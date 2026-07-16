import CipherleafApplication
import SwiftUI

struct SettingsView: View {
  @Environment(DiagnosticsFacade.self) private var diagnostics
  @Environment(DiagnosticsPreferences.self) private var preferences

  var body: some View {
    @Bindable var preferences = preferences

    TabView {
      Form {
        Section("Command-line tools") {
          ToolPathRow(
            name: "SOPS",
            path: $preferences.sopsPath
          )
          ToolPathRow(
            name: "age-keygen",
            path: $preferences.ageKeygenPath
          )
        }

        Section("Status") {
          ForEach(diagnostics.tools, id: \.name) { tool in
            ToolDiagnosticRow(tool: tool)
          }
          Button("Run diagnostics") {
            Task {
              await diagnostics.refresh()
            }
          }
        }
      }
      .formStyle(.grouped)
      .tabItem {
        Label("Tools", systemImage: "wrench.and.screwdriver")
      }

      Form {
        Section("Editing") {
          Toggle(
            "Increment a numeric root generation on save",
            isOn: $preferences.incrementGeneration
          )
          Toggle(
            "Confirm before removing values",
            isOn: $preferences.confirmRemoval
          )
        }

        Section("Value visibility") {
          Picker(
            "Automatically conceal revealed values",
            selection: $preferences.autoConcealSeconds
          ) {
            Text("After 10 seconds").tag(10)
            Text("After 30 seconds").tag(30)
            Text("After 1 minute").tag(60)
            Text("Never").tag(0)
          }
        }
      }
      .formStyle(.grouped)
      .tabItem {
        Label("Editing", systemImage: "slider.horizontal.3")
      }
    }
    .scenePadding()
    .frame(width: 680, height: 430)
  }
}

private struct ToolPathRow: View {
  let name: String
  @Binding var path: String

  var body: some View {
    LabeledContent(name) {
      HStack {
        TextField("Auto-detect", text: $path)
        Button("Choose…") {
          if let url = FilePanels.chooseExecutable(named: name) {
            path = url.path
          }
        }
      }
    }
  }
}

private struct ToolDiagnosticRow: View {
  let tool: ToolDiagnostic

  var body: some View {
    switch tool.state {
    case .available(let path, let version):
      LabeledContent {
        VStack(alignment: .trailing, spacing: 2) {
          Text(version ?? "Available")
          Text(path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      } label: {
        Label(tool.name, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }

    case .unavailable(let message):
      LabeledContent {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      } label: {
        Label(tool.name, systemImage: "xmark.circle.fill")
          .foregroundStyle(.red)
      }
    }
  }
}
