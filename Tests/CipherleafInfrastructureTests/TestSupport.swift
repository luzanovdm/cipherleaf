import CipherleafApplication
import CipherleafDomain
import Foundation
import XCTest

@testable import CipherleafInfrastructure

final class TemporaryDirectory {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

final class SOPSIntegrationFixture {
  let client: EncryptedFileClient
  let identityURL: URL

  private let ageKeygen: URL
  private let directory: TemporaryDirectory
  private let executor = ProcessExecutor()
  private let recipient: String
  private let sops: URL

  init() async throws {
    directory = try TemporaryDirectory()
    let configurationStore = ToolConfigurationStore()
    let locator = ToolLocator(configurationStore: configurationStore)

    do {
      sops = try locator.resolve(.sops)
      ageKeygen = try locator.resolve(.ageKeygen)
    } catch {
      throw XCTSkip("SOPS and age-keygen are required for this integration test.")
    }

    configurationStore.configuration = ToolConfiguration(
      sopsPath: sops.path,
      ageKeygenPath: ageKeygen.path
    )
    client = SOPSCLIClient.live(configurationStore: configurationStore)
    identityURL = directory.url.appendingPathComponent("identity.txt")

    _ = try await ProcessExecutor().run(
      ProcessRequest(
        executable: ageKeygen,
        arguments: ["-o", identityURL.path],
        environment: SecureEnvironment.sops()
      )
    )
    let recipientResult = try await ProcessExecutor().run(
      ProcessRequest(
        executable: ageKeygen,
        arguments: ["-y", identityURL.path],
        environment: SecureEnvironment.sops()
      )
    )
    recipient = String(
      decoding: recipientResult.standardOutput,
      as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func encrypt(
    _ plaintext: Data,
    format: SOPSFileFormat = .yaml
  ) async throws -> URL {
    let plaintextURL = directory.url.appendingPathComponent(
      "synthetic-plain.\(format.rawValue)"
    )
    let manifestURL = directory.url.appendingPathComponent(
      "synthetic.sops.\(format.rawValue)"
    )
    try plaintext.write(to: plaintextURL)

    _ = try await executor.run(
      ProcessRequest(
        executable: sops,
        arguments: [
          "encrypt",
          "--age", recipient,
          "--input-type", format.rawValue,
          "--output-type", format.rawValue,
          "--output", manifestURL.path,
          plaintextURL.path,
        ],
        environment: SecureEnvironment.sops()
      )
    )
    return manifestURL
  }

  func makeClientDelayingSet(
    markerURL: URL
  ) throws -> EncryptedFileClient {
    let wrapperURL = directory.url.appendingPathComponent(
      "delayed-sops"
    )
    let script = """
      #!/bin/bash
      set -euo pipefail
      if [[ "${1:-}" == "set" ]]; then
        /usr/bin/touch "\(markerURL.path)"
        /bin/sleep 0.5
      fi
      exec "\(sops.path)" "$@"
      """
    try Data(script.utf8).write(to: wrapperURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: wrapperURL.path
    )

    return SOPSCLIClient.live(
      configurationStore: ToolConfigurationStore(
        ToolConfiguration(
          sopsPath: wrapperURL.path,
          ageKeygenPath: ageKeygen.path
        )
      )
    )
  }

  func temporaryURL(named name: String) -> URL {
    directory.url.appendingPathComponent(name)
  }
}
