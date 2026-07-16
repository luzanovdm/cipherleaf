import CoreFoundation
import Foundation

public enum SecretScalarKind: String, CaseIterable, Identifiable, Sendable {
  case string
  case number
  case boolean
  case null

  public var id: String {
    rawValue
  }

  public var title: String {
    switch self {
    case .string:
      "Text"
    case .number:
      "Number"
    case .boolean:
      "Boolean"
    case .null:
      "Null"
    }
  }
}

public enum SecretValue: Equatable, Sendable {
  case object([String: SecretValue])
  case array([SecretValue])
  case string(String)
  case number(String)
  case boolean(Bool)
  case null

  public static func decodeDocument(_ data: Data) throws -> SecretValue {
    let value = try JSONSerialization.jsonObject(with: data)
    let decoded = try decodeFoundationValue(value)
    guard case .object = decoded else {
      throw SecretValueError.documentRootMustBeObject
    }
    return decoded
  }

  public var scalarKind: SecretScalarKind? {
    switch self {
    case .string:
      .string
    case .number:
      .number
    case .boolean:
      .boolean
    case .null:
      .null
    case .object, .array:
      nil
    }
  }

  public var kindName: String {
    switch self {
    case .object:
      "Object"
    case .array:
      "Array"
    case .string:
      "Text"
    case .number:
      "Number"
    case .boolean:
      "Boolean"
    case .null:
      "Null"
    }
  }

  public static func defaultValue(for kind: SecretScalarKind) -> SecretValue {
    switch kind {
    case .string:
      .string("")
    case .number:
      .number("0")
    case .boolean:
      .boolean(false)
    case .null:
      .null
    }
  }

  public static func validateNumber(_ rawValue: String) -> Bool {
    guard let data = rawValue.data(using: .utf8),
      let decoded = try? JSONSerialization.jsonObject(
        with: data,
        options: [.fragmentsAllowed]
      ),
      let number = decoded as? NSNumber
    else {
      return false
    }

    return CFGetTypeID(number) != CFBooleanGetTypeID()
  }

  private static func decodeFoundationValue(_ value: Any) throws -> SecretValue {
    if value is NSNull {
      return .null
    }
    if let dictionary = value as? [String: Any] {
      return .object(try dictionary.mapValues(decodeFoundationValue))
    }
    if let array = value as? [Any] {
      return .array(try array.map(decodeFoundationValue))
    }
    if let string = value as? String {
      return .string(string)
    }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .boolean(number.boolValue)
      }
      return .number(number.stringValue)
    }
    throw SecretValueError.unsupportedValue
  }
}

public struct SecretEntry: Identifiable, Hashable, Sendable {
  public let path: SecretPath
  public let kind: SecretScalarKind

  public init(path: SecretPath, kind: SecretScalarKind) {
    self.path = path
    self.kind = kind
  }

  public var id: SecretPath {
    path
  }
}

public enum SecretValueError: LocalizedError {
  case arrayInsertionUnsupported
  case cannotRemoveRoot
  case cannotReplaceRoot
  case documentRootMustBeObject
  case encodingFailed
  case expectedObject
  case invalidNumber(String)
  case pathAlreadyExists
  case pathNotFound
  case renameUnsupported
  case unsupportedValue

  public var errorDescription: String? {
    switch self {
    case .arrayInsertionUnsupported:
      "Adding array elements is not supported from a dot path."
    case .cannotRemoveRoot:
      "The document root cannot be removed."
    case .cannotReplaceRoot:
      "The document root cannot be replaced from this action."
    case .documentRootMustBeObject:
      "Cipherleaf supports SOPS documents with an object at the root."
    case .encodingFailed:
      "The document could not be encoded as UTF-8 JSON."
    case .expectedObject:
      "A parent path is not an object."
    case .invalidNumber:
      "The value is not a valid JSON number."
    case .pathAlreadyExists:
      "A value already exists at that path."
    case .pathNotFound:
      "The selected path no longer exists."
    case .renameUnsupported:
      "Only object keys can be renamed."
    case .unsupportedValue:
      "The decrypted document contains a value that JSON cannot represent."
    }
  }
}
