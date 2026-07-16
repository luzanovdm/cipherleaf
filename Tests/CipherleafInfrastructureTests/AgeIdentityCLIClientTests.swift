import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class AgeIdentityCLIClientTests: XCTestCase {
  func testInspectDerivesPublicRecipientFromNativeIdentity() async throws {
    let fixture = try await SOPSIntegrationFixture()

    let recipients = try await fixture.identityClient.inspect(
      fixture.identityURL
    )

    XCTAssertEqual(recipients.count, 1)
    XCTAssertTrue(recipients[0].value.hasPrefix("age1"))
  }

  func testInspectRejectsOrdinaryYAMLFile() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let yamlURL = fixture.temporaryURL(named: "synthetic-config.yaml")
    try Data("synthetic: value\n".utf8).write(to: yamlURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: yamlURL.path
    )

    do {
      _ = try await fixture.identityClient.inspect(yamlURL)
      XCTFail("Expected the YAML file to be rejected.")
    } catch {
      XCTAssertTrue(
        error.localizedDescription.contains(
          "does not contain a native age identity"
        )
      )
    }
  }

  func testInspectRejectsBroadPermissionsForNativeIdentity() async throws {
    let fixture = try await SOPSIntegrationFixture()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: fixture.identityURL.path
    )

    do {
      _ = try await fixture.identityClient.inspect(fixture.identityURL)
      XCTFail("Expected the broadly readable identity to be rejected.")
    } catch {
      XCTAssertTrue(
        error.localizedDescription.contains(
          "readable by a group or other users"
        )
      )
    }
  }
}
