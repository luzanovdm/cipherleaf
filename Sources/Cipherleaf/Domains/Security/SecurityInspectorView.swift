import CipherleafDomain
import SwiftUI

struct SecurityInspectorView: View {
  var body: some View {
    Form {
      SecurityInspectorPurposeSection()
      IdentitySection()
      IdentityRecipientSection()
      DocumentSecuritySection()
      RecipientSection()
    }
    .formStyle(.grouped)
    .navigationTitle("Security Inspector")
  }
}

private struct SecurityInspectorPurposeSection: View {
  var body: some View {
    Section {
      Label("Verify access before editing", systemImage: "checkmark.shield")
      Text(
        """
        Confirm that the selected identity can decrypt this document. This \
        inspector shows only public encryption metadata, never secret values.
        """
      )
      .foregroundStyle(.secondary)
    }
  }
}

private struct IdentitySection: View {
  @Environment(SecurityFacade.self) private var security
  @Environment(WorkspaceFacade.self) private var workspace

  var body: some View {
    Section {
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
        } else {
          Label(
            "Valid native age identity",
            systemImage: "checkmark.shield.fill"
          )
          .foregroundStyle(.green)
        }
      } else {
        Button("Choose age identity…") {
          workspace.chooseIdentity()
        }
      }
    } header: {
      Text("Identity")
    } footer: {
      Text(
        """
        The identity is a private age key used to decrypt matching documents. \
        Cipherleaf verifies it without displaying or copying its contents.
        """
      )
    }
  }
}

private struct IdentityRecipientSection: View {
  @Environment(SecurityFacade.self) private var security

  var body: some View {
    if !security.identityRecipients.isEmpty {
      Section {
        ForEach(security.identityRecipients) { recipient in
          Text(recipient.abbreviated)
            .font(.caption.monospaced())
            .help(recipient.value)
            .accessibilityLabel(recipient.value)
        }
      } header: {
        Text("Public identity recipients")
      } footer: {
        Text(
          """
          These public identifiers are derived from the selected private \
          identity. A document must contain at least one of them in its SOPS \
          metadata.
          """
        )
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
    } else {
      Section("Document") {
        Label(
          "No encrypted document open",
          systemImage: "doc.badge.plus"
        )
        Text(
          """
          Open a SOPS document to inspect its format, nearest policy, and \
          recipient match.
          """
        )
        .foregroundStyle(.secondary)
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
        Text("Document recipients")
      } footer: {
        Text(
          """
          Recipient metadata is public. A checkmark identifies recipients \
          unlocked by the selected identity.
          """
        )
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
