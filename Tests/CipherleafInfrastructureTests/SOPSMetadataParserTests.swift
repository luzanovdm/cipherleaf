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

    let recipients = try SOPSMetadataParser().parse(data, format: .yaml)

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
      try SOPSMetadataParser().parse(
        Data("sops: {}".utf8),
        format: .yaml
      )
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
      try SOPSMetadataParser().parse(data, format: .json).map(\.value),
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
      try SOPSMetadataParser().parse(data, format: .dotenv).map(\.value),
      ["age1zzzzzzzzzzzzzzzzzzzzzzzzzzzz"]
    )
  }

  func testDoesNotTreatUserJSONRecipientKeyAsMetadata() {
    let data = Data(
      #"""
      {"recipient":"age1qqqqqqqqqqqqqqqqqqqqqqqqqqqq","sops":{}}
      """#.utf8
    )

    XCTAssertThrowsError(
      try SOPSMetadataParser().parse(data, format: .json)
    ) { error in
      XCTAssertEqual(
        error as? SOPSMetadataError,
        .noAgeRecipients
      )
    }
  }

  func testRejectsMixedRecipientTypes() {
    let data = Data(
      """
      sops:
          age:
              - recipient: age1aaaaaaaaaaaaaaaaaaaaaaaaaaaa
                enc: synthetic
          pgp:
              - fp: 0000000000000000
                enc: synthetic
      """.utf8
    )

    XCTAssertThrowsError(
      try SOPSMetadataParser().parse(data, format: .yaml)
    ) { error in
      XCTAssertEqual(
        error as? SOPSMetadataError,
        .unsupportedRecipientType
      )
    }
  }

  func testRejectsSSHRecipientInAgeMetadata() {
    let data = Data(
      #"""
      {
        "sops": {
          "age": [
            {
              "recipient": "ssh-ed25519 synthetic"
            }
          ]
        }
      }
      """#.utf8
    )

    XCTAssertThrowsError(
      try SOPSMetadataParser().parse(data, format: .json)
    ) { error in
      XCTAssertEqual(
        error as? SOPSMetadataError,
        .unsupportedRecipientType
      )
    }
  }

  func testRejectsDuplicateYAMLMetadataSections() {
    let data = Data(
      """
      sops:
          age:
              - recipient: age1aaaaaaaaaaaaaaaaaaaaaaaaaaaa
                enc: synthetic
          age:
              - recipient: age1zzzzzzzzzzzzzzzzzzzzzzzzzzzz
                enc: synthetic
      """.utf8
    )

    XCTAssertThrowsError(
      try SOPSMetadataParser().parse(data, format: .yaml)
    ) { error in
      XCTAssertEqual(
        error as? SOPSMetadataError,
        .malformedMetadata
      )
    }
  }
}
