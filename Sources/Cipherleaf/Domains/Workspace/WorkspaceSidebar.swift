import SwiftUI

struct WorkspaceSidebar: View {
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    List {
      WorkspaceDocumentSection()
      RecentDocumentsSection()
    }
    .navigationTitle("Cipherleaf")
    .safeAreaInset(edge: .bottom) {
      if workspace.hasOpenDocument {
        Button("Close document") {
          workspace.requestClose()
        }
        .buttonStyle(.plain)
        .disabled(workspace.isBusy)
        .foregroundStyle(.secondary)
        .padding()
      }
    }
  }
}

private struct WorkspaceDocumentSection: View {
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    Section("Workspace") {
      if let manifestURL = workspace.manifestURL {
        Button {
          workspace.revealInFinder(manifestURL)
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(manifestURL.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
              Text(manifestURL.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            }
          } icon: {
            Image(systemName: "lock.doc")
          }
        }
        .buttonStyle(.plain)
        .help("Reveal in Finder")
      } else {
        Button("Open encrypted document…") {
          workspace.chooseManifest()
        }
      }

      if let identityName = workspace.identityName {
        Label(identityName, systemImage: "key")
          .lineLimit(1)
          .truncationMode(.middle)
          .contextMenu {
            Button("Forget Identity", role: .destructive) {
              workspace.forgetIdentity()
            }
          }
      } else {
        Button("Choose age identity…") {
          workspace.chooseIdentity()
        }
      }
    }
  }
}

private struct RecentDocumentsSection: View {
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    if !workspace.recentDocuments.isEmpty {
      Section("Recent") {
        ForEach(workspace.recentDocuments, id: \.path) { url in
          Button {
            workspace.requestOpen(url)
          } label: {
            Label(url.lastPathComponent, systemImage: "clock")
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .buttonStyle(.plain)
          .disabled(workspace.isBusy)
          .contextMenu {
            Button("Reveal in Finder") {
              workspace.revealInFinder(url)
            }
            Button("Remove from Recent", role: .destructive) {
              workspace.removeRecent(url)
            }
          }
        }
      }
    }
  }
}
