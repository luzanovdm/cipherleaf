import CipherleafDomain
import SwiftUI

struct SecretListView: View {
  @Environment(SecretsFacade.self) private var secrets

  @State private var filteredEntries: [SecretEntry] = []
  @State private var query = ""

  var body: some View {
    @Bindable var secrets = secrets

    List(selection: $secrets.selectedPath) {
      if !secrets.hasOpenDocument {
        WelcomeView()
          .listRowSeparator(.hidden)
      } else if filteredEntries.isEmpty {
        Group {
          if query.isEmpty {
            ContentUnavailableView(
              "No scalar values",
              systemImage: "key.slash",
              description: Text(
                "Add a string, number, Boolean, or null value to this document."
              )
            )
          } else {
            ContentUnavailableView.search(text: query)
          }
        }
        .listRowSeparator(.hidden)
      } else {
        ForEach(filteredEntries) { entry in
          SecretRow(
            entry: entry,
            change: secrets.changeKind(at: entry.path),
            hasValidationIssue: secrets.validationIssues[entry.path] != nil
          )
          .tag(entry.path)
        }
      }
    }
    .listStyle(.inset)
    .navigationTitle("Values")
    .searchable(text: $query, prompt: "Search paths")
    .onChange(of: query, initial: true) {
      refreshFilter()
    }
    .onChange(of: secrets.entries) {
      refreshFilter()
    }
  }

  private func refreshFilter() {
    let entries = secrets.entries
    filteredEntries =
      query.isEmpty
      ? entries
      : entries.filter {
        $0.path.display.localizedCaseInsensitiveContains(query)
      }
  }
}

private struct SecretRow: View {
  let entry: SecretEntry
  let change: DocumentChangeKind?
  let hasValidationIssue: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "key.fill")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(entry.path.display)
          .font(.body.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
        Text(entry.kind.title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if hasValidationIssue {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityLabel("Invalid value")
      } else if let change {
        Image(systemName: change.systemImage)
          .foregroundStyle(change.tint)
          .help(change.title)
          .accessibilityLabel(change.title)
      }
    }
    .padding(.vertical, 3)
  }
}

extension DocumentChangeKind {
  fileprivate var systemImage: String {
    switch self {
    case .added:
      "plus.circle.fill"
    case .changed:
      "pencil.circle.fill"
    case .removed:
      "minus.circle.fill"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .added:
      .green
    case .changed:
      .blue
    case .removed:
      .red
    }
  }
}
