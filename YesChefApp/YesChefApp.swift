import LLMClientKit
import SwiftUI
import WebExtractorKit
import YesChefCore

@main
struct YesChefApp: App {
  private let handoffReviewCoordinator: HandoffReviewCoordinator
#if DEBUG
  private let modelCallRecordCollector: ModelCallRecordCollector
#endif

  init() {
    let handoffReviewCoordinator = HandoffReviewCoordinator()
    self.handoffReviewCoordinator = handoffReviewCoordinator
#if DEBUG
    let modelCallRecordCollector = ModelCallRecordCollector()
    self.modelCallRecordCollector = modelCallRecordCollector
#endif
    let legacyPantryText = UserDefaults.standard.string(forKey: GroceryPantryStorage.storageKey)
    let legacyPantryItems = legacyPantryText.map(GroceryPantryStorage.items(from:))
    let legacyTasteProfile = UserDefaults.standard.string(forKey: legacyRecipeChatCustomInstructionsKey)
    prepareDependencies {
      try! $0.bootstrapDatabase()
      try! $0.migrateLegacyAISettingsIfNeeded(tasteProfile: legacyTasteProfile)
      try! $0.seedPantryItemsIfNeeded(titles: legacyPantryItems)
      try! $0.seedSampleDataIfNeeded()
      $0.handoffReviewCoordinator = handoffReviewCoordinator
      $0.webRecipeCaptureClient = WebRecipeCaptureClient(
        fetchHTML: WebRecipeCaptureClient.liveValue.fetchHTML,
        renderHTML: { url in
          await RenderedDOMFetcher.renderedHTML(of: url)
        },
        fetchImageData: WebRecipeCaptureClient.liveValue.fetchImageData
      )
      $0.modelClient = LoggingModelClient(
        wrapping: TieredModelClient.live(
          promptPreferences: YesChefAIPromptPreferences.modelPromptPreferences(for:)
        )
      )
#if DEBUG
      $0.modelCallRecordSink = .inMemory(modelCallRecordCollector)
      $0.modelCallRecordCollector = modelCallRecordCollector
#endif
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
