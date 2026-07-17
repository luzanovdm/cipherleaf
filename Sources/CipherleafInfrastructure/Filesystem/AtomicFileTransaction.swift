import Darwin
import Foundation

final class AtomicFileTransaction {
  let stagedURL: URL

  private let targetURL: URL
  private var isFinished = false

  private init(stagedURL: URL, targetURL: URL) {
    self.stagedURL = stagedURL
    self.targetURL = targetURL
  }

  deinit {
    if !isFinished {
      try? FileManager.default.removeItem(at: stagedURL)
    }
  }

  static func stage(_ data: Data, for targetURL: URL) throws -> AtomicFileTransaction {
    let directory = targetURL.deletingLastPathComponent()
    let stagedURL = directory.appendingPathComponent(
      ".cipherleaf-\(UUID().uuidString).\(targetURL.pathExtension)"
    )
    let path = stagedURL.withUnsafeFileSystemRepresentation { pointer in
      pointer.map(String.init(cString:))
    }

    guard let path else {
      throw AtomicFileError.invalidPath
    }

    let descriptor = Darwin.open(
      path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
      throw AtomicFileError.systemCall("open", errno)
    }

    var didAttemptClose = false
    do {
      try writeAll(data, to: descriptor)
      try synchronize(descriptor)
      let closeResult = Darwin.close(descriptor)
      let closeError = errno
      didAttemptClose = true
      guard closeResult == 0 else {
        throw AtomicFileError.systemCall("close", closeError)
      }
    } catch {
      if !didAttemptClose {
        _ = Darwin.close(descriptor)
      }
      Darwin.unlink(path)
      throw error
    }

    return AtomicFileTransaction(stagedURL: stagedURL, targetURL: targetURL)
  }

  func commit(expectedData: Data) throws -> Date {
    let installedModificationDate = try prepareStagedFileForInstall(
      expectedData: expectedData
    )
    let directoryPath = targetURL.deletingLastPathComponent().path
    let directoryDescriptor = Darwin.open(
      directoryPath,
      O_RDONLY | O_CLOEXEC
    )
    guard directoryDescriptor >= 0 else {
      throw AtomicFileError.systemCall("open directory", errno)
    }
    defer {
      _ = Darwin.close(directoryDescriptor)
    }

    while true {
      let result = stagedURL.withUnsafeFileSystemRepresentation { stagedPath in
        targetURL.withUnsafeFileSystemRepresentation { targetPath in
          guard let stagedPath, let targetPath else {
            return Int32(-1)
          }
          return Darwin.rename(stagedPath, targetPath)
        }
      }
      guard result != 0 else {
        break
      }
      let errorCode = errno
      if errorCode == EINTR {
        continue
      }
      throw AtomicFileError.systemCall("rename", errorCode)
    }
    isFinished = true

    while Darwin.fsync(directoryDescriptor) != 0 {
      let errorCode = errno
      if errorCode == EINTR {
        continue
      }
      throw AtomicFileError.installedButDirectorySyncFailed(errorCode)
    }
    return installedModificationDate
  }

  private func prepareStagedFileForInstall(expectedData: Data) throws -> Date {
    let descriptor = stagedURL.withUnsafeFileSystemRepresentation { path in
      guard let path else {
        return Int32(-1)
      }
      return Darwin.open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw AtomicFileError.systemCall("open staged file", errno)
    }

    var didAttemptClose = false
    do {
      var information = stat()
      guard Darwin.fstat(descriptor, &information) == 0 else {
        throw AtomicFileError.systemCall("inspect staged file", errno)
      }
      guard information.st_mode & S_IFMT == S_IFREG,
        information.st_nlink == 1,
        information.st_size == off_t(expectedData.count)
      else {
        throw AtomicFileError.invalidStagedFile
      }
      guard
        try Self.readAll(
          from: descriptor,
          maximumBytes: expectedData.count
        ) == expectedData
      else {
        throw AtomicFileError.stagedFileChanged
      }

      while Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) != 0 {
        let errorCode = errno
        if errorCode == EINTR {
          continue
        }
        throw AtomicFileError.systemCall("chmod staged file", errorCode)
      }
      try Self.synchronize(descriptor)

      guard Darwin.fstat(descriptor, &information) == 0 else {
        throw AtomicFileError.systemCall("inspect staged file", errno)
      }
      let modificationDate = Date(
        timeIntervalSince1970:
          TimeInterval(information.st_mtimespec.tv_sec)
          + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000
      )

      let closeResult = Darwin.close(descriptor)
      let closeError = errno
      didAttemptClose = true
      guard closeResult == 0 else {
        throw AtomicFileError.systemCall("close staged file", closeError)
      }
      return modificationDate
    } catch {
      if !didAttemptClose {
        _ = Darwin.close(descriptor)
      }
      throw error
    }
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else {
        return
      }

      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if written < 0, errno == EINTR {
          continue
        }
        guard written > 0 else {
          throw AtomicFileError.systemCall(
            "write",
            written == 0 ? EIO : errno
          )
        }
        offset += written
      }
    }
  }

  private static func readAll(
    from descriptor: Int32,
    maximumBytes: Int
  ) throws -> Data {
    var data = Data()
    data.reserveCapacity(maximumBytes)
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

    while true {
      let bytesRead = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
      }
      if bytesRead < 0, errno == EINTR {
        continue
      }
      guard bytesRead >= 0 else {
        throw AtomicFileError.systemCall("read staged file", errno)
      }
      guard bytesRead > 0 else {
        return data
      }
      guard data.count + bytesRead <= maximumBytes else {
        throw AtomicFileError.stagedFileChanged
      }
      data.append(contentsOf: buffer.prefix(bytesRead))
    }
  }

  private static func synchronize(_ descriptor: Int32) throws {
    while Darwin.fsync(descriptor) != 0 {
      let errorCode = errno
      if errorCode == EINTR {
        continue
      }
      throw AtomicFileError.systemCall("fsync", errorCode)
    }
  }
}

enum AtomicFileError: LocalizedError {
  case invalidStagedFile
  case installedButDirectorySyncFailed(Int32)
  case invalidPath
  case stagedFileChanged
  case systemCall(String, Int32)

  var errorDescription: String? {
    switch self {
    case .invalidStagedFile:
      "The encrypted staging path is not a private regular file. The original file was not replaced."
    case .installedButDirectorySyncFailed(let code):
      "The encrypted file was replaced, but its directory could not be synchronized (errno \(code)). Reload the document before making more changes."
    case .invalidPath:
      "The target path cannot be represented by the filesystem."
    case .stagedFileChanged:
      "The encrypted staging file changed after verification. The original file was not replaced."
    case .systemCall(let name, let code):
      "\(name) failed with errno \(code)."
    }
  }
}
