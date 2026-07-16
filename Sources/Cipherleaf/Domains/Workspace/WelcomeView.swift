import SwiftUI

struct WelcomeView: View {
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    ContentUnavailableView {
      Label("Open an encrypted document", systemImage: "leaf.fill")
    } description: {
      Text(
        """
        An age identity is the private key file created by age-keygen. It \
        authorizes decryption for its matching public age1… recipient. Choose \
        the identity first, then open a SOPS YAML, JSON, or dotenv document.
        """
      )
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
