import CipherleafDomain
import SwiftUI

struct SaveReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(SecretsFacade.self) private var secrets

  let candidate: SaveCandidate

  var body: some View {
    VStack(spacing: 0) {
      SaveReviewHeader(
        nextGeneration: candidate.nextGeneration,
        sourceContainsComments: secrets.sourceContainsComments
      )

      List(candidate.patch.changes) { change in
        HStack {
          Image(systemName: change.systemImage)
            .accessibilityHidden(true)
          Text(change.path.display)
            .font(.body.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Text(change.kind.title)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .disabled(!secrets.isOpen)
        Spacer()
        if secrets.isOpen {
          Button("Encrypt and save") {
            save()
          }
          .buttonStyle(.borderedProminent)
        } else {
          ProgressView("Encrypting and verifying…")
        }
      }
      .padding()
    }
    .frame(width: 660, height: 540)
    .interactiveDismissDisabled(!secrets.isOpen)
  }

  private func save() {
    Task {
      await secrets.save(candidate)
      if secrets.saveCandidate == nil {
        dismiss()
      }
    }
  }
}

private struct SaveReviewHeader: View {
  let nextGeneration: Int?
  let sourceContainsComments: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Ready to encrypt", systemImage: "lock.shield")
        .font(.title2.weight(.semibold))
      Text("Review the paths below. Secret values are intentionally omitted.")
        .foregroundStyle(.secondary)
      if let nextGeneration {
        Text("Root generation will become \(nextGeneration).")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if sourceContainsComments {
        Label(
          "SOPS may remove comments from this encrypted document while applying the patch. Move important notes elsewhere before continuing.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}

extension DocumentChange {
  fileprivate var systemImage: String {
    switch kind {
    case .added:
      "plus.circle.fill"
    case .changed:
      "pencil.circle.fill"
    case .removed:
      "minus.circle.fill"
    }
  }
}
