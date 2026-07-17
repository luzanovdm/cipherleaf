import CipherleafDomain
import Foundation

struct SOPSPatchApplier: Sendable {
  private let executor = ProcessExecutor()

  func apply(
    _ operation: PatchOperation,
    to stagedURL: URL,
    identityURL: URL,
    format: SOPSFileFormat,
    sops: URL
  ) async throws {
    switch operation {
    case .set(let path, let value):
      try await applySet(
        value,
        at: path,
        to: stagedURL,
        identityURL: identityURL,
        format: format,
        sops: sops
      )
    case .unset(let path):
      try await applyUnset(
        at: path,
        to: stagedURL,
        identityURL: identityURL,
        format: format,
        sops: sops
      )
    }
  }

  private func applySet(
    _ value: SecretValue,
    at path: SecretPath,
    to stagedURL: URL,
    identityURL: URL,
    format: SOPSFileFormat,
    sops: URL
  ) async throws {
    if case .array(let values) = value {
      try await applyArray(
        values,
        at: path,
        to: stagedURL,
        identityURL: identityURL,
        format: format,
        sops: sops
      )
      return
    }

    guard let sopsIndex = path.sopsIndex else {
      throw SOPSFileFormatEditingError.unaddressablePath
    }
    _ = try await executor.run(
      ProcessRequest(
        executable: sops,
        arguments: [
          "set",
          "--input-type", format.rawValue,
          "--output-type", format.rawValue,
          "--value-stdin",
          stagedURL.path,
          sopsIndex,
        ],
        input: try value.encoded(),
        currentDirectory: stagedURL.deletingLastPathComponent(),
        environment: SecureEnvironment.sops(identityURL: identityURL)
      )
    )
  }

  private func applyArray(
    _ values: [SecretValue],
    at path: SecretPath,
    to stagedURL: URL,
    identityURL: URL,
    format: SOPSFileFormat,
    sops: URL
  ) async throws {
    if values.isEmpty {
      let placeholderPath = path.appending(.index(0))
      try await applySet(
        .null,
        at: placeholderPath,
        to: stagedURL,
        identityURL: identityURL,
        format: format,
        sops: sops
      )
      try await applyUnset(
        at: placeholderPath,
        to: stagedURL,
        identityURL: identityURL,
        format: format,
        sops: sops
      )
      return
    }

    for (index, child) in values.enumerated() {
      try await applySet(
        child,
        at: path.appending(.index(index)),
        to: stagedURL,
        identityURL: identityURL,
        format: format,
        sops: sops
      )
    }
  }

  private func applyUnset(
    at path: SecretPath,
    to stagedURL: URL,
    identityURL: URL,
    format: SOPSFileFormat,
    sops: URL
  ) async throws {
    guard let sopsIndex = path.sopsIndex else {
      throw SOPSFileFormatEditingError.unaddressablePath
    }
    _ = try await executor.run(
      ProcessRequest(
        executable: sops,
        arguments: [
          "unset",
          "--input-type", format.rawValue,
          "--output-type", format.rawValue,
          "--idempotent",
          stagedURL.path,
          sopsIndex,
        ],
        currentDirectory: stagedURL.deletingLastPathComponent(),
        environment: SecureEnvironment.sops(identityURL: identityURL)
      )
    )
  }
}
