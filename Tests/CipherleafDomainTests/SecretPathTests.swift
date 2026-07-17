import XCTest

@testable import CipherleafDomain

final class SecretPathTests: XCTestCase {
  func testRendersDisplayAndSOPSIndex() throws {
    let path = try SecretPath.parseEditablePath("database.password")

    XCTAssertEqual(path.display, "$.database.password")
    XCTAssertEqual(path.sopsIndex, #"["database"]["password"]"#)
  }

  func testRejectsEmptyAndAmbiguousSegments() {
    XCTAssertThrowsError(try SecretPath.parseEditablePath(""))
    XCTAssertThrowsError(try SecretPath.parseEditablePath("database..password"))
    XCTAssertThrowsError(try SecretPath.parseEditablePath("database.password value"))
  }

  func testDotenvKeyTreatsDotAsLiteralCharacter() throws {
    let path = try SecretPath.parseDotenvKey(" SERVICE.TOKEN ")

    XCTAssertEqual(path.components, [.key("SERVICE.TOKEN")])
    XCTAssertEqual(path.sopsIndex, #"["SERVICE.TOKEN"]"#)
  }

  func testDotenvKeyRejectsNestedAndReservedSyntax() {
    XCTAssertThrowsError(try SecretPath.parseDotenvKey("SERVICE=TOKEN"))
    XCTAssertThrowsError(try SecretPath.parseDotenvKey("#SERVICE"))
  }

  func testSOPSIndexUsesAlternateQuoteForQuotedKey() {
    let path = SecretPath(components: [.key("quote\"key")])

    XCTAssertEqual(path.sopsIndex, "['quote\"key']")
  }

  func testSOPSIndexRejectsUnaddressableKeySyntax() {
    XCTAssertNil(
      SecretPath(components: [.key("left[bracket")]).sopsIndex
    )
    XCTAssertNil(
      SecretPath(components: [.key("both'\"quotes")]).sopsIndex
    )
  }
}
