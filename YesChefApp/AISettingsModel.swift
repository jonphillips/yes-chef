import Dependencies
import Foundation
import LLMClientKit
import Observation
import YesChefCore

@MainActor
@Observable
final class AISettingsModel {
  var keyInputs: [FrontierProvider: String] = [:]
  var customModelInputs: [FrontierProvider: String] = [:]
  var usesDefaultModel: [FrontierProvider: Bool] = [:]
  var tasteProfile = ""
  var chefItUpPreference = ""
  var serveWithPreference = ""
  var makeAheadPrepPlanPreference = ""
  var complementsPreference = ""
  var captureToNotePreference = AISettingsRepository.defaultCaptureToNotePreference
  var readerFeedbackPreference = ""
  var errorMessage: String?
  var isShowingError = false

  private(set) var storedProviders: Set<FrontierProvider> = []
  private(set) var keyPreviews: [FrontierProvider: String] = [:]
  private var savedModels: [FrontierProvider: String] = [:]
  private var savedPreferences = AISettingsRepository.defaultSettings(
    now: Date(timeIntervalSinceReferenceDate: 0)
  )

  @ObservationIgnored @Dependency(\.apiKeyStore) private var apiKeyStore
  @ObservationIgnored @Dependency(\.frontierModelPreference) private var modelPreference
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database

  let providers = FrontierProvider.allCases

  func onAppear() {
    refresh()
    loadModels()
    loadPreferences()
  }

  var hasUnsavedPreferenceChanges: Bool {
    tasteProfile != savedPreferences.tasteProfile
      || chefItUpPreference != savedPreferences.chefItUpPreference
      || serveWithPreference != savedPreferences.serveWithPreference
      || makeAheadPrepPlanPreference != savedPreferences.makeAheadPrepPlanPreference
      || complementsPreference != savedPreferences.complementsPreference
      || captureToNotePreference != savedPreferences.captureToNotePreference
      || readerFeedbackPreference != savedPreferences.readerFeedbackPreference
      || providers.contains { configuredModel(for: $0) != savedModels[$0] }
  }

  var hasInvalidCustomModel: Bool {
    providers.contains {
      !isUsingDefaultModel($0)
        && configuredModel(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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

  func configuredModel(for provider: FrontierProvider) -> String {
    isUsingDefaultModel(provider) ? provider.defaultModel : (customModelInputs[provider] ?? "")
  }

  func isUsingDefaultModel(_ provider: FrontierProvider) -> Bool {
    usesDefaultModel[provider] ?? true
  }

  func setUsesDefaultModel(_ usesDefault: Bool, for provider: FrontierProvider) {
    usesDefaultModel[provider] = usesDefault
  }

  func setCustomModel(_ model: String, for provider: FrontierProvider) {
    customModelInputs[provider] = model.trimmingCharacters(in: .whitespacesAndNewlines)
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
    guard !hasInvalidCustomModel else { return }
    let settings = AISettingsRecord(
      id: AISettingsRepository.singletonID,
      tasteProfile: tasteProfile,
      chefItUpPreference: chefItUpPreference,
      serveWithPreference: serveWithPreference,
      makeAheadPrepPlanPreference: makeAheadPrepPlanPreference,
      complementsPreference: complementsPreference,
      captureToNotePreference: captureToNotePreference,
      readerFeedbackPreference: readerFeedbackPreference,
      dateModified: now
    )
    do {
      try database.write { db in
        try AISettingsRepository.save(settings, in: db)
      }
      for provider in providers {
        modelPreference.set(
          isUsingDefaultModel(provider) ? nil : configuredModel(for: provider),
          provider
        )
      }
      savedPreferences = settings
      savedModels = Dictionary(uniqueKeysWithValues: providers.map { ($0, configuredModel(for: $0)) })
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

  private func loadModels() {
    for provider in providers {
      if let model = modelPreference.current(provider) {
        usesDefaultModel[provider] = false
        customModelInputs[provider] = model
      } else {
        usesDefaultModel[provider] = true
      }
    }
    savedModels = Dictionary(uniqueKeysWithValues: providers.map { ($0, configuredModel(for: $0)) })
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
    captureToNotePreference = settings.captureToNotePreference
    readerFeedbackPreference = settings.readerFeedbackPreference
  }
}
