import CipherleafDomain
import SwiftUI

struct RenameSecretSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(SecretsFacade.self) private var secrets

  let path: SecretPath

  @FocusState private var isFocused: Bool
  @State private var key: String

  init(path: SecretPath) {
    self.path = path
    let currentKey: String
    if case .key(let value)? = path.components.last {
      currentKey = value
    } else {
      currentKey = ""
    }
    _key = State(initialValue: currentKey)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Rename key")
          .font(.title2.weight(.semibold))
        Text(path.display)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
      }

      TextField("Key", text: $key)
        .focused($isFocused)
        .onSubmit {
          rename()
        }

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Spacer()
        Button("Rename") {
          rename()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isValid)
      }
    }
    .padding(24)
    .frame(width: 440)
    .onAppear {
      isFocused = true
    }
  }

  private var isValid: Bool {
    secrets.isValidRenameKey(key, at: path)
  }

  private func rename() {
    if secrets.rename(at: path, to: key) {
      dismiss()
    }
  }
}
