import CipherleafApplication
import CipherleafInfrastructure
import SwiftUI

@main
struct CipherleafApp: App {
  @NSApplicationDelegateAdaptor(ApplicationDelegate.self)
  private var applicationDelegate

  @State private var diagnostics: DiagnosticsFacade
  @State private var notices: AppNoticeCenter
  @State private var preferences: DiagnosticsPreferences
  @State private var secrets: SecretsFacade
  @State private var security: SecurityFacade
  @State private var workspace: WorkspaceFacade

  init() {
    let preferences = DiagnosticsPreferences()
    let notices = AppNoticeCenter()
    let session = DocumentSession(
      client: SOPSCLIClient.live(
        configurationStore: preferences.toolConfigurationStore
      )
    )
    let workspace = WorkspaceFacade(
      session: session,
      notices: notices
    )
    let secrets = SecretsFacade(
      session: session,
      preferences: preferences,
      notices: notices
    )
    let security = SecurityFacade(
      session: session,
      workspace: workspace
    )
    let diagnostics = DiagnosticsFacade(
      preferences: preferences,
      session: session
    )

    _diagnostics = State(initialValue: diagnostics)
    _notices = State(initialValue: notices)
    _preferences = State(initialValue: preferences)
    _secrets = State(initialValue: secrets)
    _security = State(initialValue: security)
    _workspace = State(initialValue: workspace)
    applicationDelegate.activityTitle = { [weak session] in
      session?.phase.activityTitle
    }
    applicationDelegate.hasUnsavedChanges = { [weak session] in
      session?.isDirty == true
    }
    applicationDelegate.discardChanges = { [weak session] in
      session?.discardChanges()
    }
  }

  var body: some Scene {
    Window("Cipherleaf", id: "main") {
      MainWindow()
        .environment(diagnostics)
        .environment(notices)
        .environment(preferences)
        .environment(secrets)
        .environment(security)
        .environment(workspace)
        .onOpenURL { url in
          workspace.requestOpen(url)
        }
    }
    .defaultSize(width: 1_240, height: 780)
    .defaultLaunchBehavior(.presented)
    .restorationBehavior(.disabled)
    .commands {
      SidebarCommands()
      DocumentCommands(
        secrets: secrets,
        workspace: workspace
      )
    }

    Settings {
      SettingsView()
        .environment(diagnostics)
        .environment(preferences)
    }
  }
}

private struct DocumentCommands: Commands {
  let secrets: SecretsFacade
  let workspace: WorkspaceFacade

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Open SOPS Document…") {
        workspace.chooseManifest()
      }
      .keyboardShortcut("o")
      .disabled(workspace.isBusy)

      Button("Choose Age Identity…") {
        workspace.chooseIdentity()
      }
      .keyboardShortcut("i", modifiers: [.command, .shift])
      .disabled(workspace.isBusy)

      Divider()

      Button("Reload from Disk") {
        workspace.requestReload()
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
      .disabled(!workspace.hasOpenDocument || workspace.isBusy)
    }

    CommandGroup(replacing: .saveItem) {
      Button("Save Encrypted Document") {
        secrets.prepareSave()
      }
      .keyboardShortcut("s")
      .disabled(!secrets.canSave)
    }

    CommandGroup(replacing: .undoRedo) {
      Button(secrets.undoActionName.map { "Undo \($0)" } ?? "Undo") {
        secrets.undo()
      }
      .keyboardShortcut("z")
      .disabled(!secrets.canUndo)

      Button(secrets.redoActionName.map { "Redo \($0)" } ?? "Redo") {
        secrets.redo()
      }
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .disabled(!secrets.canRedo)
    }
  }
}
