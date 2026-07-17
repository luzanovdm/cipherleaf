import CipherleafApplication
import CipherleafDomain
import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class SOPSIntegrationTests: XCTestCase {
  func testSyntheticDocumentRoundTripUsesPatchAndPreservesRecipients() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data(
        """
        generation: 1
        service:
          token: synthetic-token
          enabled: true
        """.utf8
      )
    )
    let originalCiphertext = try Data(contentsOf: manifestURL)
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let tokenPath = try SecretPath.parseEditablePath("service.token")
    let updatedRoot = try opened.root.setting(
      .string("updated-synthetic-token"),
      at: tokenPath
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
      reloaded.root.value(at: tokenPath),
      .string("updated-synthetic-token")
    )
    XCTAssertEqual(reloaded.recipients, opened.recipients)
    XCTAssertNotEqual(try Data(contentsOf: manifestURL), originalCiphertext)
  }

  func testExternalModificationPreventsSave() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("token: synthetic\n".utf8)
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let externalData = try Data(contentsOf: manifestURL) + Data("\n".utf8)
    try externalData.write(to: manifestURL)
    let tokenPath = SecretPath(components: [.key("token")])
    let updatedRoot = try opened.root.setting(
      .string("updated-synthetic"),
      at: tokenPath
    )

    do {
      _ = try await fixture.client.save(
        fixture.saveRequest(
          manifestURL: manifestURL,
          opened: opened,
          root: updatedRoot
        )
      )
      XCTFail("Expected an external modification error.")
    } catch {
      XCTAssertTrue(
        error.localizedDescription.contains("changed on disk")
      )
    }
  }

  func testConcurrentExternalModificationPreventsCommit() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("token: synthetic\n".utf8)
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let markerURL = fixture.temporaryURL(
      named: "set-operation-started"
    )
    let delayedClient = try fixture.makeClientDelayingSet(
      markerURL: markerURL
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

    let saveTask = Task {
      try await delayedClient.save(request)
    }
    try await waitForFile(at: markerURL)
    let externalData = try Data(contentsOf: manifestURL) + Data("\n".utf8)
    try externalData.write(to: manifestURL)

    do {
      _ = try await saveTask.value
      XCTFail("Expected a concurrent external modification error.")
    } catch {
      XCTAssertTrue(
        error.localizedDescription.contains("changed on disk")
      )
    }
    XCTAssertEqual(try Data(contentsOf: manifestURL), externalData)
  }

  func testJSONRoundTrip() async throws {
    try await assertRoundTrip(
      plaintext: Data(
        #"{"token":"synthetic","enabled":true}"#.utf8
      ),
      format: .json,
      path: SecretPath(components: [.key("token")])
    )
  }

  func testDotenvRoundTrip() async throws {
    try await assertRoundTrip(
      plaintext: Data(
        """
        TOKEN=synthetic
        ENABLED=true
        """.utf8
      ),
      format: .dotenv,
      path: SecretPath(components: [.key("TOKEN")])
    )
  }

  func testAddAndRemoveOperationsRoundTrip() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data(
        """
        service:
          token: synthetic
          obsolete: synthetic-old
        """.utf8
      )
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let tokenPath = try SecretPath.parseEditablePath("service.token")
    let credentialPath = try SecretPath.parseEditablePath(
      "service.credential"
    )
    let obsoletePath = try SecretPath.parseEditablePath("service.obsolete")
    let updatedRoot = try opened.root
      .adding(.string("synthetic-new"), at: credentialPath)
      .removing(at: tokenPath)
      .removing(at: obsoletePath)

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
      reloaded.root.value(at: credentialPath),
      .string("synthetic-new")
    )
    XCTAssertNil(reloaded.root.value(at: tokenPath))
    XCTAssertNil(reloaded.root.value(at: obsoletePath))
  }

  func testYamlCommentsAreDetectedBeforeSOPSRewritesThem() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let sourceURL = try XCTUnwrap(
      Bundle(for: Self.self).url(
        forResource: "commented.plain",
        withExtension: "yaml"
      )
    )
    let manifestURL = try await fixture.encrypt(
      Data(contentsOf: sourceURL)
    )
    var ciphertext = String(
      decoding: try Data(contentsOf: manifestURL),
      as: UTF8.self
    )
    ciphertext = "# Top-level operator note.\n\(ciphertext)"
    ciphertext = ciphertext.replacingOccurrences(
      of: "service:\n",
      with: "service:\n    # Keep this comment beside the credential.\n"
    )
    try Data(ciphertext.utf8).write(to: manifestURL)

    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let tokenPath = try SecretPath.parseEditablePath("service.token")
    let updatedRoot = try opened.root.setting(
      .string("updated-synthetic-token"),
      at: tokenPath
    )

    let saved = try await fixture.client.save(
      fixture.saveRequest(
        manifestURL: manifestURL,
        opened: opened,
        root: updatedRoot
      )
    )

    XCTAssertTrue(opened.sourceContainsComments)
    ciphertext = String(
      decoding: try Data(contentsOf: manifestURL),
      as: UTF8.self
    )
    let installedContainsComments =
      ciphertext
      .split(whereSeparator: \.isNewline)
      .contains { line in
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
      }
    XCTAssertEqual(
      saved.sourceContainsComments,
      installedContainsComments
    )
    XCTAssertFalse(ciphertext.contains("# Top-level operator note."))
    XCTAssertFalse(
      ciphertext.contains("# Keep this comment beside the credential.")
    )
  }

  func testYamlInlineCommentIsDetected() async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      Data("token: synthetic\n".utf8)
    )
    var lines = String(
      decoding: try Data(contentsOf: manifestURL),
      as: UTF8.self
    ).split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).map(String.init)
    let tokenLine = try XCTUnwrap(
      lines.firstIndex { $0.contains("token: ENC[") }
    )
    lines[tokenLine] += " # Synthetic inline operator note."
    try Data(lines.joined(separator: "\n").utf8).write(to: manifestURL)

    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )

    XCTAssertTrue(opened.sourceContainsComments)
  }

  private func assertRoundTrip(
    plaintext: Data,
    format: SOPSFileFormat,
    path: SecretPath
  ) async throws {
    let fixture = try await SOPSIntegrationFixture()
    let manifestURL = try await fixture.encrypt(
      plaintext,
      format: format
    )
    let opened = try await fixture.client.open(
      manifestURL,
      fixture.identityURL
    )
    let updatedRoot = try opened.root.setting(
      .string("updated-synthetic"),
      at: path
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
    XCTAssertEqual(reloaded.format, format)
    XCTAssertEqual(
      reloaded.root.value(at: path),
      .string("updated-synthetic")
    )
    XCTAssertEqual(reloaded.recipients, opened.recipients)
  }

  private func waitForFile(at url: URL) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))

    while !FileManager.default.fileExists(atPath: url.path) {
      guard clock.now < deadline else {
        XCTFail("Timed out waiting for the delayed SOPS operation.")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}
