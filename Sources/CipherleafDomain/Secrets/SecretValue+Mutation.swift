import Foundation

extension SecretValue {
  public func setting(
    _ value: SecretValue,
    at path: SecretPath
  ) throws -> SecretValue {
    guard !path.components.isEmpty else {
      throw SecretValueError.cannotReplaceRoot
    }
    return try setting(value, at: ArraySlice(path.components))
  }

  public func adding(
    _ value: SecretValue,
    at path: SecretPath
  ) throws -> SecretValue {
    guard !path.components.isEmpty else {
      throw SecretValueError.cannotReplaceRoot
    }
    return try adding(value, at: ArraySlice(path.components))
  }

  public func removing(at path: SecretPath) throws -> SecretValue {
    guard !path.components.isEmpty else {
      throw SecretValueError.cannotRemoveRoot
    }
    return try removing(at: ArraySlice(path.components))
  }

  public func renaming(
    at path: SecretPath,
    to newKey: String
  ) throws -> SecretValue {
    guard let parent = path.parent,
      let last = path.components.last,
      case .key(let oldKey) = last,
      SecretPath(components: [.key(newKey)]).editablePath != nil
    else {
      throw SecretValueError.renameUnsupported
    }
    guard let value = value(at: path) else {
      throw SecretValueError.pathNotFound
    }

    let destination = parent.appending(.key(newKey))
    guard self.value(at: destination) == nil || oldKey == newKey else {
      throw SecretValueError.pathAlreadyExists
    }
    guard oldKey != newKey else {
      return self
    }
    return try removing(at: path).adding(value, at: destination)
  }

  public func incrementingRootGeneration() -> (
    value: SecretValue,
    generation: Int?
  ) {
    guard case .object(var values) = self,
      case .number(let rawGeneration)? = values["generation"],
      let generation = Int(rawGeneration)
    else {
      return (self, nil)
    }

    let (nextGeneration, didOverflow) = generation.addingReportingOverflow(1)
    guard !didOverflow else {
      return (self, nil)
    }
    values["generation"] = .number(String(nextGeneration))
    return (.object(values), nextGeneration)
  }

  private func setting(
    _ newValue: SecretValue,
    at components: ArraySlice<SecretPathComponent>
  ) throws -> SecretValue {
    guard let component = components.first else {
      return newValue
    }

    let remaining = components.dropFirst()
    switch (self, component) {
    case (.object(let existingValues), .key(let key)):
      guard let child = existingValues[key] else {
        throw SecretValueError.pathNotFound
      }
      var values = existingValues
      values[key] = try child.setting(newValue, at: remaining)
      return .object(values)

    case (.array(let existingValues), .index(let index)):
      guard existingValues.indices.contains(index) else {
        throw SecretValueError.pathNotFound
      }
      var values = existingValues
      values[index] = try values[index].setting(newValue, at: remaining)
      return .array(values)

    default:
      throw SecretValueError.pathNotFound
    }
  }

  private func adding(
    _ newValue: SecretValue,
    at components: ArraySlice<SecretPathComponent>
  ) throws -> SecretValue {
    guard let component = components.first else {
      throw SecretValueError.pathAlreadyExists
    }
    guard case .key(let key) = component else {
      throw SecretValueError.arrayInsertionUnsupported
    }
    guard case .object(var values) = self else {
      throw SecretValueError.expectedObject
    }

    let remaining = components.dropFirst()
    if remaining.isEmpty {
      guard values[key] == nil else {
        throw SecretValueError.pathAlreadyExists
      }
      values[key] = newValue
      return .object(values)
    }

    let child = values[key] ?? .object([:])
    values[key] = try child.adding(newValue, at: remaining)
    return .object(values)
  }

  private func removing(
    at components: ArraySlice<SecretPathComponent>
  ) throws -> SecretValue {
    guard let component = components.first else {
      throw SecretValueError.cannotRemoveRoot
    }

    let remaining = components.dropFirst()
    switch (self, component) {
    case (.object(let existingValues), .key(let key)):
      guard existingValues[key] != nil else {
        throw SecretValueError.pathNotFound
      }
      var values = existingValues
      if remaining.isEmpty {
        values.removeValue(forKey: key)
      } else if let child = values[key] {
        values[key] = try child.removing(at: remaining)
      }
      return .object(values)

    case (.array(let existingValues), .index(let index)):
      guard existingValues.indices.contains(index) else {
        throw SecretValueError.pathNotFound
      }
      var values = existingValues
      if remaining.isEmpty {
        values.remove(at: index)
      } else {
        values[index] = try values[index].removing(at: remaining)
      }
      return .array(values)

    default:
      throw SecretValueError.pathNotFound
    }
  }
}
