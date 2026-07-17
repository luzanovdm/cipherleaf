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

  func testInspectDerivesPostQuantumRecipient() async throws {
    let fixture = try await SOPSIntegrationFixture(postQuantum: true)

    let recipients = try await fixture.identityClient.inspect(
      fixture.identityURL
    )

    XCTAssertEqual(recipients.count, 1)
    XCTAssertTrue(recipients[0].value.hasPrefix("age1pq1"))
  }

  func testInspectDerivesAllRecipientsFromMultiIdentityFile() async throws {
    let first = try await SOPSIntegrationFixture()
    let second = try await SOPSIntegrationFixture()
    let combinedURL = first.temporaryURL(named: "combined-identities.txt")
    var combined = try Data(contentsOf: first.identityURL)
    combined.append(Data("\n".utf8))
    combined.append(try Data(contentsOf: second.identityURL))
    try combined.write(to: combinedURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: combinedURL.path
    )

    let recipients = try await first.identityClient.inspect(combinedURL)

    XCTAssertEqual(recipients.count, 2)
    XCTAssertEqual(Set(recipients).count, 2)
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
