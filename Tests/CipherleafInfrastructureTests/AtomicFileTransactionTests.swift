import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class AtomicFileTransactionTests: XCTestCase {
  func testCommitReplacesTargetWithMode0600() throws {
    let fixture = try TemporaryDirectory()
    let target = fixture.url.appendingPathComponent("secrets.sops.yaml")
    try Data("old-ciphertext".utf8).write(to: target)
    let transaction = try AtomicFileTransaction.stage(
      Data("new-ciphertext".utf8),
      for: target
    )

    try transaction.commit()

    XCTAssertEqual(
      try Data(contentsOf: target),
      Data("new-ciphertext".utf8)
    )
    let attributes = try FileManager.default.attributesOfItem(
      atPath: target.path
    )
    XCTAssertEqual(
      (attributes[.posixPermissions] as? NSNumber)?.intValue,
      0o600
    )
  }

  func testUncommittedTransactionPreservesTarget() throws {
    let fixture = try TemporaryDirectory()
    let target = fixture.url.appendingPathComponent("secrets.sops.yaml")
    try Data("old-ciphertext".utf8).write(to: target)

    do {
      _ = try AtomicFileTransaction.stage(
        Data("new-ciphertext".utf8),
        for: target
      )
    }

    XCTAssertEqual(
      try Data(contentsOf: target),
      Data("old-ciphertext".utf8)
    )
  }
}
