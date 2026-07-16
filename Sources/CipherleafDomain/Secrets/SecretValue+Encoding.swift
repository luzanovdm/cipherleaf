import Foundation

extension SecretValue {
  public func encoded(prettyPrinted: Bool = false) throws -> Data {
    let rendered = try render(level: 0, prettyPrinted: prettyPrinted)
    guard let data = rendered.data(using: .utf8) else {
      throw SecretValueError.encodingFailed
    }
    return data
  }

  private func render(level: Int, prettyPrinted: Bool) throws -> String {
    switch self {
    case .object(let values):
      return try renderObject(
        values,
        level: level,
        prettyPrinted: prettyPrinted
      )
    case .array(let values):
      return try renderArray(
        values,
        level: level,
        prettyPrinted: prettyPrinted
      )
    case .string(let value):
      return try Self.renderString(value)
    case .number(let value):
      guard Self.validateNumber(value) else {
        throw SecretValueError.invalidNumber(value)
      }
      return value
    case .boolean(let value):
      return value ? "true" : "false"
    case .null:
      return "null"
    }
  }

  private func renderObject(
    _ values: [String: SecretValue],
    level: Int,
    prettyPrinted: Bool
  ) throws -> String {
    let keys = values.keys.sorted()
    guard !keys.isEmpty else {
      return "{}"
    }

    let separator = prettyPrinted ? ",\n" : ","
    let keyValueSeparator = prettyPrinted ? ": " : ":"
    let body = try keys.map { key in
      guard let value = values[key] else {
        throw SecretValueError.encodingFailed
      }
      let renderedKey = try Self.renderString(key)
      let renderedValue = try value.render(
        level: level + 1,
        prettyPrinted: prettyPrinted
      )
      let indentation =
        prettyPrinted
        ? String(repeating: "  ", count: level + 1)
        : ""
      return "\(indentation)\(renderedKey)\(keyValueSeparator)\(renderedValue)"
    }.joined(separator: separator)
    return
      "{\(prettyPrinted ? "\n" : "")\(body)\(closingIndentation(level, prettyPrinted))}"
  }

  private func renderArray(
    _ values: [SecretValue],
    level: Int,
    prettyPrinted: Bool
  ) throws -> String {
    guard !values.isEmpty else {
      return "[]"
    }

    let separator = prettyPrinted ? ",\n" : ","
    let body = try values.map { value in
      let indentation =
        prettyPrinted
        ? String(repeating: "  ", count: level + 1)
        : ""
      return try indentation
        + value.render(level: level + 1, prettyPrinted: prettyPrinted)
    }.joined(separator: separator)
    return
      "[\(prettyPrinted ? "\n" : "")\(body)\(closingIndentation(level, prettyPrinted))]"
  }

  private func closingIndentation(
    _ level: Int,
    _ prettyPrinted: Bool
  ) -> String {
    prettyPrinted ? "\n\(String(repeating: "  ", count: level))" : ""
  }

  private static func renderString(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let rendered = String(data: data, encoding: .utf8) else {
      throw SecretValueError.encodingFailed
    }
    return rendered
  }
}
