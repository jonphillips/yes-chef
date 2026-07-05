import Dependencies
import Foundation
import LLMClientKit
import Observation
import YesChefCore

@MainActor
@Observable
final class AISettingsModel {
  var keyInputs: [FrontierProvider: String] = [:]
  var tasteProfile = ""
  var chefItUpPreference = ""
  var serveWithPreference = ""
  var makeAheadPrepPlanPreference = ""
  var complementsPreference = ""
  var errorMessage: String?
  var isShowingError = false

  private(set) var storedProviders: Set<FrontierProvider> = []
  private(set) var keyPreviews: [FrontierProvider: String] = [:]
  private var savedPreferences = AISettingsRepository.defaultSettings(
    now: Date(timeIntervalSinceReferenceDate: 0)
  )

  @ObservationIgnored @Dependency(\.apiKeyStore) private var apiKeyStore
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database

  let providers = FrontierProvider.allCases

  func onAppear() {
    refresh()
    loadPreferences()
  }

  var hasUnsavedPreferenceChanges: Bool {
    tasteProfile != savedPreferences.tasteProfile
      || chefItUpPreference != savedPreferences.chefItUpPreference
      || serveWithPreference != savedPreferences.serveWithPreference
      || makeAheadPrepPlanPreference != savedPreferences.makeAheadPrepPlanPreference
      || complementsPreference != savedPreferences.complementsPreference
  }

  func hasStoredKey(_ provider: FrontierProvider) -> Bool {
    storedProviders.contains(provider)
  }

  func keyPreview(for provider: FrontierProvider) -> String? {
    keyPreviews[provider]
  }

  func keyInput(for provider: FrontierProvider) -> String {
    keyInputs[provider] ?? ""
  }

  func setKeyInput(_ value: String, for provider: FrontierProvider) {
    keyInputs[provider] = value
  }

  func canSave(_ provider: FrontierProvider) -> Bool {
    !keyInput(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func save(_ provider: FrontierProvider) {
    apiKeyStore.setKey(keyInputs[provider], for: provider)
    keyInputs[provider] = ""
    refresh()
  }

  func clear(_ provider: FrontierProvider) {
    apiKeyStore.setKey(nil, for: provider)
    keyInputs[provider] = ""
    refresh()
  }

  func savePreferencesButtonTapped() {
    let settings = AISettingsRecord(
      id: AISettingsRepository.singletonID,
      tasteProfile: tasteProfile,
      chefItUpPreference: chefItUpPreference,
      serveWithPreference: serveWithPreference,
      makeAheadPrepPlanPreference: makeAheadPrepPlanPreference,
      complementsPreference: complementsPreference,
      dateModified: now
    )
    do {
      try database.write { db in
        try AISettingsRepository.save(settings, in: db)
      }
      savedPreferences = settings
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  private func refresh() {
    storedProviders = Set(providers.filter { apiKeyStore.key($0) != nil })
    keyPreviews = Dictionary(
      uniqueKeysWithValues: providers.compactMap { provider in
        apiKeyStore.maskedKey(provider).map { (provider, $0) }
      })
  }

  private func loadPreferences() {
    do {
      let settings = try database.read { db in
        try AISettingsRepository.currentSettings(in: db, now: now)
      }
      apply(settings)
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  private func apply(_ settings: AISettingsRecord) {
    savedPreferences = settings
    tasteProfile = settings.tasteProfile
    chefItUpPreference = settings.chefItUpPreference
    serveWithPreference = settings.serveWithPreference
    makeAheadPrepPlanPreference = settings.makeAheadPrepPlanPreference
    complementsPreference = settings.complementsPreference
  }
}
