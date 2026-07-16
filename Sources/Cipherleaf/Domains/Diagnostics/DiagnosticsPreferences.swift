import CipherleafInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsPreferences {
  private enum Key {
    static let ageKeygenPath = "tools.ageKeygenPath"
    static let autoConcealSeconds = "security.autoConcealSeconds"
    static let confirmRemoval = "security.confirmRemoval"
    static let incrementGeneration = "editing.incrementGeneration"
    static let sopsPath = "tools.sopsPath"
  }

  var sopsPath: String {
    didSet {
      defaults.set(sopsPath, forKey: Key.sopsPath)
      synchronizeToolConfiguration()
    }
  }

  var ageKeygenPath: String {
    didSet {
      defaults.set(ageKeygenPath, forKey: Key.ageKeygenPath)
      synchronizeToolConfiguration()
    }
  }

  var autoConcealSeconds: Int {
    didSet {
      defaults.set(autoConcealSeconds, forKey: Key.autoConcealSeconds)
    }
  }

  var confirmRemoval: Bool {
    didSet {
      defaults.set(confirmRemoval, forKey: Key.confirmRemoval)
    }
  }

  var incrementGeneration: Bool {
    didSet {
      defaults.set(incrementGeneration, forKey: Key.incrementGeneration)
    }
  }

  let toolConfigurationStore: ToolConfigurationStore
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    let restoredSOPSPath = defaults.string(forKey: Key.sopsPath) ?? ""
    let restoredAgeKeygenPath =
      defaults.string(forKey: Key.ageKeygenPath) ?? ""

    self.defaults = defaults
    sopsPath = restoredSOPSPath
    ageKeygenPath = restoredAgeKeygenPath
    let restoredAutoConcealSeconds =
      defaults.object(forKey: Key.autoConcealSeconds) == nil
      ? 30
      : defaults.integer(forKey: Key.autoConcealSeconds)
    autoConcealSeconds =
      [0, 10, 30, 60].contains(restoredAutoConcealSeconds)
      ? restoredAutoConcealSeconds
      : 30
    confirmRemoval =
      defaults.object(forKey: Key.confirmRemoval) == nil
      ? true
      : defaults.bool(forKey: Key.confirmRemoval)
    incrementGeneration =
      defaults.object(forKey: Key.incrementGeneration) == nil
      ? false
      : defaults.bool(forKey: Key.incrementGeneration)
    toolConfigurationStore = ToolConfigurationStore(
      ToolConfiguration(
        sopsPath: restoredSOPSPath,
        ageKeygenPath: restoredAgeKeygenPath
      )
    )
  }

  private func synchronizeToolConfiguration() {
    toolConfigurationStore.configuration = ToolConfiguration(
      sopsPath: sopsPath,
      ageKeygenPath: ageKeygenPath
    )
  }
}
