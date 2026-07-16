import XCTest

@testable import CipherleafInfrastructure

final class SOPSMetadataParserTests: XCTestCase {
  func testParsesAndSortsAgeRecipients() throws {
    let data = Data(
      """
      value: ENC[AES256_GCM,data:synthetic]
      sops:
          age:
              - recipient: age1zzzzzzzzzzzzzzzzzzzzzzzzzzzz
                enc: synthetic
              - recipient: age1aaaaaaaaaaaaaaaaaaaaaaaaaaaa
                enc: synthetic
      """.utf8
    )

    let recipients = try SOPSMetadataParser().parse(data)

    XCTAssertEqual(
      recipients.map(\.value),
      [
        "age1aaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "age1zzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      ]
    )
  }

  func testRejectsDocumentWithoutAgeRecipients() {
    XCTAssertThrowsError(
      try SOPSMetadataParser().parse(Data("sops: {}".utf8))
    )
  }

  func testParsesJSONRecipientMetadata() throws {
    let data = Data(
      #"""
      {
        "sops": {
          "age": [
            {
              "recipient": "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqq"
            }
          ]
        }
      }
      """#.utf8
    )

    XCTAssertEqual(
      try SOPSMetadataParser().parse(data).map(\.value),
      ["age1qqqqqqqqqqqqqqqqqqqqqqqqqqqq"]
    )
  }

  func testParsesDotenvRecipientMetadata() throws {
    let data = Data(
      """
      sops_age__list_0__map_recipient=age1zzzzzzzzzzzzzzzzzzzzzzzzzzzz
      """.utf8
    )

    XCTAssertEqual(
      try SOPSMetadataParser().parse(data).map(\.value),
      ["age1zzzzzzzzzzzzzzzzzzzzzzzzzzzz"]
    )
  }
}
