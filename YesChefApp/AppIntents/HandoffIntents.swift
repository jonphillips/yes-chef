import AppIntents
import Dependencies
import Foundation
import SQLiteData
import YesChefCore

enum HandoffPromptMode: String, AppEnum {
  case discuss
  case immediate

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Handoff Mode"
  static let caseDisplayRepresentations: [HandoffPromptMode: DisplayRepresentation] = [
    .discuss: "Discuss",
    .immediate: "Immediate",
  ]

  var promptMode: AIHandoffToken.PromptMode {
    switch self {
    case .discuss: .discuss
    case .immediate: .immediate
    }
  }
}

struct ExportHandoffContext: AppIntent {
  static let title: LocalizedStringResource = "Export Handoff Context"
  static let description = IntentDescription("Export a menu context for an external assistant.")
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @Parameter(title: "Source", requestValueDialog: "What should Yes Chef hand off?")
  var source: HandoffSource

  // Defaults to `.immediate` because the Shortcuts surface exists for the headless
  // `Ask ChatGPT` chain; a discuss prompt sent headlessly comes back as prose the parser
  // cannot use. The in-app Copy Prep Prompt button remains the discuss path.
  @Parameter(title: "Mode", default: .immediate)
  var mode: HandoffPromptMode

  init() {}

  init(source: HandoffSource, mode: HandoffPromptMode = .immediate) {
    self.source = source
    self.mode = mode
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Export \(\.$mode) handoff context for \(\.$source)")
  }

  func perform() async throws -> some ReturnsValue<HandoffExport> & ProvidesDialog {
    let now = DependencyValues._current.date.now
    let database = DependencyValues._current.defaultDatabase
    let uuid = DependencyValues._current.uuid

    guard case let .menu(menu) = source else {
      throw HandoffIntentSurfaceError.sourceNotAvailableYet
    }
    guard let detail = try await database.read({ db in
      try MenuDetailRequest(menuID: menu.id).fetch(db)
    }) else {
      throw HandoffIntentSurfaceError.sourceNotFound
    }

    let handoffID = uuid()
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      context: MenuChatContext(detail: detail).prepPrompt(),
      mode: mode.promptMode
    )
    try await database.write { db in
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .menu,
          sourceID: detail.menu.id,
          taskType: .prepPlan,
          createdAt: now,
          exportedPrompt: prompt
        ),
        in: db
      )
    }
    return .result(
      value: HandoffExport(
        id: handoffID,
        prompt: prompt,
        externalProjectName: detail.menu.externalProjectName
      ),
      dialog: "Handoff context is ready."
    )
  }
}

struct ImportHandoffResult: AppIntent {
  static let title: LocalizedStringResource = "Import Handoff Result"
  static let description = IntentDescription("Open a returned external-assistant handoff for review.")
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @Parameter(title: "Handoff ID")
  var handoffID: String?

  @Parameter(title: "Result")
  var result: String

  init() {}

  init(handoffID: String? = nil, result: String) {
    self.handoffID = handoffID
    self.result = result
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Import \(\.$result)")
  }

  func perform() async throws -> some OpensIntent & ProvidesDialog {
    let now = DependencyValues._current.date.now
    let database = DependencyValues._current.defaultDatabase
    let handoffReviewCoordinator = DependencyValues._current.handoffReviewCoordinator

    let parsedHandoffID: UUID?
    if let handoffID {
      guard let value = UUID(uuidString: handoffID) else {
        throw HandoffIntentSurfaceError.invalidHandoffID
      }
      parsedHandoffID = value
    } else {
      parsedHandoffID = nil
    }

    let review = try await database.write { db in
      try AIHandoffIntentImport.stageMenuPrepPlanReview(
        handoffID: parsedHandoffID,
        result: result,
        in: db,
        now: now
      )
    }
    await handoffReviewCoordinator.present(review)
    return .result(opensIntent: OpenHandoffReviewIntent(), dialog: "Review the returned handoff in Yes Chef.")
  }
}

struct OpenHandoffReviewIntent: AppIntent {
  static let title: LocalizedStringResource = "Review Handoff Result"
  static var openAppWhenRun: Bool { true }
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  init() {}

  func perform() async throws -> some IntentResult {
    .result()
  }
}

private enum HandoffIntentSurfaceError: Error, LocalizedError {
  case sourceNotAvailableYet
  case sourceNotFound
  case invalidHandoffID

  var errorDescription: String? {
    switch self {
    case .sourceNotAvailableYet:
      "Recipe and meal-plan handoffs are not available until their serializers ship."
    case .sourceNotFound:
      "Yes Chef could not find that source."
    case .invalidHandoffID:
      "The handoff ID must be a UUID."
    }
  }
}
