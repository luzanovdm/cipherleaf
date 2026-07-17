import CipherleafApplication
import CryptoKit
import Foundation

struct FileRevisionCalculator: Sendable {
  func revision(for data: Data, modifiedAt: Date?) -> FileRevision {
    let digest = SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()

    return FileRevision(
      digest: digest,
      byteCount: data.count,
      modifiedAt: modifiedAt
    )
  }
}
