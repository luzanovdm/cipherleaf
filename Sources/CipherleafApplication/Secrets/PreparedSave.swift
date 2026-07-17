import CipherleafDomain
import Foundation

public struct PreparedSave: Identifiable, Sendable {
  public let id = UUID()
  public let candidate: SaveCandidate

  let contentVersion: UUID
  let incrementingGeneration: Bool
  let revisionDigest: String
}
