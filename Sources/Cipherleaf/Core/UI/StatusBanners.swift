import SwiftUI

struct ActivityBanner: View {
  let title: String

  var body: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
      Text(title)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: Capsule())
    .shadow(radius: 8, y: 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
  }
}

struct StatusBanner: View {
  let title: String

  var body: some View {
    Label(title, systemImage: "checkmark.shield")
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(.regularMaterial, in: Capsule())
      .shadow(radius: 8, y: 3)
      .accessibilityElement(children: .combine)
  }
}
