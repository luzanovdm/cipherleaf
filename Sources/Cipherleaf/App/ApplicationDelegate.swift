import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
  var activityTitle: (() -> String?)?
  var discardChanges: (() -> Void)?
  var hasUnsavedChanges: (() -> Bool)?

  func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      presentMainWindow(in: sender)
    }
    return true
  }

  func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    if let activityTitle = activityTitle?() {
      let alert = NSAlert()
      alert.alertStyle = .informational
      alert.messageText = "Document operation in progress"
      alert.informativeText = "\(activityTitle) Wait for it to finish before quitting."
      alert.addButton(withTitle: "OK")
      alert.runModal()
      presentMainWindow(in: sender)
      return .terminateCancel
    }

    guard hasUnsavedChanges?() == true else {
      return .terminateNow
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Unsaved encrypted document changes"
    alert.informativeText =
      "Your edits exist only in memory. Review and save them, or discard them before quitting."
    alert.addButton(withTitle: "Review Changes")
    alert.addButton(withTitle: "Discard and Quit")

    if alert.runModal() == .alertSecondButtonReturn {
      discardChanges?()
      return .terminateNow
    }
    presentMainWindow(in: sender)
    return .terminateCancel
  }

  private func presentMainWindow(in application: NSApplication) {
    application.activate()
    application.windows
      .first(where: { $0.title == "Cipherleaf" })?
      .makeKeyAndOrderFront(nil)
  }
}
