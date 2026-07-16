import CipherleafApplication
import CipherleafDomain
import Foundation

public enum SOPSCLIClient {
  public static func live(
    configurationStore: ToolConfigurationStore
  ) -> EncryptedFileClient {
    let service = SOPSCLIService(configurationStore: configurationStore)
    return EncryptedFileClient(
      open: { manifestURL, identityURL in
        try await service.open(
          manifestURL: manifestURL,
          identityURL: identityURL
        )
      },
      save: { request in
        try await service.save(request)
      },
      diagnoseTools: {
        await service.diagnoseTools()
      }
    )
  }
}

private struct SOPSCLIService: Sendable {
  private let executor = ProcessExecutor()
  private let fileSafety = FileSafetyValidator()
  private let locator: ToolLocator
  private let metadataParser = SOPSMetadataParser()
  private let revisionCalculator = FileRevisionCalculator()

  init(configurationStore: ToolConfigurationStore) {
    locator = ToolLocator(configurationStore: configurationStore)
  }

  func open(
    manifestURL: URL,
    identityURL: URL
  ) async throws -> OpenedSOPSFile {
    try fileSafety.validateManifest(manifestURL)
    try fileSafety.validateIdentity(identityURL)
    let format = try SOPSFileFormat(url: manifestURL)
    let encryptedData = try Data(contentsOf: manifestURL)
    let recipients = try metadataParser.parse(encryptedData)
    let identityRecipients = try await deriveRecipients(identityURL: identityURL)

    guard !Set(recipients).isDisjoint(with: identityRecipients) else {
      throw SOPSCLIError.identityDoesNotMatch
    }

    let root = try await decrypt(
      manifestURL: manifestURL,
      identityURL: identityURL,
      format: format
    )

    return OpenedSOPSFile(
      root: root,
      format: format,
      recipients: recipients,
      identityRecipients: identityRecipients,
      policyURL: nearestPolicy(to: manifestURL),
      revision: try revisionCalculator.revision(
        for: encryptedData,
        at: manifestURL
      ),
      sourceContainsComments: containsComments(
        in: encryptedData,
        format: format
      )
    )
  }

  func save(_ request: SaveSOPSFileRequest) async throws -> SavedSOPSFile {
    guard !request.candidate.patch.operations.isEmpty else {
      throw SOPSCLIError.emptyPatch
    }

    try fileSafety.validateManifest(request.manifestURL)
    try fileSafety.validateIdentity(request.identityURL)
    let currentData = try Data(contentsOf: request.manifestURL)
    let currentRevision = try revisionCalculator.revision(
      for: currentData,
      at: request.manifestURL
    )
    guard currentRevision.digest == request.expectedRevision.digest else {
      throw SOPSCLIError.externalModification
    }

    let currentRecipients = try metadataParser.parse(currentData)
    guard currentRecipients == request.originalRecipients else {
      throw SOPSCLIError.recipientsChanged
    }

    let transaction = try AtomicFileTransaction.stage(
      currentData,
      for: request.manifestURL
    )

    for operation in request.candidate.patch.operations {
      try await apply(
        operation,
        to: transaction.stagedURL,
        identityURL: request.identityURL,
        format: request.format
      )
    }

    let verifiedRoot = try await decrypt(
      manifestURL: transaction.stagedURL,
      identityURL: request.identityURL,
      format: request.format
    )
    guard verifiedRoot == request.candidate.root else {
      throw SOPSCLIError.verificationMismatch
    }

    let stagedData = try Data(contentsOf: transaction.stagedURL)
    let stagedRecipients = try metadataParser.parse(stagedData)
    guard stagedRecipients == request.originalRecipients else {
      throw SOPSCLIError.recipientsChanged
    }

    let latestData = try Data(contentsOf: request.manifestURL)
    let latestRevision = try revisionCalculator.revision(
      for: latestData,
      at: request.manifestURL
    )
    guard latestRevision.digest == request.expectedRevision.digest else {
      throw SOPSCLIError.externalModification
    }

    try transaction.commit()
    let installedData = try Data(contentsOf: request.manifestURL)
    return SavedSOPSFile(
      revision: try revisionCalculator.revision(
        for: installedData,
        at: request.manifestURL
      ),
      sourceContainsComments: containsComments(
        in: installedData,
        format: request.format
      )
    )
  }

  func diagnoseTools() async -> [ToolDiagnostic] {
    await [
      diagnose(.sops),
      diagnose(.ageKeygen),
    ]
  }

  private func diagnose(_ tool: ExternalTool) async -> ToolDiagnostic {
    do {
      let url = try locator.resolve(tool)
      let output = try? await executor.run(
        ProcessRequest(
          executable: url,
          arguments: ["--version"],
          environment: SecureEnvironment.sops(),
          failureOutputPolicy: .diagnostic,
          outputLimit: 64 * 1_024
        )
      )
      let version = output.flatMap {
        let value =
          String(decoding: $0.standardOutput, as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
      }
      return ToolDiagnostic(
        name: tool.rawValue,
        state: .available(path: url.path, version: version)
      )
    } catch {
      return ToolDiagnostic(
        name: tool.rawValue,
        state: .unavailable(message: error.localizedDescription)
      )
    }
  }

  private func deriveRecipients(identityURL: URL) async throws -> [AgeRecipient] {
    let ageKeygen = try locator.resolve(.ageKeygen)
    let result = try await executor.run(
      ProcessRequest(
        executable: ageKeygen,
        arguments: ["-y", identityURL.path],
        currentDirectory: identityURL.deletingLastPathComponent(),
        environment: SecureEnvironment.sops(),
        outputLimit: 1_024 * 1_024
      )
    )

    let values = String(decoding: result.standardOutput, as: UTF8.self)
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
      .filter { $0.hasPrefix("age1") }
    let recipients = try Set(values).map(AgeRecipient.init).sorted {
      $0.value < $1.value
    }
    guard !recipients.isEmpty else {
      throw SOPSCLIError.identityHasNoNativeRecipients
    }
    return recipients
  }

  private func decrypt(
    manifestURL: URL,
    identityURL: URL,
    format: SOPSFileFormat
  ) async throws -> SecretValue {
    let sops = try locator.resolve(.sops)
    let result = try await executor.run(
      ProcessRequest(
        executable: sops,
        arguments: [
          "decrypt",
          "--input-type", format.rawValue,
          "--output-type", "json",
          manifestURL.path,
        ],
        currentDirectory: manifestURL.deletingLastPathComponent(),
        environment: SecureEnvironment.sops(identityURL: identityURL)
      )
    )
    return try SecretValue.decodeDocument(result.standardOutput)
  }

  private func apply(
    _ operation: PatchOperation,
    to stagedURL: URL,
    identityURL: URL,
    format: SOPSFileFormat
  ) async throws {
    let sops = try locator.resolve(.sops)

    switch operation {
    case .set(let path, let value):
      let input = try value.encoded()
      _ = try await executor.run(
        ProcessRequest(
          executable: sops,
          arguments: [
            "set",
            "--input-type", format.rawValue,
            "--output-type", format.rawValue,
            "--value-stdin",
            stagedURL.path,
            path.sopsIndex,
          ],
          input: input,
          currentDirectory: stagedURL.deletingLastPathComponent(),
          environment: SecureEnvironment.sops(identityURL: identityURL)
        )
      )

    case .unset(let path):
      _ = try await executor.run(
        ProcessRequest(
          executable: sops,
          arguments: [
            "unset",
            "--input-type", format.rawValue,
            "--output-type", format.rawValue,
            "--idempotent",
            stagedURL.path,
            path.sopsIndex,
          ],
          currentDirectory: stagedURL.deletingLastPathComponent(),
          environment: SecureEnvironment.sops(identityURL: identityURL)
        )
      )
    }
  }

  private func nearestPolicy(to manifestURL: URL) -> URL? {
    var directory = manifestURL.deletingLastPathComponent().standardizedFileURL
    let root = URL(fileURLWithPath: "/", isDirectory: true)

    while true {
      let candidate = directory.appendingPathComponent(".sops.yaml")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }

      if directory == root {
        return nil
      }
      let parent = directory.deletingLastPathComponent()
      if parent == directory {
        return nil
      }
      directory = parent
    }
  }

  private func containsComments(
    in data: Data,
    format: SOPSFileFormat
  ) -> Bool {
    guard format != .json else {
      return false
    }
    return String(decoding: data, as: UTF8.self).contains("#")
  }
}

enum SOPSCLIError: LocalizedError {
  case emptyPatch
  case externalModification
  case identityDoesNotMatch
  case identityHasNoNativeRecipients
  case recipientsChanged
  case verificationMismatch

  var errorDescription: String? {
    switch self {
    case .emptyPatch:
      "There are no document changes to save."
    case .externalModification:
      "The encrypted file changed on disk after it was opened. Reload it before saving."
    case .identityDoesNotMatch:
      "The selected age identity is not one of this document's recipients."
    case .identityHasNoNativeRecipients:
      "The selected file does not contain a native age identity."
    case .recipientsChanged:
      "The SOPS recipient metadata changed unexpectedly. The original file was not replaced."
    case .verificationMismatch:
      "The patched staging file did not decrypt to the intended document. The original file was not replaced."
    }
  }
}
