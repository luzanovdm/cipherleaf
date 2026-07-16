import AppKit
import CipherleafApplication
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
  private(set) var selectedIdentityURL: URL?

  private let bookmarks: KeychainBookmarkStore
  private let notices: AppNoticeCenter
  private let recentStore: RecentDocumentsStore
  private let session: DocumentSession
  private var didRestore = false
  private var pendingManifestAfterIdentitySelection: URL?

  init(
    session: DocumentSession,
    notices: AppNoticeCenter,
    bookmarks: KeychainBookmarkStore = KeychainBookmarkStore(),
    recentStore: RecentDocumentsStore = RecentDocumentsStore()
  ) {
    self.session = session
    self.notices = notices
    self.bookmarks = bookmarks
    self.recentStore = recentStore
    recentDocuments = recentStore.urls
  }

  var identityName: String? {
    selectedIdentityURL?.lastPathComponent
  }

  var activityTitle: String? {
    session.phase.activityTitle
  }

  var hasOpenDocument: Bool {
    session.document != nil
  }

  var isBusy: Bool {
    session.isBusy
  }

  var manifestURL: URL? {
    session.manifestURL
  }

  var phase: DocumentSession.Phase {
    session.phase
  }

  func restoreIfNeeded() {
    guard !didRestore else {
      return
    }
    didRestore = true
    selectedIdentityURL = bookmarks.restore(.identity)
    recentDocuments = recentStore.urls
  }

  func chooseIdentity() {
    guard canStartDocumentOperation() else {
      return
    }
    guard let url = FilePanels.chooseIdentity() else {
      return
    }
    selectIdentity(url)
  }

  func selectIdentity(_ url: URL) {
    guard canStartDocumentOperation() else {
      return
    }
    if selectedIdentityURL?.standardizedFileURL == url.standardizedFileURL,
      pendingManifestAfterIdentitySelection == nil
    {
      storeIdentitySelection(url)
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

    guard let manifestURL else {
      storeIdentitySelection(url)
      return
    }

    Task {
      await open(
        manifestURL,
        using: url,
        updatesIdentitySelection: true
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
      try bookmarks.delete(.identity)
      selectedIdentityURL = nil
      notices.statusMessage = "Age identity bookmark removed."
    } catch {
      notices.present(error)
    }
  }

  func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func open(_ manifestURL: URL) async {
    guard let identityURL = selectedIdentityURL else {
      pendingManifestAfterIdentitySelection = manifestURL
      chooseIdentity()
      if pendingManifestAfterIdentitySelection != nil {
        pendingManifestAfterIdentitySelection = nil
        notices.present(
          title: "An age identity is required",
          message: "Choose an identity before opening an encrypted document."
        )
      }
      return
    }

    await open(
      manifestURL,
      using: identityURL,
      updatesIdentitySelection: false
    )
  }

  private func open(
    _ manifestURL: URL,
    using identityURL: URL,
    updatesIdentitySelection: Bool
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
        storeIdentitySelection(identityURL, statusMessage: nil)
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
    statusMessage: String? = "Age identity selected."
  ) {
    selectedIdentityURL = url
    do {
      try bookmarks.save(url, for: .identity)
      notices.statusMessage = statusMessage
    } catch {
      notices.present(error)
    }
  }

  private func canStartDocumentOperation() -> Bool {
    guard !session.isBusy else {
      notices.present(DocumentSessionError.documentBusy)
      return false
    }
    return true
  }
}
