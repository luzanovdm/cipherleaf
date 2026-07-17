import Darwin
import Foundation

struct FileSafetyValidator: Sendable {
  private let maximumIdentityBytes = 1_024 * 1_024
  private let maximumManifestBytes = 32 * 1_024 * 1_024

  func validateManifest(_ url: URL) throws {
    let information = try inspect(url)
    guard information.isRegularFile else {
      throw FileSafetyError.notRegularFile(url)
    }
    guard information.byteCount <= maximumManifestBytes else {
      throw FileSafetyError.manifestTooLarge(
        url,
        maximumBytes: maximumManifestBytes
      )
    }
  }

  func readManifest(_ url: URL) throws -> ManifestSnapshot {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else {
        return Int32(-1)
      }
      return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      throw FileSafetyError.cannotRead(url, errno)
    }
    defer {
      _ = Darwin.close(descriptor)
    }

    var before = stat()
    guard Darwin.fstat(descriptor, &before) == 0 else {
      throw FileSafetyError.cannotInspect(url, errno)
    }
    try validateManifest(url, information: before)

    var data = Data()
    data.reserveCapacity(Int(before.st_size))
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

    while true {
      let bytesRead = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
      }
      if bytesRead < 0, errno == EINTR {
        continue
      }
      guard bytesRead >= 0 else {
        throw FileSafetyError.cannotRead(url, errno)
      }
      guard bytesRead > 0 else {
        break
      }
      guard data.count + bytesRead <= maximumManifestBytes else {
        throw FileSafetyError.manifestTooLarge(
          url,
          maximumBytes: maximumManifestBytes
        )
      }
      data.append(contentsOf: buffer.prefix(bytesRead))
    }

    var after = stat()
    guard Darwin.fstat(descriptor, &after) == 0 else {
      throw FileSafetyError.cannotInspect(url, errno)
    }

    var currentPath = stat()
    let pathResult = url.withUnsafeFileSystemRepresentation { path in
      guard let path else {
        return Int32(-1)
      }
      return Darwin.lstat(path, &currentPath)
    }
    guard pathResult == 0 else {
      throw FileSafetyError.cannotInspect(url, errno)
    }
    guard
      isSameSnapshot(before, after),
      isSameFile(after, currentPath),
      currentPath.st_mode & S_IFMT != S_IFLNK
    else {
      throw FileSafetyError.changedDuringRead(url)
    }

    return ManifestSnapshot(
      data: data,
      modifiedAt: modificationDate(after)
    )
  }

  func validateIdentity(_ url: URL) throws {
    try validateIdentityCandidate(url)
    try validateIdentityPermissions(url)
  }

  func validateIdentityCandidate(_ url: URL) throws {
    let information = try inspect(url)
    guard information.isRegularFile else {
      throw FileSafetyError.notRegularFile(url)
    }
    guard information.byteCount <= maximumIdentityBytes else {
      throw FileSafetyError.identityTooLarge(
        url,
        maximumBytes: maximumIdentityBytes
      )
    }
  }

  func validateIdentityPermissions(_ url: URL) throws {
    let information = try inspect(url)
    guard information.permissions & 0o077 == 0 else {
      throw FileSafetyError.identityPermissionsTooBroad(url)
    }
  }

  private func inspect(_ url: URL) throws -> FileInformation {
    var information = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else {
        return Int32(-1)
      }
      return Darwin.lstat(path, &information)
    }
    guard result == 0 else {
      throw FileSafetyError.cannotInspect(url, errno)
    }

    let fileType = information.st_mode & S_IFMT
    guard fileType != S_IFLNK else {
      throw FileSafetyError.symbolicLink(url)
    }

    return FileInformation(
      isRegularFile: fileType == S_IFREG,
      byteCount: Int(information.st_size),
      permissions: Int(information.st_mode & 0o777)
    )
  }

  private func validateManifest(_ url: URL, information: stat) throws {
    guard information.st_mode & S_IFMT == S_IFREG else {
      throw FileSafetyError.notRegularFile(url)
    }
    guard information.st_size >= 0,
      information.st_size <= off_t(maximumManifestBytes)
    else {
      throw FileSafetyError.manifestTooLarge(
        url,
        maximumBytes: maximumManifestBytes
      )
    }
  }

  private func isSameFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
  }

  private func isSameSnapshot(_ lhs: stat, _ rhs: stat) -> Bool {
    isSameFile(lhs, rhs)
      && lhs.st_size == rhs.st_size
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
  }

  private func modificationDate(_ information: stat) -> Date {
    Date(
      timeIntervalSince1970:
        TimeInterval(information.st_mtimespec.tv_sec)
        + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000
    )
  }
}

struct ManifestSnapshot: Sendable {
  let data: Data
  let modifiedAt: Date
}

private struct FileInformation {
  let isRegularFile: Bool
  let byteCount: Int
  let permissions: Int
}

enum FileSafetyError: LocalizedError {
  case cannotRead(URL, Int32)
  case cannotInspect(URL, Int32)
  case changedDuringRead(URL)
  case identityPermissionsTooBroad(URL)
  case identityTooLarge(URL, maximumBytes: Int)
  case manifestTooLarge(URL, maximumBytes: Int)
  case notRegularFile(URL)
  case symbolicLink(URL)

  var errorDescription: String? {
    switch self {
    case .cannotRead(let url, let code):
      "Could not safely read \(url.lastPathComponent) (errno \(code))."
    case .cannotInspect(let url, let code):
      "Could not inspect \(url.lastPathComponent) (errno \(code))."
    case .changedDuringRead(let url):
      "\(url.lastPathComponent) changed while it was being read. Try again after other editors finish."
    case .identityPermissionsTooBroad(let url):
      "The age identity \(url.lastPathComponent) is readable by a group or other users. Set its permissions to 0600 before using it."
    case .identityTooLarge(let url, let maximumBytes):
      "The age identity \(url.lastPathComponent) is larger than the \(maximumBytes / 1_024) KB safety limit."
    case .manifestTooLarge(let url, let maximumBytes):
      "\(url.lastPathComponent) is larger than the \(maximumBytes / 1_024 / 1_024) MB safety limit."
    case .notRegularFile(let url):
      "\(url.lastPathComponent) is not a regular file."
    case .symbolicLink(let url):
      "\(url.lastPathComponent) is a symbolic link. Choose the real file instead."
    }
  }
}
