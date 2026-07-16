import CipherleafDomain
import Foundation

public struct AgeIdentityClient: Sendable {
  public var inspect: @Sendable (_ identityURL: URL) async throws -> [AgeRecipient]

  public init(
    inspect:
      @escaping @Sendable (
        _ identityURL: URL
      ) async throws -> [AgeRecipient]
  ) {
    self.inspect = inspect
  }
}
