import Foundation

public enum SecretPathComponent: Hashable, Sendable {
  case key(String)
  case index(Int)
}

public struct SecretPath: Hashable, Identifiable, Sendable {
  public static let root = SecretPath(components: [])

  public let components: [SecretPathComponent]

  public init(components: [SecretPathComponent]) {
    self.components = components
  }

  public var id: String {
    display
  }

  public var display: String {
    components.reduce(into: "$") { result, component in
      switch component {
      case .key(let key):
        if Self.isSimpleKey(key) {
          result += ".\(key)"
        } else {
          result += "[\(Self.quoted(key))]"
        }
      case .index(let index):
        result += "[\(index)]"
      }
    }
  }

  public var sopsIndex: String {
    components.map { component in
      switch component {
      case .key(let key):
        "[\(Self.quoted(key))]"
      case .index(let index):
        "[\(index)]"
      }
    }.joined()
  }

  public var editablePath: String? {
    var keys: [String] = []
    for component in components {
      guard case .key(let key) = component, Self.isSimpleKey(key) else {
        return nil
      }
      keys.append(key)
    }
    return keys.joined(separator: ".")
  }

  public var parent: SecretPath? {
    guard !components.isEmpty else {
      return nil
    }
    return SecretPath(components: Array(components.dropLast()))
  }

  public var depth: Int {
    components.count
  }

  public func appending(_ component: SecretPathComponent) -> SecretPath {
    SecretPath(components: components + [component])
  }

  public static func parseEditablePath(_ rawValue: String) throws -> SecretPath {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let segments = trimmed.split(separator: ".", omittingEmptySubsequences: false)

    guard !trimmed.isEmpty, !segments.isEmpty else {
      throw SecretPathError.empty
    }

    let components = try segments.map { segment -> SecretPathComponent in
      let key = String(segment)
      guard isSimpleKey(key) else {
        throw SecretPathError.invalidSegment(key)
      }
      return .key(key)
    }

    return SecretPath(components: components)
  }

  private static func isSimpleKey(_ value: String) -> Bool {
    value.range(
      of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#,
      options: .regularExpression
    ) != nil
  }

  private static func quoted(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value) else {
      return "\"?\""
    }
    return String(decoding: data, as: UTF8.self)
  }
}

public enum SecretPathError: LocalizedError {
  case empty
  case invalidSegment(String)

  public var errorDescription: String? {
    switch self {
    case .empty:
      "Enter a path such as database.password."
    case .invalidSegment(let segment):
      "“\(segment)” is not a valid key segment. Use letters, numbers, underscores, or hyphens."
    }
  }
}
