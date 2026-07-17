import CipherleafDomain
import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class SOPSStructuredValueIntegrationTests: XCTestCase {
  func testReplacingScalarWithArrayRoundTrips() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("items: synthetic\n".utf8)
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let itemsPath = SecretPath(components: [.key("items")])
    let updatedRoot = try opened.root.setting(
      .array([
        .string("synthetic-one"),
        .array([.string("synthetic-nested")]),
      ]),
      at: itemsPath
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
    XCTAssertEqual(reloaded.root.value(at: itemsPath), updatedRoot.value(at: itemsPath))
  }

  func testRemovingArrayElementRoundTripsWholeArray() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data(
        """
        items:
          - synthetic-one
          - synthetic-two
          - synthetic-three
        """.utf8
      )
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let removedPath = SecretPath(
      components: [.key("items"), .index(1)]
    )
    let itemsPath = SecretPath(components: [.key("items")])
    let updatedRoot = try opened.root.removing(at: removedPath)

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
      reloaded.root.value(at: itemsPath),
      .array([
        .string("synthetic-one"),
        .string("synthetic-three"),
      ])
    )
  }

  func testRemovingOnlyArrayElementLeavesEmptyArray() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data(
        """
        items:
          - synthetic-one
        """.utf8
      )
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let itemsPath = SecretPath(components: [.key("items")])
    let updatedRoot = try opened.root.removing(
      at: itemsPath.appending(.index(0))
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
    XCTAssertEqual(reloaded.root.value(at: itemsPath), .array([]))
  }

  func testJSONKeysWithPathSyntaxCharactersRoundTrip() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data(
        #"{"service.token":"synthetic","quote\"key":"synthetic-two","single'key":"synthetic-three","back\\slash":"synthetic-four","right]bracket":"synthetic-five"}"#
          .utf8
      ),
      format: .json
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let dottedPath = SecretPath(components: [.key("service.token")])
    let quotedPath = SecretPath(components: [.key("quote\"key")])
    let singleQuotedPath = SecretPath(components: [.key("single'key")])
    let backslashPath = SecretPath(components: [.key("back\\slash")])
    let bracketPath = SecretPath(components: [.key("right]bracket")])
    let updatedRoot = try opened.root
      .setting(.string("updated-synthetic"), at: dottedPath)
      .setting(.string("updated-synthetic-two"), at: quotedPath)
      .setting(.string("updated-synthetic-three"), at: singleQuotedPath)
      .setting(.string("updated-synthetic-four"), at: backslashPath)
      .setting(.string("updated-synthetic-five"), at: bracketPath)

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
      .string("updated-synthetic")
    )
    XCTAssertEqual(
      reloaded.root.value(at: quotedPath),
      .string("updated-synthetic-two")
    )
    XCTAssertEqual(
      reloaded.root.value(at: singleQuotedPath),
      .string("updated-synthetic-three")
    )
    XCTAssertEqual(
      reloaded.root.value(at: backslashPath),
      .string("updated-synthetic-four")
    )
    XCTAssertEqual(
      reloaded.root.value(at: bracketPath),
      .string("updated-synthetic-five")
    )
  }

  func testRemovingSeveralTrailingArrayElementsRoundTrips() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data(
        """
        items:
          - synthetic-one
          - synthetic-two
          - synthetic-three
          - synthetic-four
        """.utf8
      )
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let itemsPath = SecretPath(components: [.key("items")])
    let updatedRoot = try opened.root
      .removing(
        at: SecretPath(components: [.key("items"), .index(3)])
      )
      .removing(
        at: SecretPath(components: [.key("items"), .index(2)])
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
      reloaded.root.value(at: itemsPath),
      .array([.string("synthetic-one"), .string("synthetic-two")])
    )
  }

  func testRemovingLastUserValueLeavesValidEncryptedDocument() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("token: synthetic\n".utf8)
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let tokenPath = SecretPath(components: [.key("token")])
    let updatedRoot = try opened.root.removing(at: tokenPath)

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
    XCTAssertEqual(reloaded.root, .object([:]))
    XCTAssertEqual(reloaded.recipients, opened.recipients)
  }
}
