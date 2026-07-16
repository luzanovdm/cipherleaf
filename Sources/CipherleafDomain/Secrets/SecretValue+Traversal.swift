import Foundation

extension SecretValue {
  public func scalarEntries(path: SecretPath = .root) -> [SecretEntry] {
    switch self {
    case .object(let values):
      values.keys.sorted().flatMap { key in
        values[key]?.scalarEntries(path: path.appending(.key(key))) ?? []
      }
    case .array(let values):
      values.indices.flatMap { index in
        values[index].scalarEntries(path: path.appending(.index(index)))
      }
    case .string, .number, .boolean, .null:
      [SecretEntry(path: path, kind: scalarKind ?? .string)]
    }
  }

  public func value(at path: SecretPath) -> SecretValue? {
    value(at: ArraySlice(path.components))
  }

  private func value(
    at components: ArraySlice<SecretPathComponent>
  ) -> SecretValue? {
    guard let component = components.first else {
      return self
    }

    let remaining = components.dropFirst()
    switch (self, component) {
    case (.object(let values), .key(let key)):
      return values[key]?.value(at: remaining)
    case (.array(let values), .index(let index))
    where values.indices.contains(index):
      return values[index].value(at: remaining)
    default:
      return nil
    }
  }
}
