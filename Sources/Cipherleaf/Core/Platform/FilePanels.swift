import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanels {
  static func chooseManifest() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Open SOPS document"
    panel.prompt = "Open"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.allowedContentTypes = [
      UTType(filenameExtension: "yaml"),
      UTType(filenameExtension: "yml"),
      UTType(filenameExtension: "env"),
      UTType(filenameExtension: "dotenv"),
      .json,
    ].compactMap { $0 }
    return panel.runModal() == .OK ? panel.url : nil
  }

  static func chooseIdentity() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Choose age identity"
    panel.prompt = "Choose"
    panel.message = "Cipherleaf keeps the identity in its current location."
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    return panel.runModal() == .OK ? panel.url : nil
  }

  static func chooseExecutable(named name: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Choose \(name)"
    panel.prompt = "Choose"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    return panel.runModal() == .OK ? panel.url : nil
  }
}
