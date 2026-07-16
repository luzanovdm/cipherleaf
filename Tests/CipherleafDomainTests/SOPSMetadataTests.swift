import XCTest

@testable import CipherleafDomain

final class SOPSMetadataTests: XCTestCase {
  func testAcceptsNativeAgeRecipient() throws {
    let value =
      "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"

    XCTAssertEqual(try AgeRecipient(value).value, value)
  }

  func testRejectsMalformedAgeRecipient() {
    XCTAssertThrowsError(
      try AgeRecipient("age1contains-invalid-uppercase")
    )
    XCTAssertThrowsError(
      try AgeRecipient("ssh-ed25519 synthetic")
    )
  }

  func testRecognizesHiddenDotenvFilename() throws {
    XCTAssertEqual(
      try SOPSFileFormat(
        url: URL(fileURLWithPath: "/tmp/.env")
      ),
      .dotenv
    )
  }
}
