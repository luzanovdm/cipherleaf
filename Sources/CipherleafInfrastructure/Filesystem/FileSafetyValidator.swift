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
}

private struct FileInformation {
  let isRegularFile: Bool
  let byteCount: Int
  let permissions: Int
}

enum FileSafetyError: LocalizedError {
  case cannotInspect(URL, Int32)
  case identityPermissionsTooBroad(URL)
  case identityTooLarge(URL, maximumBytes: Int)
  case manifestTooLarge(URL, maximumBytes: Int)
  case notRegularFile(URL)
  case symbolicLink(URL)

  var errorDescription: String? {
    switch self {
    case .cannotInspect(let url, let code):
      "Could not inspect \(url.lastPathComponent) (errno \(code))."
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
