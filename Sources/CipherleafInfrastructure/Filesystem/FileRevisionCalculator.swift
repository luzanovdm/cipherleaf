import CipherleafApplication
import CryptoKit
import Foundation

struct FileRevisionCalculator: Sendable {
  func revision(for data: Data, at url: URL) throws -> FileRevision {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let digest = SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()

    return FileRevision(
      digest: digest,
      byteCount: data.count,
      modifiedAt: attributes[.modificationDate] as? Date
    )
  }
}
