import Foundation

extension SOPSFileFormat {
  public func pathForNewValue(_ rawValue: String) throws -> SecretPath {
    let path =
      try self == .dotenv
      ? SecretPath.parseDotenvKey(rawValue)
      : SecretPath.parseEditablePath(rawValue)
    try validateEditablePath(path)
    return path
  }

  public func validateEditablePath(_ path: SecretPath) throws {
    guard path.sopsIndex != nil else {
      throw SOPSFileFormatEditingError.unaddressablePath
    }
    guard case .key(let rootKey)? = path.components.first else {
      return
    }

    switch self {
    case .yaml, .json:
      guard rootKey != "sops" else {
        throw SOPSFileFormatEditingError.reservedMetadataPath
      }
    case .dotenv:
      guard path.depth == 1 else {
        throw SOPSFileFormatEditingError.dotenvRequiresFlatValues
      }
      guard !rootKey.hasPrefix("sops_") else {
        throw SOPSFileFormatEditingError.reservedMetadataPath
      }
    }
  }

  public func validateCandidateRoot(_ root: SecretValue) throws {
    guard case .object(let values) = root else {
      throw SecretValueError.documentRootMustBeObject
    }

    switch self {
    case .yaml, .json:
      guard values["sops"] == nil else {
        throw SOPSFileFormatEditingError.reservedMetadataPath
      }
    case .dotenv:
      guard !values.keys.contains(where: { $0.hasPrefix("sops_") }) else {
        throw SOPSFileFormatEditingError.reservedMetadataPath
      }
      guard values.values.allSatisfy({ $0.scalarKind != nil }) else {
        throw SOPSFileFormatEditingError.dotenvRequiresFlatValues
      }
    }
  }
}

public enum SOPSFileFormatEditingError: LocalizedError {
  case dotenvRequiresFlatValues
  case reservedMetadataPath
  case unaddressablePath

  public var errorDescription: String? {
    switch self {
    case .dotenvRequiresFlatValues:
      "dotenv documents support only scalar values at one-level keys."
    case .reservedMetadataPath:
      "That path is reserved for SOPS metadata."
    case .unaddressablePath:
      "SOPS set and unset cannot safely address this path. The value is read-only."
    }
  }
}
