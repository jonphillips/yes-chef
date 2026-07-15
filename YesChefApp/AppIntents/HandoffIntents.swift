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
    let handoff = try await HandoffAppOperations.export(
      source: HandoffExportSource(source),
      mode: mode.promptMode,
      in: database,
      now: now,
      handoffID: uuid()
    )
    return .result(
      value: handoff,
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

    let review = try await HandoffAppOperations.stageReview(
      handoffID: parsedHandoffID,
      result: result,
      in: database,
      now: now
    )
    await handoffReviewCoordinator.present(review)
    return .result(opensIntent: OpenHandoffReviewIntent(), dialog: "Review the returned handoff in Yes Chef.")
  }
}

struct HandoffAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ExportHandoffContext(),
      phrases: ["Export handoff context in \(.applicationName)"],
      shortTitle: "Export Handoff",
      systemImageName: "arrow.up.doc"
    )
    AppShortcut(
      intent: ImportHandoffResult(),
      phrases: ["Import handoff result in \(.applicationName)"],
      shortTitle: "Import Handoff",
      systemImageName: "arrow.down.doc"
    )
  }
}

enum HandoffExportSource: Sendable {
  case recipe(Recipe.ID)
  case menu(Menu.ID)
  case mealPlan(MealPlanItem.ID)

  init(_ source: HandoffSource) {
    switch source {
    case let .recipe(recipe): self = .recipe(recipe.id)
    case let .menu(menu): self = .menu(menu.id)
    case let .mealPlan(mealPlan): self = .mealPlan(mealPlan.id)
    }
  }
}

enum HandoffAppOperations {
  static func export(
    source: HandoffExportSource,
    mode: AIHandoffToken.PromptMode,
    in database: any DatabaseWriter,
    now: Date,
    handoffID: AIHandoff.ID
  ) async throws -> HandoffExport {
    let handoff: AIHandoff
    let externalProjectName: String?

    switch source {
    case let .menu(menuID):
      guard let detail = try await database.read({ db in
        try MenuDetailRequest(menuID: menuID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      let prompt = AIHandoffToken.prompt(
        handoffID: handoffID,
        context: MenuChatContext(detail: detail).prepPrompt(),
        mode: mode
      )
      handoff = AIHandoff(
        id: handoffID,
        sourceType: .menu,
        sourceID: detail.menu.id,
        taskType: .prepPlan,
        createdAt: now,
        exportedPrompt: prompt
      )
      externalProjectName = detail.menu.externalProjectName

    case let .recipe(recipeID):
      guard let detail = try await database.read({ db in
        try RecipeDetailRequest(recipeID: recipeID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      let prompt = AIHandoffToken.prompt(
        handoffID: handoffID,
        context: RecipeHandoffContext(detail: detail).makeAheadPrompt(),
        mode: mode,
        deliverableFormat: .recipeMakeAhead
      )
      handoff = AIHandoff(
        id: handoffID,
        sourceType: .recipe,
        sourceID: detail.recipe.id,
        taskType: .recipeMakeAhead,
        createdAt: now,
        exportedPrompt: prompt
      )
      externalProjectName = nil

    case let .mealPlan(mealPlanID):
      let context = try await database.read { db -> (MealPlanItem, MealPlanHandoffContext) in
        guard let item = try MealPlanItem.find(mealPlanID).fetchOne(db) else {
          throw HandoffIntentSurfaceError.sourceNotFound
        }
        let rows = try MealCalendarRequest().fetch(db)
          .filter { $0.item.scheduledDate == item.scheduledDate }
        var recipeMethodLinesByID: [Recipe.ID: [String]] = [:]
        for recipeID in Set(rows.compactMap { $0.recipe?.id }) {
          guard let detail = try RecipeRepository.fetchDetail(recipeID: recipeID, in: db) else { continue }
          recipeMethodLinesByID[recipeID] = detail.instructionSteps
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.text)
        }
        return (
          item,
          MealPlanHandoffContext(
            title: item.scheduledDate.formatted(date: .complete, time: .omitted),
            rows: rows,
            recipeMethodLinesByID: recipeMethodLinesByID
          )
        )
      }
      let prompt = AIHandoffToken.prompt(
        handoffID: handoffID,
        context: context.1.makeAheadPrompt(),
        mode: mode,
        deliverableFormat: .mealPlanMakeAheadStrategy
      )
      handoff = AIHandoff(
        id: handoffID,
        sourceType: .mealPlan,
        sourceID: context.0.id,
        taskType: .mealPlanMakeAheadStrategy,
        createdAt: now,
        exportedPrompt: prompt
      )
      externalProjectName = nil
    }

    try await database.write { db in
      try AIHandoffRepository.create(handoff, in: db)
    }
    return HandoffExport(
      id: handoff.id,
      prompt: handoff.exportedPrompt,
      externalProjectName: externalProjectName
    )
  }

  static func stageReview(
    handoffID: AIHandoff.ID?,
    result: String,
    in database: any DatabaseWriter,
    now: Date
  ) async throws -> AIHandoffReview {
    try await database.write { db in
      try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: result,
        in: db,
        now: now
      )
    }
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
  case sourceNotFound
  case invalidHandoffID

  var errorDescription: String? {
    switch self {
    case .sourceNotFound:
      "Yes Chef could not find that source."
    case .invalidHandoffID:
      "The handoff ID must be a UUID."
    }
  }
}
