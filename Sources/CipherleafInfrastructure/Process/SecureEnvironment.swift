import Foundation

enum SecureEnvironment {
  static func sops(identityURL: URL? = nil) -> [String: String] {
    let inherited = ProcessInfo.processInfo.environment
    let allowedKeys = [
      "HOME",
      "LANG",
      "LC_ALL",
      "LOGNAME",
      "TMPDIR",
      "USER",
    ]
    var environment = Dictionary(
      uniqueKeysWithValues: allowedKeys.compactMap { key in
        inherited[key].map { (key, $0) }
      }
    )

    environment["SOPS_DISABLE_VERSION_CHECK"] = "1"

    if let identityURL {
      environment["SOPS_AGE_KEY_FILE"] = identityURL.path
      environment["SOPS_DECRYPTION_ORDER"] = "age"
    }

    return environment
  }
}
