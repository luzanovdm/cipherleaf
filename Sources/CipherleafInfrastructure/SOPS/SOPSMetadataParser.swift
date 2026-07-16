import CipherleafDomain
import Foundation

struct SOPSMetadataParser: Sendable {
  func parse(_ data: Data) throws -> [AgeRecipient] {
    guard let text = String(data: data, encoding: .utf8) else {
      throw SOPSMetadataError.notUTF8
    }

    let expression = try NSRegularExpression(
      pattern: #"(?i)recipient[^\n\r]*?(age1[a-z0-9]+)"#
    )
    let range = NSRange(text.startIndex..., in: text)
    let values = expression.matches(in: text, range: range).compactMap {
      match -> String? in
      guard let recipientRange = Range(match.range(at: 1), in: text) else {
        return nil
      }
      return String(text[recipientRange])
    }

    let recipients = try Set(values).map(AgeRecipient.init).sorted {
      $0.value < $1.value
    }
    guard !recipients.isEmpty else {
      throw SOPSMetadataError.noAgeRecipients
    }
    return recipients
  }
}

enum SOPSMetadataError: LocalizedError {
  case noAgeRecipients
  case notUTF8

  var errorDescription: String? {
    switch self {
    case .noAgeRecipients:
      "The encrypted document does not contain native age recipients."
    case .notUTF8:
      "The encrypted document is not UTF-8 text."
    }
  }
}
