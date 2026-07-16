import SwiftUI

struct MainWindow: View {
  @Environment(AppNoticeCenter.self) private var notices
  @Environment(DiagnosticsFacade.self) private var diagnostics
  @Environment(SecretsFacade.self) private var secrets
  @Environment(WorkspaceFacade.self) private var workspace

  @State private var isSecurityInspectorPresented = true

  var body: some View {
    @Bindable var notices = notices
    @Bindable var secrets = secrets
    @Bindable var workspace = workspace

    NavigationSplitView {
      WorkspaceSidebar()
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    } content: {
      SecretListView()
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
    } detail: {
      SecretDetailView()
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 1_040, minHeight: 680)
    .inspector(isPresented: $isSecurityInspectorPresented) {
      SecurityInspectorView()
        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
    }
    .toolbar {
      MainWindowToolbar(
        isSecurityInspectorPresented: $isSecurityInspectorPresented
      )
    }
    .overlay(alignment: .bottom) {
      MainWindowStatusOverlay(
        activityTitle: workspace.activityTitle,
        statusMessage: notices.statusMessage
      )
    }
    .sheet(isPresented: $secrets.isPresentingAddSecret) {
      AddSecretSheet()
    }
    .sheet(item: $secrets.renamePath) { path in
      RenameSecretSheet(path: path)
    }
    .sheet(isPresented: saveReviewBinding) {
      if let candidate = secrets.saveCandidate {
        SaveReviewSheet(candidate: candidate)
      }
    }
    .confirmationDialog(
      workspace.pendingAction?.title ?? "",
      isPresented: pendingActionBinding
    ) {
      if let action = workspace.pendingAction {
        Button("Discard changes", role: .destructive) {
          workspace.confirm(action)
        }
        Button("Cancel", role: .cancel) {}
      }
    } message: {
      Text(workspace.pendingAction?.message ?? "")
    }
    .alert(item: $notices.alert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .task {
      workspace.restoreIfNeeded()
      await diagnostics.refresh()
    }
    .onChange(of: workspace.phase) {
      if workspace.phase == .open || workspace.phase == .closed {
        secrets.synchronizeSelection()
      }
    }
  }

  private var pendingActionBinding: Binding<Bool> {
    Binding(
      get: { workspace.pendingAction != nil },
      set: { isPresented in
        if !isPresented {
          workspace.pendingAction = nil
        }
      }
    )
  }

  private var saveReviewBinding: Binding<Bool> {
    Binding(
      get: { secrets.saveCandidate != nil },
      set: { isPresented in
        if !isPresented {
          secrets.saveCandidate = nil
        }
      }
    )
  }
}

private struct MainWindowToolbar: ToolbarContent {
  @Environment(SecretsFacade.self) private var secrets
  @Environment(WorkspaceFacade.self) private var workspace

  @Binding var isSecurityInspectorPresented: Bool

  var body: some ToolbarContent {
    ToolbarItemGroup {
      Button("Open document", systemImage: "folder") {
        workspace.chooseManifest()
      }
      .disabled(workspace.isBusy)
      .help("Open SOPS document")

      Button("Choose identity", systemImage: "key") {
        workspace.chooseIdentity()
      }
      .disabled(workspace.isBusy)
      .help("Choose age identity")

      Button("Reload", systemImage: "arrow.clockwise") {
        workspace.requestReload()
      }
      .disabled(!workspace.hasOpenDocument || workspace.isBusy)
      .help("Reload encrypted document from disk")

      Button("Add value", systemImage: "plus") {
        secrets.isPresentingAddSecret = true
      }
      .disabled(workspace.phase != .open)

      Button("Save", systemImage: "lock.doc") {
        secrets.prepareSave()
      }
      .disabled(!secrets.canSave)

      Button("Security inspector", systemImage: "sidebar.trailing") {
        isSecurityInspectorPresented.toggle()
      }
      .help("Show or hide security inspector")
    }
  }
}

private struct MainWindowStatusOverlay: View {
  let activityTitle: String?
  let statusMessage: String?

  var body: some View {
    Group {
      if let activityTitle {
        ActivityBanner(title: activityTitle)
      } else if let statusMessage {
        StatusBanner(title: statusMessage)
      }
    }
    .padding()
  }
}
