import Foundation

public enum SOPSFileFormat: String, CaseIterable, Sendable {
  case yaml
  case json
  case dotenv

  public init(url: URL) throws {
    let name = url.lastPathComponent.lowercased()
    let fileExtension = url.pathExtension.lowercased()

    if fileExtension == "yaml" || fileExtension == "yml" {
      self = .yaml
    } else if fileExtension == "json" {
      self = .json
    } else if fileExtension == "env" || name == ".env" || name.hasSuffix(".dotenv") {
      self = .dotenv
    } else {
      throw SOPSFileFormatError.unsupportedExtension(fileExtension)
    }
  }

  public var title: String {
    switch self {
    case .yaml:
      "YAML"
    case .json:
      "JSON"
    case .dotenv:
      "dotenv"
    }
  }
}

public struct AgeRecipient: Hashable, Identifiable, Sendable {
  public let value: String

  public init(_ value: String) throws {
    let patterns = [
      "^age1[023456789ac-hj-np-z]{20,}$",
      "^age1pq1[023456789ac-hj-np-z]{20,}$",
    ]
    guard
      patterns.contains(where: { pattern in
        value.range(of: pattern, options: .regularExpression) != nil
      })
    else {
      throw AgeRecipientError.invalid
    }
    self.value = value
  }

  public var id: String {
    value
  }

  public var abbreviated: String {
    guard value.count > 22 else {
      return value
    }
    return "\(value.prefix(14))…\(value.suffix(8))"
  }
}

public enum AgeRecipientError: LocalizedError {
  case invalid

  public var errorDescription: String? {
    "The SOPS metadata contains an invalid native age recipient."
  }
}

public enum SOPSFileFormatError: LocalizedError {
  case unsupportedExtension(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedExtension(let fileExtension):
      "Unsupported SOPS file extension “\(fileExtension)”. Use YAML, JSON, or dotenv."
    }
  }
}
