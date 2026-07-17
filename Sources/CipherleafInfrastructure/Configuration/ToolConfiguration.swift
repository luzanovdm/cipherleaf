import Darwin
import Foundation

public struct ToolConfiguration: Equatable, Sendable {
  public var sopsPath: String
  public var ageKeygenPath: String

  public init(sopsPath: String = "", ageKeygenPath: String = "") {
    self.sopsPath = sopsPath
    self.ageKeygenPath = ageKeygenPath
  }
}

public final class ToolConfigurationStore: @unchecked Sendable {
  private let lock = NSLock()
  private var storedConfiguration: ToolConfiguration

  public init(_ configuration: ToolConfiguration = ToolConfiguration()) {
    storedConfiguration = configuration
  }

  public var configuration: ToolConfiguration {
    get {
      lock.withLock { storedConfiguration }
    }
    set {
      lock.withLock {
        storedConfiguration = newValue
      }
    }
  }
}

enum ExternalTool: String, Sendable {
  case sops
  case ageKeygen = "age-keygen"
}

struct ToolLocator: Sendable {
  let configurationStore: ToolConfigurationStore

  func resolve(_ tool: ExternalTool) throws -> URL {
    let configuredPath = configuredPath(for: tool)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !configuredPath.isEmpty {
      return try validate(
        tool,
        at: URL(fileURLWithPath: configuredPath)
      )
    }

    for directory in candidateDirectories {
      let candidate = directory.appendingPathComponent(tool.rawValue)
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return try validate(tool, at: candidate)
      }
    }

    throw ToolLocatorError.notFound(tool)
  }

  private func configuredPath(for tool: ExternalTool) -> String {
    switch tool {
    case .sops:
      configurationStore.configuration.sopsPath
    case .ageKeygen:
      configurationStore.configuration.ageKeygenPath
    }
  }

  private var candidateDirectories: [URL] {
    var paths = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
    ]

    if let path = ProcessInfo.processInfo.environment["PATH"] {
      paths.append(contentsOf: path.split(separator: ":").map(String.init))
    }

    var seen = Set<String>()
    return paths.compactMap { path in
      guard seen.insert(path).inserted else {
        return nil
      }
      return URL(fileURLWithPath: path, isDirectory: true)
    }
  }

  private func validate(_ tool: ExternalTool, at url: URL) throws -> URL {
    let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
    guard FileManager.default.isExecutableFile(atPath: resolvedURL.path) else {
      throw ToolLocatorError.configuredPathIsNotExecutable(tool, resolvedURL)
    }

    let attributes = try FileManager.default.attributesOfItem(
      atPath: resolvedURL.path
    )
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw ToolLocatorError.notRegularFile(tool, resolvedURL)
    }
    guard
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
      let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
    else {
      throw ToolLocatorError.cannotVerifyTrust(tool, resolvedURL)
    }
    guard permissions & 0o022 == 0 else {
      throw ToolLocatorError.insecurePermissions(tool, resolvedURL)
    }

    let currentUser = Darwin.getuid()
    guard owner == 0 || owner == currentUser else {
      throw ToolLocatorError.untrustedOwner(tool, resolvedURL)
    }

    return resolvedURL
  }
}

enum ToolLocatorError: LocalizedError {
  case cannotVerifyTrust(ExternalTool, URL)
  case configuredPathIsNotExecutable(ExternalTool, URL)
  case insecurePermissions(ExternalTool, URL)
  case notFound(ExternalTool)
  case notRegularFile(ExternalTool, URL)
  case untrustedOwner(ExternalTool, URL)

  var errorDescription: String? {
    switch self {
    case .cannotVerifyTrust(let tool, let url):
      "Could not verify the owner and permissions of \(tool.rawValue) at \(url.path)."
    case .configuredPathIsNotExecutable(let tool, let url):
      "\(tool.rawValue) is not executable at \(url.path)."
    case .insecurePermissions(let tool, let url):
      "\(tool.rawValue) is writable by a group or other users at \(url.path)."
    case .notFound(let tool):
      "Could not find \(tool.rawValue). Install it with Homebrew or set its path in Settings."
    case .notRegularFile(let tool, let url):
      "\(tool.rawValue) is not a regular file at \(url.path)."
    case .untrustedOwner(let tool, let url):
      "\(tool.rawValue) is not owned by the current user or root at \(url.path)."
    }
  }
}
