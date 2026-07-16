import Foundation

struct RecentDocumentsStore {
  private let defaults: UserDefaults
  private let key = "recentDocuments"
  private let limit = 8

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var urls: [URL] {
    (defaults.stringArray(forKey: key) ?? []).map {
      URL(fileURLWithPath: $0)
    }.filter {
      FileManager.default.fileExists(atPath: $0.path)
    }
  }

  func record(_ url: URL) {
    let path = url.standardizedFileURL.path
    var paths = urls.map(\.path).filter { $0 != path }
    paths.insert(path, at: 0)
    defaults.set(Array(paths.prefix(limit)), forKey: key)
  }

  func remove(_ url: URL) {
    defaults.set(
      urls.map(\.path).filter { $0 != url.standardizedFileURL.path },
      forKey: key
    )
  }
}
