import Foundation

public struct SecretsDocument: Equatable, Sendable {
  public let baseline: SecretValue
  public private(set) var working: SecretValue

  public init(root: SecretValue) {
    baseline = root
    working = root
  }

  public init(baseline: SecretValue, working: SecretValue) {
    self.baseline = baseline
    self.working = working
  }

  public var entries: [SecretEntry] {
    working.scalarEntries()
  }

  public var patch: DocumentPatch {
    DocumentPatch.between(baseline: baseline, candidate: working)
  }

  public var isDirty: Bool {
    baseline != working
  }

  public func value(at path: SecretPath) -> SecretValue? {
    working.value(at: path)
  }

  public mutating func set(_ value: SecretValue, at path: SecretPath) throws {
    working = try working.setting(value, at: path)
  }

  public mutating func add(_ value: SecretValue, at path: SecretPath) throws {
    working = try working.adding(value, at: path)
  }

  public mutating func remove(at path: SecretPath) throws {
    working = try working.removing(at: path)
  }

  public mutating func rename(at path: SecretPath, to newKey: String) throws -> SecretPath {
    working = try working.renaming(at: path, to: newKey)
    guard let parent = path.parent else {
      throw SecretValueError.renameUnsupported
    }
    return parent.appending(.key(newKey))
  }

  public mutating func restore(_ root: SecretValue) {
    working = root
  }

  public func candidate(incrementingGeneration: Bool) -> SaveCandidate {
    guard incrementingGeneration else {
      return SaveCandidate(
        root: working,
        patch: patch,
        nextGeneration: nil
      )
    }

    let incremented = working.incrementingRootGeneration()
    return SaveCandidate(
      root: incremented.value,
      patch: DocumentPatch.between(
        baseline: baseline,
        candidate: incremented.value
      ),
      nextGeneration: incremented.generation
    )
  }
}

public struct SaveCandidate: Equatable, Sendable {
  public let root: SecretValue
  public let patch: DocumentPatch
  public let nextGeneration: Int?

  public init(root: SecretValue, patch: DocumentPatch, nextGeneration: Int?) {
    self.root = root
    self.patch = patch
    self.nextGeneration = nextGeneration
  }
}
