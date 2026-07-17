import CipherleafApplication
import CipherleafDomain
import CipherleafInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class SecretsFacade {
  enum Sheet: Identifiable {
    case addSecret
    case rename(SecretPath)
    case saveReview(PreparedSave)

    var id: String {
      switch self {
      case .addSecret:
        "add-secret"
      case .rename(let path):
        "rename:\(path.id)"
      case .saveReview(let preparedSave):
        "save:\(preparedSave.id.uuidString)"
      }
    }
  }

  var presentedSheet: Sheet?
  var selectedPath: SecretPath?

  private(set) var validationIssues: [SecretPath: String] = [:]

  private let notices: AppNoticeCenter
  private let preferences: DiagnosticsPreferences
  private let session: DocumentSession

  init(
    session: DocumentSession,
    preferences: DiagnosticsPreferences,
    notices: AppNoticeCenter
  ) {
    self.session = session
    self.preferences = preferences
    self.notices = notices
  }

  var entries: [SecretEntry] {
    session.entries
  }

  var changes: [DocumentChange] {
    session.changes
  }

  var canSave: Bool {
    session.canSave && validationIssues.isEmpty
  }

  var canRedo: Bool {
    session.canRedo
  }

  var canUndo: Bool {
    session.canUndo
  }

  var hasOpenDocument: Bool {
    session.document != nil
  }

  var sourceContainsComments: Bool {
    session.sourceContainsComments
  }

  var isOpen: Bool {
    session.phase == .open
  }

  var redoActionName: String? {
    session.redoActionName
  }

  var undoActionName: String? {
    session.undoActionName
  }

  func synchronizeSelection() {
    validationIssues.removeAll(keepingCapacity: true)
    repairPresentedSheet()
    repairSelection()
  }

  func presentAddSecret() {
    guard isOpen else {
      return
    }
    presentedSheet = .addSecret
  }

  func presentRename(at path: SecretPath) {
    guard isOpen, session.value(at: path) != nil else {
      return
    }
    presentedSheet = .rename(path)
  }

  func value(at path: SecretPath) -> SecretValue? {
    session.value(at: path)
  }

  func changeKind(at path: SecretPath) -> DocumentChangeKind? {
    session.changeKind(at: path)
  }

  func add(path rawPath: String, value: SecretValue) -> Bool {
    do {
      let path = try SecretPath.parseEditablePath(rawPath)
      try session.add(value, at: path)
      selectedPath = path
      notices.statusMessage = nil
      return true
    } catch {
      notices.present(error)
      return false
    }
  }

  func set(_ value: SecretValue, at path: SecretPath) {
    do {
      try session.set(value, at: path)
      notices.statusMessage = nil
    } catch {
      notices.present(error)
    }
  }

  func changeKind(_ kind: SecretScalarKind, at path: SecretPath) {
    do {
      try session.changeKind(kind, at: path)
      validationIssues.removeValue(forKey: path)
      notices.statusMessage = nil
    } catch {
      notices.present(error)
    }
  }

  func remove(at path: SecretPath) {
    do {
      try session.remove(at: path)
      validationIssues.removeValue(forKey: path)
      repairSelection()
      notices.statusMessage = nil
    } catch {
      notices.present(error)
    }
  }

  func rename(at path: SecretPath, to newKey: String) -> Bool {
    do {
      selectedPath = try session.rename(at: path, to: newKey)
      validationIssues.removeValue(forKey: path)
      presentedSheet = nil
      notices.statusMessage = nil
      return true
    } catch {
      notices.present(error)
      return false
    }
  }

  func setValidationIssue(_ message: String?, at path: SecretPath) {
    if let message {
      validationIssues[path] = message
    } else {
      validationIssues.removeValue(forKey: path)
    }
  }

  func endHistoryCoalescing() {
    session.endHistoryCoalescing()
  }

  func undo() {
    session.undo()
    repairSelection()
  }

  func redo() {
    session.redo()
    repairSelection()
  }

  func discardChanges() {
    session.discardChanges()
    validationIssues.removeAll(keepingCapacity: true)
    repairSelection()
    notices.statusMessage = "In-memory changes discarded."
  }

  func prepareSave() {
    guard validationIssues.isEmpty else {
      notices.present(
        title: "Resolve invalid values",
        message: "Correct the highlighted fields before saving."
      )
      return
    }
    guard
      let candidate = session.prepareSave(
        incrementingGeneration: preferences.incrementGeneration
      )
    else {
      notices.statusMessage = "No changes to save."
      return
    }
    presentedSheet = .saveReview(candidate)
  }

  func save(_ preparedSave: PreparedSave) async {
    let manifestAccess = session.manifestURL.map(SecurityScopedAccess.init)
    let identityAccess = session.identityURL.map(SecurityScopedAccess.init)
    defer {
      _ = manifestAccess
      _ = identityAccess
    }

    do {
      try await session.save(preparedSave)
      presentedSheet = nil
      validationIssues.removeAll(keepingCapacity: true)
      notices.statusMessage = "Encrypted patch verified and installed atomically."
    } catch {
      repairPresentedSheet()
      notices.present(error)
    }
  }

  private func repairPresentedSheet() {
    switch presentedSheet {
    case .addSecret:
      if !isOpen {
        presentedSheet = nil
      }
    case .rename(let path):
      if !isOpen || session.value(at: path) == nil {
        presentedSheet = nil
      }
    case .saveReview(let preparedSave):
      if !session.isCurrent(preparedSave) {
        presentedSheet = nil
      }
    case nil:
      break
    }
  }

  private func repairSelection() {
    if let selectedPath, session.value(at: selectedPath) != nil {
      return
    }
    selectedPath = session.entries.first?.path
  }
}
