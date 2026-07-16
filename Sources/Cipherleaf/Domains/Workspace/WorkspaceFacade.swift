import AppKit
import CipherleafApplication
import CipherleafDomain
import CipherleafInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceFacade {
  enum PendingAction: Identifiable {
    case closeDocument
    case openDocument(URL)
    case reloadDocument
    case selectIdentity(URL)

    var id: String {
      switch self {
      case .closeDocument:
        "close"
      case .openDocument(let url):
        "open:\(url.path)"
      case .reloadDocument:
        "reload"
      case .selectIdentity(let url):
        "identity:\(url.path)"
      }
    }

    var title: String {
      switch self {
      case .closeDocument:
        "Close without saving?"
      case .openDocument:
        "Open another document?"
      case .reloadDocument:
        "Reload from disk?"
      case .selectIdentity:
        "Switch age identity?"
      }
    }

    var message: String {
      "Unsaved in-memory changes will be discarded."
    }
  }

  var pendingAction: PendingAction?
  private(set) var recentDocuments: [URL] = []

  private let identitySelection: AgeIdentitySelection
  private let notices: AppNoticeCenter
  private let recentStore: RecentDocumentsStore
  private let session: DocumentSession
  private var didRestore = false
  private var pendingManifestAfterIdentitySelection: URL?

  init(
    session: DocumentSession,
    identityClient: AgeIdentityClient,
    notices: AppNoticeCenter,
    bookmarks: KeychainBookmarkStore = KeychainBookmarkStore(),
    recentStore: RecentDocumentsStore = RecentDocumentsStore()
  ) {
    self.session = session
    identitySelection = AgeIdentitySelection(
      client: identityClient,
      bookmarks: bookmarks
    )
    self.notices = notices
    self.recentStore = recentStore
    recentDocuments = recentStore.urls
  }

  var identityName: String? {
    identitySelection.url?.lastPathComponent
  }

  var selectedIdentityRecipients: [AgeRecipient] {
    identitySelection.recipients
  }

  var activityTitle: String? {
    identitySelection.isInspecting
      ? "Checking age identity…"
      : session.phase.activityTitle
  }

  var hasOpenDocument: Bool {
    session.document != nil
  }

  var isBusy: Bool {
    session.isBusy || identitySelection.isInspecting
  }

  var manifestURL: URL? {
    session.manifestURL
  }

  var phase: DocumentSession.Phase {
    session.phase
  }

  func restoreIfNeeded() async {
    guard !didRestore else {
      return
    }
    didRestore = true
    recentDocuments = recentStore.urls

    do {
      try await identitySelection.restore()
    } catch {
      notices.present(
        title: "Saved age identity is unavailable",
        message: error.localizedDescription
      )
    }
  }

  func chooseIdentity() {
    guard canStartDocumentOperation() else {
      return
    }
    guard let url = FilePanels.chooseIdentity() else {
      if pendingManifestAfterIdentitySelection != nil {
        pendingManifestAfterIdentitySelection = nil
        notices.present(
          title: "An age identity is required",
          message: "Choose an identity before opening an encrypted document."
        )
      }
      return
    }
    selectIdentity(url)
  }

  func selectIdentity(_ url: URL) {
    guard canStartDocumentOperation() else {
      return
    }
    guard !session.isDirty else {
      pendingAction = .selectIdentity(url)
      return
    }

    let manifestURL =
      pendingManifestAfterIdentitySelection
      ?? session.manifestURL
    pendingManifestAfterIdentitySelection = nil

    Task {
      await inspectAndUseIdentity(
        url,
        manifestURL: manifestURL
      )
    }
  }

  func chooseManifest() {
    guard canStartDocumentOperation() else {
      return
    }
    guard let url = FilePanels.chooseManifest() else {
      return
    }
    requestOpen(url)
  }

  func requestOpen(_ url: URL) {
    guard canStartDocumentOperation() else {
      return
    }
    guard !session.isDirty else {
      pendingAction = .openDocument(url)
      return
    }
    Task {
      await open(url)
    }
  }

  func requestReload() {
    guard canStartDocumentOperation() else {
      return
    }
    guard !session.isDirty else {
      pendingAction = .reloadDocument
      return
    }
    Task {
      await reload()
    }
  }

  func requestClose() {
    guard canStartDocumentOperation() else {
      return
    }
    guard !session.isDirty else {
      pendingAction = .closeDocument
      return
    }
    close()
  }

  func confirm(_ action: PendingAction) {
    pendingAction = nil
    switch action {
    case .closeDocument:
      close()
    case .openDocument(let url):
      Task {
        await open(url)
      }
    case .reloadDocument:
      Task {
        await reload()
      }
    case .selectIdentity(let url):
      session.discardChanges()
      selectIdentity(url)
    }
  }

  func removeRecent(_ url: URL) {
    recentStore.remove(url)
    recentDocuments = recentStore.urls
  }

  func forgetIdentity() {
    guard canStartDocumentOperation() else {
      return
    }
    guard session.document == nil else {
      notices.present(
        title: "Close the document first",
        message: "Close the current document before forgetting its age identity."
      )
      return
    }

    do {
      try identitySelection.remove()
      notices.statusMessage = "Age identity bookmark removed."
    } catch {
      notices.present(error)
    }
  }

  func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func open(_ manifestURL: URL) async {
    guard let identityURL = identitySelection.url else {
      pendingManifestAfterIdentitySelection = manifestURL
      chooseIdentity()
      return
    }

    await open(
      manifestURL,
      using: identityURL,
      updatesIdentitySelection: false,
      verifiedIdentityRecipients: nil
    )
  }

  private func open(
    _ manifestURL: URL,
    using identityURL: URL,
    updatesIdentitySelection: Bool,
    verifiedIdentityRecipients: [AgeRecipient]?
  ) async {
    let manifestAccess = SecurityScopedAccess(manifestURL)
    let identityAccess = SecurityScopedAccess(identityURL)
    defer {
      _ = manifestAccess
      _ = identityAccess
    }

    do {
      try await session.open(
        manifestURL: manifestURL,
        identityURL: identityURL
      )
      if updatesIdentitySelection {
        storeIdentitySelection(
          identityURL,
          recipients: verifiedIdentityRecipients
            ?? session.identityRecipients,
          statusMessage: nil
        )
      }
      recentStore.record(manifestURL)
      recentDocuments = recentStore.urls
      notices.statusMessage = "Decrypted in memory."
    } catch {
      notices.present(error)
    }
  }

  private func reload() async {
    let manifestAccess = session.manifestURL.map(SecurityScopedAccess.init)
    let identityAccess = session.identityURL.map(SecurityScopedAccess.init)
    defer {
      _ = manifestAccess
      _ = identityAccess
    }

    do {
      try await session.reloadDiscardingChanges()
      notices.statusMessage = "Reloaded from disk."
    } catch {
      notices.present(error)
    }
  }

  private func close() {
    do {
      try session.close()
      notices.statusMessage = nil
    } catch {
      notices.present(error)
    }
  }

  private func storeIdentitySelection(
    _ url: URL,
    recipients: [AgeRecipient],
    statusMessage: String? = "Age identity selected."
  ) {
    do {
      try identitySelection.store(url, recipients: recipients)
      notices.statusMessage = statusMessage
    } catch {
      notices.present(error)
    }
  }

  private func inspectAndUseIdentity(
    _ identityURL: URL,
    manifestURL: URL?
  ) async {
    do {
      let recipients = try await identitySelection.inspect(identityURL)
      guard let manifestURL else {
        storeIdentitySelection(
          identityURL,
          recipients: recipients,
          statusMessage: "Age identity verified."
        )
        return
      }

      await open(
        manifestURL,
        using: identityURL,
        updatesIdentitySelection: true,
        verifiedIdentityRecipients: recipients
      )
    } catch is CancellationError {
      return
    } catch {
      if session.document == nil {
        pendingManifestAfterIdentitySelection = manifestURL
      }
      notices.present(
        title: "Not a usable age identity",
        message: error.localizedDescription
      )
    }
  }

  private func canStartDocumentOperation() -> Bool {
    guard !isBusy else {
      notices.present(DocumentSessionError.documentBusy)
      return false
    }
    return true
  }
}
