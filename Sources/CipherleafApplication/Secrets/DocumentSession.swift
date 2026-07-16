import CipherleafDomain
import Foundation
import Observation

@MainActor
@Observable
public final class DocumentSession {
  public enum Phase: Equatable, Sendable {
    case closed
    case opening
    case open
    case saving

    public var activityTitle: String? {
      switch self {
      case .closed, .open:
        nil
      case .opening:
        "Decrypting…"
      case .saving:
        "Applying encrypted patch and verifying…"
      }
    }
  }

  public private(set) var document: SecretsDocument?
  public private(set) var format: SOPSFileFormat?
  public private(set) var identityRecipients: [AgeRecipient] = []
  public private(set) var identityURL: URL?
  public private(set) var manifestURL: URL?
  public private(set) var phase = Phase.closed
  public private(set) var policyURL: URL?
  public private(set) var recipients: [AgeRecipient] = []
  public private(set) var revision: FileRevision?
  public private(set) var sourceContainsComments = false
  public private(set) var toolDiagnostics: [ToolDiagnostic] = []

  private var cachedEntries: [SecretEntry] = []
  private var cachedChangeKinds: [SecretPath: DocumentChangeKind] = [:]
  private var cachedPatch = DocumentPatch(operations: [], changes: [])
  private let client: EncryptedFileClient
  private let historyLimit: Int
  private var lastCoalescingKey: String?
  private var redoStack: [HistoryEntry] = []
  private var undoStack: [HistoryEntry] = []

  public init(client: EncryptedFileClient, historyLimit: Int = 100) {
    self.client = client
    self.historyLimit = max(0, historyLimit)
  }

  public var entries: [SecretEntry] {
    cachedEntries
  }

  public var changes: [DocumentChange] {
    cachedPatch.changes
  }

  public func changeKind(at path: SecretPath) -> DocumentChangeKind? {
    cachedChangeKinds[path]
  }

  public var isDirty: Bool {
    !cachedPatch.operations.isEmpty
  }

  public var isBusy: Bool {
    phase == .opening || phase == .saving
  }

  public var canSave: Bool {
    isDirty && phase == .open
  }

  public var canUndo: Bool {
    !undoStack.isEmpty && phase == .open
  }

  public var canRedo: Bool {
    !redoStack.isEmpty && phase == .open
  }

  public var undoActionName: String? {
    undoStack.last?.name
  }

  public var redoActionName: String? {
    redoStack.last?.name
  }

  public var identityMatchesMetadata: Bool {
    !Set(recipients).isDisjoint(with: identityRecipients)
  }

  public func open(manifestURL: URL, identityURL: URL) async throws {
    guard !isBusy else {
      throw DocumentSessionError.documentBusy
    }
    phase = .opening
    defer {
      if phase == .opening {
        phase = document == nil ? .closed : .open
      }
    }

    let opened = try await client.open(manifestURL, identityURL)
    document = SecretsDocument(root: opened.root)
    format = opened.format
    identityRecipients = opened.identityRecipients
    self.identityURL = identityURL
    self.manifestURL = manifestURL
    policyURL = opened.policyURL
    recipients = opened.recipients
    revision = opened.revision
    sourceContainsComments = opened.sourceContainsComments
    refreshDerivedState()
    undoStack.removeAll(keepingCapacity: true)
    redoStack.removeAll(keepingCapacity: true)
    lastCoalescingKey = nil
    phase = .open
  }

  public func reloadDiscardingChanges() async throws {
    guard let manifestURL, let identityURL else {
      return
    }
    try await open(manifestURL: manifestURL, identityURL: identityURL)
  }

  public func close() throws {
    guard !isBusy else {
      throw DocumentSessionError.documentBusy
    }
    document = nil
    format = nil
    identityRecipients.removeAll(keepingCapacity: false)
    identityURL = nil
    manifestURL = nil
    policyURL = nil
    recipients.removeAll(keepingCapacity: false)
    revision = nil
    sourceContainsComments = false
    cachedEntries.removeAll(keepingCapacity: false)
    cachedChangeKinds.removeAll(keepingCapacity: false)
    cachedPatch = DocumentPatch(operations: [], changes: [])
    undoStack.removeAll(keepingCapacity: false)
    redoStack.removeAll(keepingCapacity: false)
    lastCoalescingKey = nil
    phase = .closed
  }

  public func value(at path: SecretPath) -> SecretValue? {
    document?.value(at: path)
  }

  public func set(_ value: SecretValue, at path: SecretPath) throws {
    try mutate(
      name: "Edit Value",
      coalescingKey: "set:\(path.id)"
    ) { document in
      try document.set(value, at: path)
    }
  }

  public func changeKind(_ kind: SecretScalarKind, at path: SecretPath) throws {
    try mutate(name: "Change Value Type") { document in
      try document.set(.defaultValue(for: kind), at: path)
    }
  }

  public func add(_ value: SecretValue, at path: SecretPath) throws {
    try mutate(name: "Add Value") { document in
      try document.add(value, at: path)
    }
  }

  public func remove(at path: SecretPath) throws {
    try mutate(name: "Remove Value") { document in
      try document.remove(at: path)
    }
  }

  public func rename(at path: SecretPath, to newKey: String) throws -> SecretPath {
    var destination: SecretPath?
    try mutate(name: "Rename Key") { document in
      destination = try document.rename(at: path, to: newKey)
    }
    guard let destination else {
      throw DocumentSessionError.mutationDidNotProduceDestination
    }
    return destination
  }

  public func discardChanges() {
    guard phase == .open, let document else {
      return
    }
    self.document = SecretsDocument(root: document.baseline)
    refreshDerivedState()
    undoStack.removeAll(keepingCapacity: true)
    redoStack.removeAll(keepingCapacity: true)
    lastCoalescingKey = nil
  }

  public func undo() {
    guard phase == .open,
      let entry = undoStack.popLast(),
      var document
    else {
      return
    }

    redoStack.append(
      HistoryEntry(name: entry.name, root: document.working)
    )
    document.restore(entry.root)
    self.document = document
    refreshDerivedState()
    lastCoalescingKey = nil
  }

  public func redo() {
    guard phase == .open,
      let entry = redoStack.popLast(),
      var document
    else {
      return
    }

    undoStack.append(
      HistoryEntry(name: entry.name, root: document.working)
    )
    document.restore(entry.root)
    self.document = document
    refreshDerivedState()
    lastCoalescingKey = nil
  }

  public func endHistoryCoalescing() {
    lastCoalescingKey = nil
  }

  public func prepareSave(incrementingGeneration: Bool) -> SaveCandidate? {
    guard phase == .open, let document else {
      return nil
    }
    let candidate = document.candidate(
      incrementingGeneration: incrementingGeneration
    )
    return candidate.patch.operations.isEmpty ? nil : candidate
  }

  public func save(_ candidate: SaveCandidate) async throws {
    guard phase == .open else {
      throw DocumentSessionError.documentBusy
    }
    guard let manifestURL,
      let identityURL,
      let format,
      let revision
    else {
      throw DocumentSessionError.noOpenDocument
    }

    phase = .saving
    defer {
      phase = self.document == nil ? .closed : .open
    }

    let saved = try await client.save(
      SaveSOPSFileRequest(
        manifestURL: manifestURL,
        identityURL: identityURL,
        format: format,
        expectedRevision: revision,
        originalRecipients: recipients,
        candidate: candidate
      )
    )

    self.document = SecretsDocument(root: candidate.root)
    self.revision = saved.revision
    sourceContainsComments = saved.sourceContainsComments
    refreshDerivedState()
    undoStack.removeAll(keepingCapacity: true)
    redoStack.removeAll(keepingCapacity: true)
    lastCoalescingKey = nil
  }

  public func refreshToolDiagnostics() async {
    toolDiagnostics = await client.diagnoseTools()
  }

  private func mutate(
    name: String,
    coalescingKey: String? = nil,
    _ mutation: (inout SecretsDocument) throws -> Void
  ) throws {
    guard phase == .open else {
      throw DocumentSessionError.documentBusy
    }
    guard var document else {
      throw DocumentSessionError.noOpenDocument
    }

    let previousRoot = document.working
    try mutation(&document)
    guard document.working != previousRoot else {
      return
    }

    if coalescingKey == nil || coalescingKey != lastCoalescingKey {
      undoStack.append(HistoryEntry(name: name, root: previousRoot))
      if undoStack.count > historyLimit {
        undoStack.removeFirst(undoStack.count - historyLimit)
      }
    }
    lastCoalescingKey = coalescingKey
    redoStack.removeAll(keepingCapacity: true)
    self.document = document
    refreshDerivedState()
  }

  private func refreshDerivedState() {
    cachedEntries = document?.entries ?? []
    cachedPatch = document?.patch ?? DocumentPatch(operations: [], changes: [])
    cachedChangeKinds = Dictionary(
      uniqueKeysWithValues: cachedPatch.changes.map { ($0.path, $0.kind) }
    )
  }
}

private struct HistoryEntry {
  let name: String
  let root: SecretValue
}

public enum DocumentSessionError: LocalizedError {
  case documentBusy
  case mutationDidNotProduceDestination
  case noOpenDocument

  public var errorDescription: String? {
    switch self {
    case .documentBusy:
      "Wait for the current document operation to finish."
    case .mutationDidNotProduceDestination:
      "The rename operation did not produce a destination path."
    case .noOpenDocument:
      "No encrypted document is open."
    }
  }
}
