import CipherleafApplication
import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsFacade {
  let preferences: DiagnosticsPreferences

  private let session: DocumentSession

  init(
    preferences: DiagnosticsPreferences,
    session: DocumentSession
  ) {
    self.preferences = preferences
    self.session = session
  }

  var tools: [ToolDiagnostic] {
    session.toolDiagnostics
  }

  func refresh() async {
    await session.refreshToolDiagnostics()
  }
}
