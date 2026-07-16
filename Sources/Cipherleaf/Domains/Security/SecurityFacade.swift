import CipherleafApplication
import CipherleafDomain
import Foundation
import Observation

@MainActor
@Observable
final class SecurityFacade {
  private let session: DocumentSession
  private let workspace: WorkspaceFacade

  init(session: DocumentSession, workspace: WorkspaceFacade) {
    self.session = session
    self.workspace = workspace
  }

  var identityName: String? {
    workspace.identityName
  }

  var recipients: [AgeRecipient] {
    session.recipients
  }

  var identityRecipients: [AgeRecipient] {
    session.document == nil
      ? workspace.selectedIdentityRecipients
      : session.identityRecipients
  }

  var identityMatchesMetadata: Bool {
    session.identityMatchesMetadata
  }

  var policyURL: URL? {
    session.policyURL
  }

  var format: SOPSFileFormat? {
    session.format
  }

  var isDocumentOpen: Bool {
    session.document != nil
  }
}
