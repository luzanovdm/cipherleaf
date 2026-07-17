import XCTest

@testable import CipherleafDomain

final class SOPSFileFormatEditingTests: XCTestCase {
  func testDotenvNewPathUsesOneFlatKey() throws {
    let path = try SOPSFileFormat.dotenv.pathForNewValue("SERVICE.TOKEN")

    XCTAssertEqual(path.components, [.key("SERVICE.TOKEN")])
  }

  func testDotenvRejectsNestedCandidate() {
    let root = SecretValue.object([
      "SERVICE": .object([
        "TOKEN": .string("synthetic")
      ])
    ])

    XCTAssertThrowsError(
      try SOPSFileFormat.dotenv.validateCandidateRoot(root)
    ) { error in
      XCTAssertFalse(error.localizedDescription.contains("synthetic"))
    }
  }

  func testFormatsRejectTheirReservedMetadataPaths() {
    XCTAssertThrowsError(
      try SOPSFileFormat.yaml.validateEditablePath(
        SecretPath(components: [.key("sops"), .key("mac")])
      )
    )
    XCTAssertThrowsError(
      try SOPSFileFormat.json.validateEditablePath(
        SecretPath(components: [.key("sops")])
      )
    )
    XCTAssertThrowsError(
      try SOPSFileFormat.dotenv.validateEditablePath(
        SecretPath(components: [.key("sops_mac")])
      )
    )
  }

  func testUnaddressableExistingPathIsReadOnly() {
    XCTAssertThrowsError(
      try SOPSFileFormat.json.validateEditablePath(
        SecretPath(components: [.key("left[bracket")])
      )
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("read-only"))
    }
  }
}
