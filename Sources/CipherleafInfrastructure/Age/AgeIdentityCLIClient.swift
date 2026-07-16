import CipherleafApplication
import CipherleafDomain
import Foundation

public enum AgeIdentityCLIClient {
  public static func live(
    configurationStore: ToolConfigurationStore
  ) -> AgeIdentityClient {
    let service = AgeIdentityCLIService(
      configurationStore: configurationStore
    )
    return AgeIdentityClient { identityURL in
      try await service.inspect(identityURL)
    }
  }
}

private struct AgeIdentityCLIService: Sendable {
  private let executor = ProcessExecutor()
  private let fileSafety = FileSafetyValidator()
  private let locator: ToolLocator

  init(configurationStore: ToolConfigurationStore) {
    locator = ToolLocator(configurationStore: configurationStore)
  }

  func inspect(_ identityURL: URL) async throws -> [AgeRecipient] {
    try fileSafety.validateIdentityCandidate(identityURL)
    let ageKeygen = try locator.resolve(.ageKeygen)
    let result: ProcessOutput
    do {
      result = try await executor.run(
        ProcessRequest(
          executable: ageKeygen,
          arguments: ["-y", identityURL.path],
          currentDirectory: identityURL.deletingLastPathComponent(),
          environment: SecureEnvironment.sops(),
          outputLimit: 1_024 * 1_024
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw AgeIdentityCLIError.invalidNativeIdentity
    }

    let values = String(decoding: result.standardOutput, as: UTF8.self)
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
      .filter { $0.hasPrefix("age1") }
    let recipients = try Set(values).map(AgeRecipient.init).sorted {
      $0.value < $1.value
    }
    guard !recipients.isEmpty else {
      throw AgeIdentityCLIError.invalidNativeIdentity
    }
    try fileSafety.validateIdentityPermissions(identityURL)
    return recipients
  }
}

private enum AgeIdentityCLIError: LocalizedError {
  case invalidNativeIdentity

  var errorDescription: String? {
    switch self {
    case .invalidNativeIdentity:
      "The selected file does not contain a native age identity created by age-keygen."
    }
  }
}
