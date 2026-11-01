import IssueReporting
import LLMClientKit
import SwiftUI
import WebExtractorKit
import YesChefCore

@main
struct YesChefApp: App {
  private let handoffReviewCoordinator: HandoffReviewCoordinator
  private let createRecipeCoordinator: CreateRecipeCoordinator
  private let syncActivityRecorder: SyncActivityRecorder
#if DEBUG
  private let modelCallRecordCollector: ModelCallRecordCollector
#endif

  init() {
    let handoffReviewCoordinator = HandoffReviewCoordinator()
    self.handoffReviewCoordinator = handoffReviewCoordinator
    let createRecipeCoordinator = CreateRecipeCoordinator()
    self.createRecipeCoordinator = createRecipeCoordinator
#if DEBUG
    let modelCallRecordCollector = ModelCallRecordCollector()
    self.modelCallRecordCollector = modelCallRecordCollector
#endif
    let legacyTasteProfile = UserDefaults.standard.string(forKey: legacyRecipeChatCustomInstructionsKey)
    prepareDependencies {
      try! $0.bootstrapDatabase()
      try! $0.migrateLegacyAISettingsIfNeeded(tasteProfile: legacyTasteProfile)
      try! $0.seedSampleDataIfNeeded()
      $0.handoffReviewCoordinator = handoffReviewCoordinator
      $0.createRecipeCoordinator = createRecipeCoordinator
      $0.webRecipeCaptureClient = WebRecipeCaptureClient(
        fetchHTML: WebRecipeCaptureClient.liveValue.fetchHTML,
        renderHTML: { url in
          await RenderedDOMFetcher.renderedHTML(of: url)
        },
        fetchImageData: WebRecipeCaptureClient.liveValue.fetchImageData
      )
      $0.modelClient = LoggingModelClient(
        wrapping: TieredModelClient.live(
          promptPreferences: YesChefAIPromptPreferences.modelPromptPreferences(for:),
          modelForProvider: YesChefAIPromptPreferences.model(for:)
        )
      )
#if DEBUG
      $0.modelCallRecordSink = .inMemory(modelCallRecordCollector)
      $0.modelCallRecordCollector = modelCallRecordCollector
#endif
    }
    let syncActivityRecorder = SyncActivityRecorder()
    self.syncActivityRecorder = syncActivityRecorder
    YesChefIssueReporter.install()
    YesChefCloudSync.persistManualEnablementFromLaunchEnvironment()
    Task {
      syncActivityRecorder.start()
      _ = await YesChefCloudSync.startIfManuallyEnabled()
    }
    DatabaseChangeBeacon.startObserving(
      appGroupIdentifier: try! YesChefDatabaseStorage.liveAppGroupIdentifier()
    )
  }

  var body: some Scene {
    WindowGroup {
      AppContainer()
        .environment(syncActivityRecorder)
    }
  }
}

final class YesChefIssueReporter: IssueReporter, @unchecked Sendable {
  private let onReport: (String, StaticString, UInt) -> Void

  init(onReport: @escaping (String, StaticString, UInt) -> Void = { message, fileID, line in
    AppLog.sync.error(
      "Issue: \(message, privacy: .public) at \(String(describing: fileID), privacy: .public):\(line, privacy: .public)"
    )
  }) {
    self.onReport = onReport
  }

  static func install(_ reporter: YesChefIssueReporter = YesChefIssueReporter()) {
    guard !IssueReporters.current.contains(where: { $0 is YesChefIssueReporter }) else { return }
    IssueReporters.current.append(reporter)
  }

  func reportIssue(
    _ message: @autoclosure () -> String?,
    severity: IssueSeverity,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt
  ) {
    guard let message = message() else { return }
    onReport(message, fileID, line)
  }
}
