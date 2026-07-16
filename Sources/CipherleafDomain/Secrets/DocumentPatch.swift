import Foundation

public enum DocumentChangeKind: String, Sendable {
  case added
  case changed
  case removed

  public var title: String {
    rawValue.capitalized
  }
}

public struct DocumentChange: Identifiable, Equatable, Sendable {
  public let path: SecretPath
  public let kind: DocumentChangeKind

  public init(path: SecretPath, kind: DocumentChangeKind) {
    self.path = path
    self.kind = kind
  }

  public var id: String {
    "\(kind.rawValue):\(path.display)"
  }
}

public enum PatchOperation: Equatable, Sendable {
  case set(path: SecretPath, value: SecretValue)
  case unset(path: SecretPath)

  public var path: SecretPath {
    switch self {
    case .set(let path, _), .unset(let path):
      path
    }
  }
}

public struct DocumentPatch: Equatable, Sendable {
  public let operations: [PatchOperation]
  public let changes: [DocumentChange]

  public init(operations: [PatchOperation], changes: [DocumentChange]) {
    self.operations = operations
    self.changes = changes
  }

  public static func between(
    baseline: SecretValue,
    candidate: SecretValue
  ) -> DocumentPatch {
    var operations: [PatchOperation] = []
    diff(
      baseline: baseline,
      candidate: candidate,
      path: .root,
      operations: &operations
    )

    let sortedOperations = operations.sorted { lhs, rhs in
      switch (lhs, rhs) {
      case (.unset, .set):
        return false
      case (.set, .unset):
        return true
      case (.unset, .unset):
        if lhs.path.depth == rhs.path.depth {
          return lhs.path.display < rhs.path.display
        }
        return lhs.path.depth > rhs.path.depth
      case (.set, .set):
        return lhs.path.display < rhs.path.display
      }
    }

    let changes = sortedOperations.map { operation in
      switch operation {
      case .set(let path, _):
        let kind: DocumentChangeKind =
          baseline.value(at: path) == nil ? .added : .changed
        return DocumentChange(path: path, kind: kind)
      case .unset(let path):
        return DocumentChange(path: path, kind: .removed)
      }
    }

    return DocumentPatch(operations: sortedOperations, changes: changes)
  }

  private static func diff(
    baseline: SecretValue,
    candidate: SecretValue,
    path: SecretPath,
    operations: inout [PatchOperation]
  ) {
    guard baseline != candidate else {
      return
    }

    switch (baseline, candidate) {
    case (.object(let oldValues), .object(let newValues)):
      let keys = Set(oldValues.keys).union(newValues.keys).sorted()
      for key in keys {
        let childPath = path.appending(.key(key))
        switch (oldValues[key], newValues[key]) {
        case (.some(let oldValue), .some(let newValue)):
          diff(
            baseline: oldValue,
            candidate: newValue,
            path: childPath,
            operations: &operations
          )
        case (.none, .some(let newValue)):
          operations.append(.set(path: childPath, value: newValue))
        case (.some, .none):
          operations.append(.unset(path: childPath))
        case (.none, .none):
          break
        }
      }

    case (.array(let oldValues), .array(let newValues))
    where oldValues.count == newValues.count:
      for index in oldValues.indices {
        diff(
          baseline: oldValues[index],
          candidate: newValues[index],
          path: path.appending(.index(index)),
          operations: &operations
        )
      }

    default:
      guard path != .root else {
        return
      }
      operations.append(.set(path: path, value: candidate))
    }
  }
}
