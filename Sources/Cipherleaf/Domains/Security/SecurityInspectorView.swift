import CipherleafDomain
import SwiftUI

struct SecurityInspectorView: View {
  var body: some View {
    Form {
      IdentitySection()
      DocumentSecuritySection()
      RecipientSection()
    }
    .formStyle(.grouped)
    .navigationTitle("Security")
  }
}

private struct IdentitySection: View {
  @Environment(SecurityFacade.self) private var security
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    Section("Identity") {
      if let identityName = security.identityName {
        Label(identityName, systemImage: "key")
          .lineLimit(1)
          .truncationMode(.middle)
        if security.isDocumentOpen {
          Label(
            security.identityMatchesMetadata
              ? "Matches document"
              : "Does not match document",
            systemImage: security.identityMatchesMetadata
              ? "checkmark.shield.fill"
              : "xmark.shield.fill"
          )
          .foregroundStyle(
            security.identityMatchesMetadata ? .green : .red
          )
        }
      } else {
        Button("Choose age identity…") {
          workspace.chooseIdentity()
        }
      }
    }
  }
}

private struct DocumentSecuritySection: View {
  @Environment(SecurityFacade.self) private var security
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    if security.isDocumentOpen {
      Section("Document") {
        if let format = security.format {
          LabeledContent("Format", value: format.title)
        }

        if let policyURL = security.policyURL {
          Button {
            workspace.revealInFinder(policyURL)
          } label: {
            LabeledContent("Policy") {
              Text(policyURL.lastPathComponent)
            }
          }
          .buttonStyle(.plain)
          .help("Reveal .sops.yaml in Finder")
        } else {
          Label("No .sops.yaml found", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }
    }
  }
}

private struct RecipientSection: View {
  @Environment(SecurityFacade.self) private var security

  var body: some View {
    if security.isDocumentOpen {
      Section {
        ForEach(security.recipients) { recipient in
          RecipientRow(
            recipient: recipient,
            matchesIdentity: security.identityRecipients.contains(recipient)
          )
        }
      } header: {
        Text("Age recipients")
      } footer: {
        Text("Recipient metadata is public. Private identity contents are never displayed.")
      }
    }
  }
}

private struct RecipientRow: View {
  let recipient: AgeRecipient
  let matchesIdentity: Bool

  var body: some View {
    HStack {
      Text(recipient.abbreviated)
        .font(.caption.monospaced())
        .help(recipient.value)
        .accessibilityLabel(recipient.value)
      Spacer()
      if matchesIdentity {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel("Selected identity")
      }
    }
  }
}
