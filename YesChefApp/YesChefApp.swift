import LLMClientKit
import SwiftUI
import WebExtractorKit
import YesChefCore

@main
struct YesChefApp: App {
  init() {
    let legacyPantryText = UserDefaults.standard.string(forKey: GroceryPantryStorage.storageKey)
    let legacyPantryItems = legacyPantryText.map(GroceryPantryStorage.items(from:))
    let legacyTasteProfile = UserDefaults.standard.string(forKey: legacyRecipeChatCustomInstructionsKey)
    prepareDependencies {
      try! $0.bootstrapDatabase()
      try! $0.migrateLegacyAISettingsIfNeeded(tasteProfile: legacyTasteProfile)
      try! $0.seedPantryItemsIfNeeded(titles: legacyPantryItems)
      try! $0.seedSampleDataIfNeeded()
      $0.webRecipeCaptureClient = WebRecipeCaptureClient(
        fetchHTML: WebRecipeCaptureClient.liveValue.fetchHTML,
        renderHTML: { url in
          await RenderedDOMFetcher.renderedHTML(of: url)
        },
        fetchImageData: WebRecipeCaptureClient.liveValue.fetchImageData
      )
      $0.modelClient = TieredModelClient.live(
        promptPreferences: YesChefAIPromptPreferences.modelPromptPreferences(for:)
      )
    }
    YesChefCloudSync.persistManualEnablementFromLaunchEnvironment()
    Task {
      _ = await YesChefCloudSync.startIfManuallyEnabled()
    }
    DatabaseChangeBeacon.startObserving()
  }

  var body: some Scene {
    WindowGroup {
      AppContainer()
    }
  }
}
