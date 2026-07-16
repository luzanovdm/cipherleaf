import Foundation
import Security

public enum StoredBookmark: String, Sendable {
  case identity
}

public struct KeychainBookmarkStore: Sendable {
  private let service = "app.cipherleaf.bookmarks"

  public init() {}

  public func save(_ url: URL, for bookmark: StoredBookmark) throws {
    let data = try bookmarkData(for: url)
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: bookmark.rawValue,
      kSecAttrSynchronizable as String: false,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]

    let updateStatus = SecItemUpdate(
      baseQuery as CFDictionary,
      attributes as CFDictionary
    )
    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainBookmarkError.status(updateStatus)
    }

    var insertQuery = baseQuery
    for (key, value) in attributes {
      insertQuery[key] = value
    }
    let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
    guard insertStatus == errSecSuccess else {
      throw KeychainBookmarkError.status(insertStatus)
    }
  }

  public func restore(_ bookmark: StoredBookmark) -> URL? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: bookmark.rawValue,
      kSecAttrSynchronizable as String: false,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }

    return resolve(data)
  }

  public func delete(_ bookmark: StoredBookmark) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: bookmark.rawValue,
      kSecAttrSynchronizable as String: false,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainBookmarkError.status(status)
    }
  }

  private func bookmarkData(for url: URL) throws -> Data {
    do {
      return try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    } catch {
      return try url.bookmarkData(
        options: [.minimalBookmark],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    }
  }

  private func resolve(_ data: Data) -> URL? {
    var isStale = false
    if let url = try? URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) {
      return url
    }

    return try? URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
  }
}

public final class SecurityScopedAccess {
  private let didStart: Bool
  private let url: URL

  public init(_ url: URL) {
    self.url = url
    didStart = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if didStart {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

enum KeychainBookmarkError: LocalizedError {
  case status(OSStatus)

  var errorDescription: String? {
    switch self {
    case .status(let status):
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "Keychain error: \(message)"
      }
      return "Keychain error \(status)."
    }
  }
}
