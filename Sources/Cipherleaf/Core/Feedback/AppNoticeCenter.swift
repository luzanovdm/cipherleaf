import Foundation
import Observation

@MainActor
@Observable
final class AppNoticeCenter {
  var alert: AppAlert?
  var statusMessage: String?

  func present(_ error: Error) {
    alert = AppAlert(
      title: "Cipherleaf could not complete the operation",
      message: error.localizedDescription
    )
  }

  func present(title: String, message: String) {
    alert = AppAlert(title: title, message: message)
  }
}

struct AppAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
