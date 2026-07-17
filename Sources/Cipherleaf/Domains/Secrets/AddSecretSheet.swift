import CipherleafDomain
import SwiftUI

struct AddSecretSheet: View {
  private enum FocusField {
    case path
    case value
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(DiagnosticsPreferences.self) private var preferences
  @Environment(SecretsFacade.self) private var secrets

  @FocusState private var focusedField: FocusField?
  @State private var booleanValue = false
  @State private var concealmentActivityID = UUID()
  @State private var isRevealed = false
  @State private var kind = SecretScalarKind.string
  @State private var path = ""
  @State private var textValue = ""

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Location") {
          TextField("Path", text: $path, prompt: Text("database.password"))
            .font(.body.monospaced())
            .focused($focusedField, equals: .path)
            .onSubmit {
              focusedField = .value
            }
          Text("Use dots for nested object keys.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Value") {
          Picker("Type", selection: $kind) {
            ForEach(SecretScalarKind.allCases) { kind in
              Text(kind.title).tag(kind)
            }
          }

          valueEditor
        }
      }
      .formStyle(.grouped)

      Divider()

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Spacer()
        Button("Add") {
          add()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isValid)
      }
      .padding()
    }
    .frame(width: 500, height: 410)
    .onAppear {
      focusedField = .path
    }
    .task(id: concealmentTaskID) {
      guard isRevealed, preferences.autoConcealSeconds > 0 else {
        return
      }
      try? await Task.sleep(
        for: .seconds(preferences.autoConcealSeconds)
      )
      guard !Task.isCancelled else {
        return
      }
      isRevealed = false
    }
    .onChange(of: kind) {
      isRevealed = false
    }
    .onChange(of: textValue) {
      recordSecretActivity()
    }
    .onChange(of: scenePhase) {
      if scenePhase != .active {
        isRevealed = false
      }
    }
  }

  @ViewBuilder
  private var valueEditor: some View {
    switch kind {
    case .string:
      concealedTextField(label: "Content")
    case .number:
      concealedTextField(label: "Content", monospaced: true)
      if !textValue.isEmpty, !SecretValue.validateNumber(textValue) {
        Label(
          "Enter a valid JSON number.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    case .boolean:
      HStack {
        if isRevealed {
          Toggle("Enabled", isOn: booleanBinding)
        } else {
          Text("••••••••")
            .font(.body.monospaced())
            .accessibilityLabel("Concealed value")
        }
        Spacer()
        visibilityButton
      }
    case .null:
      Text("No content is stored for null.")
        .foregroundStyle(.secondary)
    }
  }

  private func concealedTextField(
    label: String,
    monospaced: Bool = false
  ) -> some View {
    HStack {
      Group {
        if isRevealed {
          TextField(label, text: $textValue)
        } else {
          SecureField(label, text: $textValue)
        }
      }
      .font(monospaced ? .body.monospaced() : .body)
      .focused($focusedField, equals: .value)

      visibilityButton
    }
  }

  private var visibilityButton: some View {
    Button(
      isRevealed ? "Conceal value" : "Reveal value",
      systemImage: isRevealed ? "eye.slash" : "eye"
    ) {
      isRevealed.toggle()
      recordSecretActivity()
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .help(isRevealed ? "Conceal value" : "Reveal value")
  }

  private var value: SecretValue {
    switch kind {
    case .string:
      .string(textValue)
    case .number:
      .number(textValue)
    case .boolean:
      .boolean(booleanValue)
    case .null:
      .null
    }
  }

  private var booleanBinding: Binding<Bool> {
    Binding(
      get: { booleanValue },
      set: { newValue in
        booleanValue = newValue
        recordSecretActivity()
      }
    )
  }

  private var concealmentTaskID: SecretConcealmentTaskID {
    SecretConcealmentTaskID(
      activityID: concealmentActivityID,
      delaySeconds: preferences.autoConcealSeconds,
      isRevealed: isRevealed
    )
  }

  private var isValid: Bool {
    guard (try? SecretPath.parseEditablePath(path)) != nil else {
      return false
    }
    return kind != .number || SecretValue.validateNumber(textValue)
  }

  private func add() {
    if secrets.add(path: path, value: value) {
      dismiss()
    }
  }

  private func recordSecretActivity() {
    guard isRevealed else {
      return
    }
    concealmentActivityID = UUID()
  }
}
