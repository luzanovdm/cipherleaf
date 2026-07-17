import CipherleafDomain
import Foundation

struct SOPSMetadataParser: Sendable {
  private let supportedScalarKeys: Set<String> = [
    "encrypted_comment_regex",
    "encrypted_regex",
    "encrypted_suffix",
    "lastmodified",
    "mac",
    "mac_only_encrypted",
    "shamir_threshold",
    "unencrypted_comment_regex",
    "unencrypted_regex",
    "unencrypted_suffix",
    "version",
  ]
  private let unsupportedRecipientKeys: Set<String> = [
    "azure_kv",
    "gcp_kms",
    "hc_vault",
    "hckms",
    "key_groups",
    "kms",
    "pgp",
  ]

  func parse(
    _ data: Data,
    format: SOPSFileFormat
  ) throws -> [AgeRecipient] {
    let values: [String]
    switch format {
    case .yaml:
      values = try parseYAML(data)
    case .json:
      values = try parseJSON(data)
    case .dotenv:
      values = try parseDotenv(data)
    }

    let recipients = try Set(values.map(makeRecipient)).sorted {
      $0.value < $1.value
    }
    guard !recipients.isEmpty else {
      throw SOPSMetadataError.noAgeRecipients
    }
    return recipients
  }

  private func parseJSON(_ data: Data) throws -> [String] {
    let value: Any
    do {
      value = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw SOPSMetadataError.malformedMetadata
    }
    guard
      let root = value as? [String: Any],
      let metadata = root["sops"] as? [String: Any]
    else {
      throw SOPSMetadataError.malformedMetadata
    }

    try validateMetadataKeys(metadata)
    for key in unsupportedRecipientKeys {
      if let value = metadata[key], hasContent(value) {
        throw SOPSMetadataError.unsupportedRecipientType
      }
    }

    guard let ageEntries = metadata["age"] as? [Any] else {
      return []
    }
    return try ageEntries.map { entry in
      guard
        let entry = entry as? [String: Any],
        let recipient = entry["recipient"] as? String
      else {
        throw SOPSMetadataError.malformedMetadata
      }
      return recipient
    }
  }

  private func parseYAML(_ data: Data) throws -> [String] {
    guard let text = String(data: data, encoding: .utf8) else {
      throw SOPSMetadataError.notUTF8
    }
    let lines = text.split(
      omittingEmptySubsequences: false,
      whereSeparator: \.isNewline
    ).map(String.init)
    let sopsIndices = lines.indices.filter {
      indentation(of: lines[$0]) == 0
        && lines[$0].trimmingCharacters(in: .whitespaces) == "sops:"
    }
    guard sopsIndices.count == 1, let sopsIndex = sopsIndices.first else {
      throw SOPSMetadataError.malformedMetadata
    }

    let metadataLines = Array(
      lines.dropFirst(sopsIndex + 1).prefix { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
          || trimmed.hasPrefix("#")
          || indentation(of: line) > 0
      }
    )
    let contentLines = metadataLines.filter {
      let trimmed = $0.trimmingCharacters(in: .whitespaces)
      return !trimmed.isEmpty && !trimmed.hasPrefix("#")
    }
    guard
      let childIndent = contentLines.map(indentation).min(),
      childIndent > 0
    else {
      return []
    }

    var sections: [(key: String, lines: [String])] = []
    for line in contentLines {
      if indentation(of: line) == childIndent,
        let key = yamlKey(in: line)
      {
        sections.append((key, [line]))
      } else if !sections.isEmpty {
        sections[sections.count - 1].lines.append(line)
      } else {
        throw SOPSMetadataError.malformedMetadata
      }
    }

    var recipients: [String] = []
    var seenKeys = Set<String>()
    for section in sections {
      guard seenKeys.insert(section.key).inserted else {
        throw SOPSMetadataError.malformedMetadata
      }
      if unsupportedRecipientKeys.contains(section.key) {
        if yamlSectionHasContent(section.lines) {
          throw SOPSMetadataError.unsupportedRecipientType
        }
        continue
      }
      guard section.key == "age" || supportedScalarKeys.contains(section.key)
      else {
        throw SOPSMetadataError.malformedMetadata
      }
      guard section.key == "age" else {
        continue
      }

      for line in section.lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let candidate =
          trimmed.hasPrefix("- recipient:")
          ? String(trimmed.dropFirst("- recipient:".count))
          : trimmed.hasPrefix("recipient:")
            ? String(trimmed.dropFirst("recipient:".count))
            : nil
        if let candidate {
          recipients.append(unquoted(candidate))
        }
      }
    }
    return recipients
  }

  private func parseDotenv(_ data: Data) throws -> [String] {
    guard let text = String(data: data, encoding: .utf8) else {
      throw SOPSMetadataError.notUTF8
    }

    var recipients: [String] = []
    var seenMetadataKeys = Set<String>()
    for line in text.split(whereSeparator: \.isNewline) {
      let line = String(line)
      guard let separator = line.firstIndex(of: "=") else {
        continue
      }
      let key = String(line[..<separator])
      let value = String(line[line.index(after: separator)...])
      if key.hasPrefix("sops_"),
        !seenMetadataKeys.insert(key).inserted
      {
        throw SOPSMetadataError.malformedMetadata
      }

      if key.range(
        of: #"^sops_age__list_[0-9]+__map_recipient$"#,
        options: .regularExpression
      ) != nil {
        recipients.append(unquoted(value))
        continue
      }
      if key.hasPrefix("sops_age__") {
        guard
          key.range(
            of: #"^sops_age__list_[0-9]+__map_enc$"#,
            options: .regularExpression
          ) != nil
        else {
          throw SOPSMetadataError.malformedMetadata
        }
        continue
      }

      guard key.hasPrefix("sops_") else {
        continue
      }
      let metadataKey = String(key.dropFirst("sops_".count))
      if unsupportedRecipientKeys.contains(where: {
        metadataKey == $0 || metadataKey.hasPrefix("\($0)__")
      }) {
        throw SOPSMetadataError.unsupportedRecipientType
      }
      guard supportedScalarKeys.contains(metadataKey) else {
        throw SOPSMetadataError.malformedMetadata
      }
    }
    return recipients
  }

  private func validateMetadataKeys(_ metadata: [String: Any]) throws {
    for key in metadata.keys {
      guard
        key == "age"
          || supportedScalarKeys.contains(key)
          || unsupportedRecipientKeys.contains(key)
      else {
        throw SOPSMetadataError.malformedMetadata
      }
    }
  }

  private func yamlKey(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let separator = trimmed.firstIndex(of: ":") else {
      return nil
    }
    let key = String(trimmed[..<separator])
    guard
      key.range(
        of: #"^[A-Za-z][A-Za-z0-9_]*$"#,
        options: .regularExpression
      ) != nil
    else {
      return nil
    }
    return key
  }

  private func yamlSectionHasContent(_ lines: [String]) -> Bool {
    guard let first = lines.first,
      let separator = first.firstIndex(of: ":")
    else {
      return true
    }
    let inlineValue = first[first.index(after: separator)...]
      .trimmingCharacters(in: .whitespaces)
    if !inlineValue.isEmpty, inlineValue != "[]", inlineValue != "{}" {
      return true
    }
    return lines.dropFirst().contains {
      let value = $0.trimmingCharacters(in: .whitespaces)
      return !value.isEmpty && !value.hasPrefix("#")
    }
  }

  private func indentation(of line: String) -> Int {
    line.prefix(while: { $0 == " " }).count
  }

  private func unquoted(_ rawValue: String) -> String {
    let value = rawValue.trimmingCharacters(in: .whitespaces)
    guard value.count >= 2,
      let first = value.first,
      let last = value.last,
      (first == "\"" && last == "\"") || (first == "'" && last == "'")
    else {
      return value
    }
    return String(value.dropFirst().dropLast())
  }

  private func hasContent(_ value: Any) -> Bool {
    switch value {
    case is NSNull:
      false
    case let array as [Any]:
      !array.isEmpty
    case let dictionary as [String: Any]:
      !dictionary.isEmpty
    case let string as String:
      !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    default:
      true
    }
  }

  private func makeRecipient(_ value: String) throws -> AgeRecipient {
    do {
      return try AgeRecipient(value)
    } catch {
      throw SOPSMetadataError.unsupportedRecipientType
    }
  }
}

enum SOPSMetadataError: Equatable, LocalizedError {
  case malformedMetadata
  case noAgeRecipients
  case notUTF8
  case unsupportedRecipientType

  var errorDescription: String? {
    switch self {
    case .malformedMetadata:
      "The encrypted document contains unsupported or malformed SOPS metadata."
    case .noAgeRecipients:
      "The encrypted document does not contain native age recipients."
    case .notUTF8:
      "The encrypted document is not UTF-8 text."
    case .unsupportedRecipientType:
      "Cipherleaf supports documents encrypted exclusively for native age recipients."
    }
  }
}
