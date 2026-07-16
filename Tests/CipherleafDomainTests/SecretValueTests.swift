import XCTest

@testable import CipherleafDomain

final class SecretValueTests: XCTestCase {
  func testEncodingUsesStableKeyOrder() throws {
    let value = SecretValue.object([
      "zeta": .string("last"),
      "alpha": .number("12.50"),
      "nested": .object([
        "enabled": .boolean(true)
      ]),
    ])

    let encoded = try XCTUnwrap(String(data: value.encoded(), encoding: .utf8))

    XCTAssertEqual(
      encoded,
      #"{"alpha":12.50,"nested":{"enabled":true},"zeta":"last"}"#
    )
  }

  func testAddingRenamingAndRemovingNestedValue() throws {
    let original = SecretValue.object([:])
    let path = try SecretPath.parseEditablePath("database.password")
    let added = try original.adding(.string("synthetic-secret"), at: path)

    XCTAssertEqual(added.value(at: path), .string("synthetic-secret"))

    let renamed = try added.renaming(at: path, to: "credential")
    let renamedPath = try SecretPath.parseEditablePath("database.credential")
    XCTAssertEqual(renamed.value(at: renamedPath), .string("synthetic-secret"))

    let removed = try renamed.removing(at: renamedPath)
    XCTAssertNil(removed.value(at: renamedPath))
  }

  func testDocumentRootMustBeObject() throws {
    XCTAssertThrowsError(
      try SecretValue.decodeDocument(Data(#"["synthetic"]"#.utf8))
    )
  }

  func testGenerationIncrementsOnlyForNumericRootValue() {
    let original = SecretValue.object([
      "generation": .number("41"),
      "secret": .string("synthetic"),
    ])

    let result = original.incrementingRootGeneration()

    XCTAssertEqual(result.generation, 42)
    XCTAssertEqual(
      result.value.value(
        at: SecretPath(components: [.key("generation")])
      ),
      .number("42")
    )
  }

  func testGenerationOverflowLeavesDocumentUnchanged() {
    let original = SecretValue.object([
      "generation": .number(String(Int.max))
    ])

    let result = original.incrementingRootGeneration()

    XCTAssertNil(result.generation)
    XCTAssertEqual(result.value, original)
  }

  func testInvalidNumberErrorDoesNotExposeInput() {
    let sensitiveInput = "synthetic-sensitive-input"

    XCTAssertThrowsError(
      try SecretValue.number(sensitiveInput).encoded()
    ) { error in
      XCTAssertFalse(
        error.localizedDescription.contains(sensitiveInput)
      )
    }
  }
}
