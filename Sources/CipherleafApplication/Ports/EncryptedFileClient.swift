import CipherleafDomain
import Foundation

public struct FileRevision: Equatable, Sendable {
  public let digest: String
  public let byteCount: Int
  public let modifiedAt: Date?

  public init(digest: String, byteCount: Int, modifiedAt: Date?) {
    self.digest = digest
    self.byteCount = byteCount
    self.modifiedAt = modifiedAt
  }
}

public struct OpenedSOPSFile: Sendable {
  public let root: SecretValue
  public let format: SOPSFileFormat
  public let recipients: [AgeRecipient]
  public let identityRecipients: [AgeRecipient]
  public let policyURL: URL?
  public let revision: FileRevision
  public let sourceContainsComments: Bool

  public init(
    root: SecretValue,
    format: SOPSFileFormat,
    recipients: [AgeRecipient],
    identityRecipients: [AgeRecipient],
    policyURL: URL?,
    revision: FileRevision,
    sourceContainsComments: Bool = false
  ) {
    self.root = root
    self.format = format
    self.recipients = recipients
    self.identityRecipients = identityRecipients
    self.policyURL = policyURL
    self.revision = revision
    self.sourceContainsComments = sourceContainsComments
  }
}

public struct SavedSOPSFile: Sendable {
  public let revision: FileRevision
  public let sourceContainsComments: Bool

  public init(
    revision: FileRevision,
    sourceContainsComments: Bool
  ) {
    self.revision = revision
    self.sourceContainsComments = sourceContainsComments
  }
}

public struct SaveSOPSFileRequest: Sendable {
  public let manifestURL: URL
  public let identityURL: URL
  public let format: SOPSFileFormat
  public let expectedRevision: FileRevision
  public let originalRecipients: [AgeRecipient]
  public let candidate: SaveCandidate

  public init(
    manifestURL: URL,
    identityURL: URL,
    format: SOPSFileFormat,
    expectedRevision: FileRevision,
    originalRecipients: [AgeRecipient],
    candidate: SaveCandidate
  ) {
    self.manifestURL = manifestURL
    self.identityURL = identityURL
    self.format = format
    self.expectedRevision = expectedRevision
    self.originalRecipients = originalRecipients
    self.candidate = candidate
  }
}

public struct ToolDiagnostic: Equatable, Sendable {
  public enum State: Equatable, Sendable {
    case available(path: String, version: String?)
    case unavailable(message: String)
  }

  public let name: String
  public let state: State

  public init(name: String, state: State) {
    self.name = name
    self.state = state
  }
}

public struct EncryptedFileClient: Sendable {
  public var open: @Sendable (_ manifestURL: URL, _ identityURL: URL) async throws -> OpenedSOPSFile
  public var save: @Sendable (_ request: SaveSOPSFileRequest) async throws -> SavedSOPSFile
  public var diagnoseTools: @Sendable () async -> [ToolDiagnostic]

  public init(
    open:
      @escaping @Sendable (
        _ manifestURL: URL,
        _ identityURL: URL
      ) async throws -> OpenedSOPSFile,
    save:
      @escaping @Sendable (
        _ request: SaveSOPSFileRequest
      ) async throws -> SavedSOPSFile,
    diagnoseTools: @escaping @Sendable () async -> [ToolDiagnostic]
  ) {
    self.open = open
    self.save = save
    self.diagnoseTools = diagnoseTools
  }
}
