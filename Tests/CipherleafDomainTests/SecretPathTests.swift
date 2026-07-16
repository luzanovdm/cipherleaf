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
}
