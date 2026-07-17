import Foundation

struct SecretConcealmentTaskID: Equatable {
  let activityID: UUID
  let delaySeconds: Int
  let isRevealed: Bool
}
