import CipherleafApplication
import CipherleafDomain
import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class SOPSPostQuantumIntegrationTests: XCTestCase {
  func testPostQuantumDocumentRoundTrip() async throws {
    let fixture = try await SOPSIntegrationFixture(postQuantum: true)
    let manifestURL = try await fixture.encrypt(
      Data("token: synthetic\n".utf8)
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let tokenPath = SecretPath(components: [.key("token")])
    let updatedRoot = try opened.root.setting(
      .string("updated-synthetic"),
      at: tokenPath
    )
    let request = fixture.saveRequest(
      manifestURL: manifestURL,
      opened: opened,
      root: updatedRoot
    )

    _ = try await fixture.client.save(request)

    let reloaded = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    XCTAssertTrue(
      reloaded.recipients.allSatisfy { $0.value.hasPrefix("age1pq1") }
    )
    XCTAssertEqual(
      reloaded.root.value(at: tokenPath),
      .string("updated-synthetic")
    )
  }
}
