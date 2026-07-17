import CipherleafDomain
import SwiftUI

struct SecretDetailView: View {
  @Environment(SecretsFacade.self) private var secrets

  var body: some View {
    Group {
      if let path = secrets.selectedPath,
        let value = secrets.value(at: path)
      {
        SecretEditor(path: path, value: value)
          .id(path)
      } else {
        ContentUnavailableView(
          "Select a value",
          systemImage: "key",
          description: Text("Values stay concealed until you select one.")
        )
      }
    }
    .navigationTitle(secrets.selectedPath?.display ?? "Editor")
  }
}

private struct SecretEditor: View {
  private enum FocusField {
    case content
  }

  @Environment(DiagnosticsPreferences.self) private var preferences
  @Environment(SecretsFacade.self) private var secrets
  @Environment(\.scenePhase) private var scenePhase

  let path: SecretPath
  let value: SecretValue

  @FocusState private var focusedField: FocusField?
  @State private var concealmentActivityID = UUID()
  @State private var isConfirmingRemoval = false
  @State private var isRevealed = false
  @State private var textDraft: String

  init(path: SecretPath, value: SecretValue) {
    self.path = path
    self.value = value
    switch value {
    case .string(let content), .number(let content):
      _textDraft = State(initialValue: content)
    case .object, .array, .boolean, .null:
      _textDraft = State(initialValue: "")
    }
  }

  var body: some View {
    Form {
      SecretIdentitySection(path: path, value: value)

      Section("Value") {
        Picker("Type", selection: kindBinding) {
          ForEach(SecretScalarKind.allCases) { kind in
            Text(kind.title).tag(kind)
          }
        }

        editor
      }

      Section {
        HStack {
          Button("Rename key…") {
            secrets.presentRename(at: path)
          }
          .disabled(path.editablePath == nil)

          Spacer()

          Button("Remove value", role: .destructive) {
            requestRemoval()
          }
        }
      } footer: {
        Text("Change summaries contain paths only. Values are never included.")
      }
    }
    .formStyle(.grouped)
    .disabled(!secrets.isOpen)
    .confirmationDialog(
      "Remove \(path.display)?",
      isPresented: $isConfirmingRemoval
    ) {
      Button("Remove", role: .destructive) {
        secrets.remove(at: path)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The encrypted file is not changed until you save.")
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
    .onChange(of: focusedField) {
      if focusedField == nil {
        commitDraftIfValid()
        secrets.endHistoryCoalescing()
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase != .active {
        isRevealed = false
      }
    }
    .onChange(of: value) { previousValue, currentValue in
      synchronizeDraft(with: currentValue)
      if previousValue.scalarKind != currentValue.scalarKind {
        isRevealed = false
      }
    }
  }

  @ViewBuilder
  private var editor: some View {
    switch value {
    case .string:
      LabeledContent("Content") {
        HStack {
          if isRevealed {
            TextField("Value", text: $textDraft)
              .textFieldStyle(.roundedBorder)
              .focused($focusedField, equals: .content)
          } else {
            SecureField("Value", text: $textDraft)
              .textFieldStyle(.roundedBorder)
              .focused($focusedField, equals: .content)
          }

          visibilityButton
        }
      }
      .onChange(of: textDraft) {
        secrets.set(.string(textDraft), at: path)
        recordSecretActivity()
      }

    case .number:
      LabeledContent("Content") {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 5) {
            Group {
              if isRevealed {
                TextField("Number", text: $textDraft)
              } else {
                SecureField("Number", text: $textDraft)
              }
            }
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .focused($focusedField, equals: .content)
            .onSubmit {
              commitDraftIfValid()
            }
            if let issue = secrets.validationIssues[path] {
              Label(issue, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            }
          }

          visibilityButton
        }
      }
      .onChange(of: textDraft) {
        validateNumberDraft()
        recordSecretActivity()
      }

    case .boolean:
      LabeledContent("Content") {
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
      }

    case .null:
      LabeledContent("Content") {
        Text("null")
          .font(.body.monospaced())
          .foregroundStyle(.secondary)
      }

    case .object, .array:
      Text("Select a scalar value from the list.")
    }
  }

  private var kindBinding: Binding<SecretScalarKind> {
    Binding(
      get: { value.scalarKind ?? .string },
      set: { kind in
        isRevealed = false
        secrets.changeKind(kind, at: path)
      }
    )
  }

  private var booleanBinding: Binding<Bool> {
    Binding(
      get: {
        guard case .boolean(let content) = secrets.value(at: path) else {
          return false
        }
        return content
      },
      set: { newValue in
        secrets.set(.boolean(newValue), at: path)
        recordSecretActivity()
      }
    )
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

  private func requestRemoval() {
    if preferences.confirmRemoval {
      isConfirmingRemoval = true
    } else {
      secrets.remove(at: path)
    }
  }

  private func recordSecretActivity() {
    guard isRevealed else {
      return
    }
    concealmentActivityID = UUID()
  }

  private var concealmentTaskID: SecretConcealmentTaskID {
    SecretConcealmentTaskID(
      activityID: concealmentActivityID,
      delaySeconds: preferences.autoConcealSeconds,
      isRevealed: isRevealed
    )
  }

  private func validateNumberDraft() {
    let message =
      SecretValue.validateNumber(textDraft)
      ? nil
      : "Enter a valid JSON number."
    secrets.setValidationIssue(message, at: path)
    if message == nil {
      secrets.set(.number(textDraft), at: path)
    }
  }

  private func commitDraftIfValid() {
    switch value {
    case .string:
      secrets.set(.string(textDraft), at: path)
    case .number:
      validateNumberDraft()
    case .object, .array, .boolean, .null:
      break
    }
  }

  private func synchronizeDraft(with currentValue: SecretValue) {
    switch currentValue {
    case .string(let content), .number(let content):
      if textDraft != content {
        textDraft = content
      }
    case .object, .array, .boolean, .null:
      textDraft = ""
    }
  }
}

private struct SecretIdentitySection: View {
  let path: SecretPath
  let value: SecretValue

  var body: some View {
    Section("Identity") {
      LabeledContent("Path") {
        Text(path.display)
          .font(.body.monospaced())
          .textSelection(.disabled)
      }
      LabeledContent("Stored type", value: value.kindName)
    }
  }
}
