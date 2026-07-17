import CipherleafApplication
import CipherleafDomain
import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class SOPSDotenvIntegrationTests: XCTestCase {
  func testDotenvRoundTripsNumberValue() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("TOKEN=synthetic\n".utf8),
      format: .dotenv
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let tokenPath = SecretPath(components: [.key("TOKEN")])
    let updatedRoot = try opened.root.setting(.number("42"), at: tokenPath)

    _ = try await fixture.client.save(
      fixture.saveRequest(
        manifestURL: manifestURL,
        opened: opened,
        root: updatedRoot
      )
    )

    let reloaded = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    XCTAssertEqual(reloaded.root.value(at: tokenPath), .number("42"))
  }

  func testDotenvCannotRepresentNestedValues() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("TOKEN=synthetic\n".utf8),
      format: .dotenv
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let nestedPath = try SecretPath.parseEditablePath("SERVICE.TOKEN")
    let updatedRoot = try opened.root.adding(
      .string("nested-synthetic"),
      at: nestedPath
    )

    do {
      _ = try await fixture.client.save(
        fixture.saveRequest(
          manifestURL: manifestURL,
          opened: opened,
          root: updatedRoot
        )
      )
      XCTFail("Expected dotenv to reject a nested value.")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("one-level keys"))
      let reloaded = try await fixture.client.open(
        manifestURL,
        fixture.identityURL
      )
      XCTAssertNil(reloaded.root.value(at: nestedPath))
    }
  }

  func testDotenvAddsKeyContainingDotAsFlatKey() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("TOKEN=synthetic\n".utf8),
      format: .dotenv
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let dottedPath = SecretPath(components: [.key("SERVICE.TOKEN")])
    let updatedRoot = try opened.root.adding(
      .string("dotted-synthetic"),
      at: dottedPath
    )

    _ = try await fixture.client.save(
      fixture.saveRequest(
        manifestURL: manifestURL,
        opened: opened,
        root: updatedRoot
      )
    )

    let reloaded = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    XCTAssertEqual(
      reloaded.root.value(at: dottedPath),
      .string("dotted-synthetic")
    )
  }

}
