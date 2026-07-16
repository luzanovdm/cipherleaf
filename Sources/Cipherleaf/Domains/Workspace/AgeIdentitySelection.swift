import CipherleafApplication
import CipherleafDomain
import CipherleafInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class AgeIdentitySelection {
  private(set) var isInspecting = false
  private(set) var recipients: [AgeRecipient] = []
  private(set) var url: URL?

  private let bookmarks: KeychainBookmarkStore
  private let client: AgeIdentityClient

  init(
    client: AgeIdentityClient,
    bookmarks: KeychainBookmarkStore
  ) {
    self.client = client
    self.bookmarks = bookmarks
  }

  func restore() async throws {
    guard let restoredURL = bookmarks.restore(.identity) else {
      return
    }

    do {
      let restoredRecipients = try await inspect(restoredURL)
      recipients = restoredRecipients
      url = restoredURL
    } catch {
      try? bookmarks.delete(.identity)
      recipients = []
      url = nil
      throw error
    }
  }

  func inspect(_ identityURL: URL) async throws -> [AgeRecipient] {
    isInspecting = true
    defer {
      isInspecting = false
    }

    let identityAccess = SecurityScopedAccess(identityURL)
    defer {
      _ = identityAccess
    }

    return try await client.inspect(identityURL)
  }

  func store(
    _ identityURL: URL,
    recipients: [AgeRecipient]
  ) throws {
    self.recipients = recipients
    url = identityURL
    try bookmarks.save(identityURL, for: .identity)
  }

  func remove() throws {
    try bookmarks.delete(.identity)
    recipients = []
    url = nil
  }
}
