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

    _ = try transaction.commit(
      expectedData: Data("new-ciphertext".utf8)
    )

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

  func testCommitReassertsPrivateModeAfterStagingMutation() throws {
    let fixture = try TemporaryDirectory()
    let target = fixture.url.appendingPathComponent("secrets.sops.yaml")
    let expectedData = Data("new-ciphertext".utf8)
    try Data("old-ciphertext".utf8).write(to: target)
    let transaction = try AtomicFileTransaction.stage(
      Data("initial-ciphertext".utf8),
      for: target
    )
    try expectedData.write(to: transaction.stagedURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: transaction.stagedURL.path
    )

    _ = try transaction.commit(expectedData: expectedData)

    let attributes = try FileManager.default.attributesOfItem(
      atPath: target.path
    )
    XCTAssertEqual(
      (attributes[.posixPermissions] as? NSNumber)?.intValue,
      0o600
    )
  }

  func testCommitRejectsStagingDataChangedAfterVerification() throws {
    let fixture = try TemporaryDirectory()
    let target = fixture.url.appendingPathComponent("secrets.sops.yaml")
    try Data("old-ciphertext".utf8).write(to: target)
    let transaction = try AtomicFileTransaction.stage(
      Data("reviewed-ciphertext".utf8),
      for: target
    )
    try Data("changed-ciphertext!".utf8).write(to: transaction.stagedURL)

    XCTAssertThrowsError(
      try transaction.commit(
        expectedData: Data("reviewed-ciphertext".utf8)
      )
    )
    XCTAssertEqual(
      try Data(contentsOf: target),
      Data("old-ciphertext".utf8)
    )
  }
}
