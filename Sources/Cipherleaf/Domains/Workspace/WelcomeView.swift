import SwiftUI

struct WelcomeView: View {
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    ContentUnavailableView {
      Label("Open an encrypted document", systemImage: "leaf.fill")
    } description: {
      Text("Choose an age identity, then open a SOPS YAML, JSON, or dotenv document.")
    } actions: {
      HStack {
        Button("Choose identity") {
          workspace.chooseIdentity()
        }
        Button("Open document") {
          workspace.chooseManifest()
        }
        .buttonStyle(.borderedProminent)
      }
      .disabled(workspace.isBusy)
    }
  }
}
