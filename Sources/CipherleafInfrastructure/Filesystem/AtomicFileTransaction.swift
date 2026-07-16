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

  func commit() throws {
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

    while Darwin.fsync(directoryDescriptor) != 0 {
      let errorCode = errno
      if errorCode == EINTR {
        continue
      }
      throw AtomicFileError.installedButDirectorySyncFailed(errorCode)
    }
    isFinished = true
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
  case installedButDirectorySyncFailed(Int32)
  case invalidPath
  case systemCall(String, Int32)

  var errorDescription: String? {
    switch self {
    case .installedButDirectorySyncFailed(let code):
      "The encrypted file was replaced, but its directory could not be synchronized (errno \(code)). Reload the document before making more changes."
    case .invalidPath:
      "The target path cannot be represented by the filesystem."
    case .systemCall(let name, let code):
      "\(name) failed with errno \(code)."
    }
  }
}
