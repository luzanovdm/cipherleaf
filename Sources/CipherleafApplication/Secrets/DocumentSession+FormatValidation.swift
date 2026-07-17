import CipherleafDomain
import Foundation

extension DocumentSession {
  public func pathForNewValue(_ rawValue: String) throws -> SecretPath {
    guard phase == .open else {
      throw DocumentSessionError.documentBusy
    }
    guard let format else {
      throw DocumentSessionError.noOpenDocument
    }
    return try format.pathForNewValue(rawValue)
  }

  public func canRename(at path: SecretPath) -> Bool {
    guard canEdit(at: path),
      case .key = path.components.last
    else {
      return false
    }
    return format == .dotenv ? path.depth == 1 : true
  }

  public func isValidRenameKey(_ rawValue: String, at path: SecretPath) -> Bool {
    guard let rename = try? renameDestination(at: path, rawValue: rawValue),
      rename.path != path,
      document?.value(at: rename.path) == nil
    else {
      return false
    }
    return true
  }

  public func canEdit(at path: SecretPath) -> Bool {
    guard phase == .open,
      document?.value(at: path) != nil,
      let format
    else {
      return false
    }
    return (try? format.validateEditablePath(path)) != nil
  }

  func validateEditablePath(_ path: SecretPath) throws {
    guard phase == .open else {
      throw DocumentSessionError.documentBusy
    }
    guard let format else {
      throw DocumentSessionError.noOpenDocument
    }
    try format.validateEditablePath(path)
  }

  func renameDestination(
    at path: SecretPath,
    rawValue: String
  ) throws -> (path: SecretPath, key: String) {
    guard canRename(at: path) else {
      throw SecretValueError.renameUnsupported
    }
    guard let format, let parent = path.parent else {
      throw SecretValueError.renameUnsupported
    }
    let keyPath =
      try format == .dotenv
      ? SecretPath.parseDotenvKey(rawValue)
      : SecretPath.parseEditablePath(rawValue)
    guard keyPath.components.count == 1,
      case .key(let key) = keyPath.components[0]
    else {
      throw SecretValueError.renameUnsupported
    }
    let destination = parent.appending(.key(key))
    try format.validateEditablePath(destination)
    return (destination, key)
  }
}
