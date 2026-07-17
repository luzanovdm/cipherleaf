import CipherleafApplication
import CipherleafDomain
import Foundation

public enum SOPSCLIClient {
  public static func live(
    configurationStore: ToolConfigurationStore,
    identityClient: AgeIdentityClient? = nil
  ) -> EncryptedFileClient {
    let service = SOPSCLIService(
      configurationStore: configurationStore,
      identityClient: identityClient
        ?? AgeIdentityCLIClient.live(
          configurationStore: configurationStore
        )
    )
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
  private let identityClient: AgeIdentityClient
  private let locator: ToolLocator
  private let metadataParser = SOPSMetadataParser()
  private let revisionCalculator = FileRevisionCalculator()

  init(
    configurationStore: ToolConfigurationStore,
    identityClient: AgeIdentityClient
  ) {
    self.identityClient = identityClient
    locator = ToolLocator(configurationStore: configurationStore)
  }

  func open(
    manifestURL: URL,
    identityURL: URL
  ) async throws -> OpenedSOPSFile {
    let format = try SOPSFileFormat(url: manifestURL)
    let encryptedSnapshot = try fileSafety.readManifest(manifestURL)
    let recipients = try metadataParser.parse(
      encryptedSnapshot.data,
      format: format
    )
    let identityRecipients = try await identityClient.inspect(identityURL)

    guard !Set(recipients).isDisjoint(with: identityRecipients) else {
      throw SOPSCLIError.identityDoesNotMatch
    }

    let root = try await decrypt(
      encryptedData: encryptedSnapshot.data,
      filenameURL: manifestURL,
      identityURL: identityURL,
      format: format
    )

    return OpenedSOPSFile(
      root: root,
      format: format,
      recipients: recipients,
      identityRecipients: identityRecipients,
      policyURL: nearestPolicy(to: manifestURL),
      revision: revisionCalculator.revision(
        for: encryptedSnapshot.data,
        modifiedAt: encryptedSnapshot.modifiedAt
      ),
      sourceContainsComments: containsComments(
        in: encryptedSnapshot.data,
        format: format
      )
    )
  }

  func save(_ request: SaveSOPSFileRequest) async throws -> SavedSOPSFile {
    guard !request.candidate.patch.operations.isEmpty else {
      throw SOPSCLIError.emptyPatch
    }

    try fileSafety.validateIdentity(request.identityURL)
    let currentSnapshot = try fileSafety.readManifest(request.manifestURL)
    let currentRevision = revisionCalculator.revision(
      for: currentSnapshot.data,
      modifiedAt: currentSnapshot.modifiedAt
    )
    guard currentRevision.digest == request.expectedRevision.digest else {
      throw SOPSCLIError.externalModification
    }

    let currentRecipients = try metadataParser.parse(
      currentSnapshot.data,
      format: request.format
    )
    guard currentRecipients == request.originalRecipients else {
      throw SOPSCLIError.recipientsChanged
    }

    let transaction = try AtomicFileTransaction.stage(
      currentSnapshot.data,
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

    let stagedSnapshot = try fileSafety.readManifest(transaction.stagedURL)
    let stagedRecipients = try metadataParser.parse(
      stagedSnapshot.data,
      format: request.format
    )
    guard stagedRecipients == request.originalRecipients else {
      throw SOPSCLIError.recipientsChanged
    }

    let verifiedRoot = try await decrypt(
      encryptedData: stagedSnapshot.data,
      filenameURL: transaction.stagedURL,
      identityURL: request.identityURL,
      format: request.format
    )
    guard verifiedRoot == request.candidate.root else {
      throw SOPSCLIError.verificationMismatch
    }

    let latestSnapshot = try fileSafety.readManifest(request.manifestURL)
    let latestRevision = revisionCalculator.revision(
      for: latestSnapshot.data,
      modifiedAt: latestSnapshot.modifiedAt
    )
    guard latestRevision.digest == request.expectedRevision.digest else {
      throw SOPSCLIError.externalModification
    }

    let installedModificationDate = try transaction.commit(
      expectedData: stagedSnapshot.data
    )
    return SavedSOPSFile(
      revision: revisionCalculator.revision(
        for: stagedSnapshot.data,
        modifiedAt: installedModificationDate
      ),
      sourceContainsComments: containsComments(
        in: stagedSnapshot.data,
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
      let arguments =
        tool == .sops
        ? ["--disable-version-check", "--version"]
        : ["--version"]
      let output = try await executor.run(
        ProcessRequest(
          executable: url,
          arguments: arguments,
          environment: SecureEnvironment.sops(),
          failureOutputPolicy: .diagnostic,
          outputLimit: 64 * 1_024
        )
      )
      let value =
        String(decoding: output.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let version = value.isEmpty ? nil : value
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

  private func decrypt(
    encryptedData: Data,
    filenameURL: URL,
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
          "--filename-override", filenameURL.path,
        ],
        input: encryptedData,
        currentDirectory: filenameURL.deletingLastPathComponent(),
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
    case .recipientsChanged:
      "The SOPS recipient metadata changed unexpectedly. The original file was not replaced."
    case .verificationMismatch:
      "The patched staging file did not decrypt to the intended document. The original file was not replaced."
    }
  }
}
