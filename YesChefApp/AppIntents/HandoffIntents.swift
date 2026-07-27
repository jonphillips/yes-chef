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
  static let description = IntentDescription("Export a Yes Chef context for an external assistant.")
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @Parameter(title: "Source", requestValueDialog: "What should Yes Chef hand off?")
  var source: HandoffSource

  // Defaults to `.immediate` because the Shortcuts surface exists for the headless
  // `Ask ChatGPT` chain; a discuss prompt sent headlessly comes back as prose the parser
  // cannot use. The in-app Copy Prompt button remains the discuss path.
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
  case recipeSection(Recipe.ID, PlaybookSectionKind)
  case recipeAdjustment(Recipe.ID)
  case menu(Menu.ID)
  case menuComplement(Menu.ID)
  case menuDay(Menu.ID, dayOffset: Int)
  case menuDayComplement(Menu.ID, dayOffset: Int)
  case mealPlan(MealPlanItem.ID)
  case mealPlanComplement(MealPlanItem.ID)
  case readerFeedback(ReaderFeedbackHandoffContext)
  case workbench(Workbench.ID, task: WorkbenchHandoffTask)

  init(_ source: HandoffSource) {
    switch source {
    case let .recipe(recipe): self = .recipeAdjustment(recipe.id)
    case let .menu(menu): self = .menu(menu.id)
    case let .mealPlan(mealPlan): self = .mealPlan(mealPlan.id)
    case let .workbench(workbench): self = .workbench(workbench.id, task: .compare)
    }
  }
}

extension HandoffExportSource {
  struct Metadata: Sendable {
    let sourceType: AIHandoffSourceType
    let sourceID: UUID
    let taskType: AIHandoffTaskType
    let dayOffset: Int?
  }

  func metadata(handoffID: AIHandoff.ID) -> Metadata {
    switch self {
    case let .recipeSection(recipeID, section):
      Metadata(sourceType: .recipe, sourceID: recipeID, taskType: section.handoffTaskType, dayOffset: nil)
    case let .recipeAdjustment(recipeID):
      Metadata(sourceType: .recipe, sourceID: recipeID, taskType: .adjustRecipe, dayOffset: nil)
    case let .menu(menuID):
      Metadata(sourceType: .menu, sourceID: menuID, taskType: .prepPlan, dayOffset: nil)
    case let .menuComplement(menuID):
      Metadata(sourceType: .menu, sourceID: menuID, taskType: .menuComplement, dayOffset: nil)
    case let .menuDay(menuID, dayOffset):
      Metadata(sourceType: .menu, sourceID: menuID, taskType: .prepPlan, dayOffset: dayOffset)
    case let .menuDayComplement(menuID, dayOffset):
      Metadata(sourceType: .menu, sourceID: menuID, taskType: .menuComplement, dayOffset: dayOffset)
    case let .mealPlan(mealPlanID):
      Metadata(sourceType: .mealPlan, sourceID: mealPlanID, taskType: .mealPlanMakeAheadStrategy, dayOffset: nil)
    case let .mealPlanComplement(mealPlanID):
      Metadata(sourceType: .mealPlan, sourceID: mealPlanID, taskType: .mealPlanComplement, dayOffset: nil)
    case .readerFeedback:
      Metadata(sourceType: .capture, sourceID: handoffID, taskType: .readerFeedbackCuration, dayOffset: nil)
    case let .workbench(workbenchID, task):
      Metadata(sourceType: .workbench, sourceID: workbenchID, taskType: task.handoffTaskType, dayOffset: nil)
    }
  }

  var unmatchedSubject: String {
    switch self {
    case .recipeSection: "recipe section"
    case .recipeAdjustment: "recipe"
    case .menu: "menu"
    case .menuComplement: "menu"
    case .menuDay: "menu day"
    case .menuDayComplement: "menu day"
    case .mealPlan: "meal-plan day"
    case .mealPlanComplement: "meal-plan day"
    case .readerFeedback: "reader feedback"
    case .workbench: "workbench"
    }
  }

  func matches(_ handoff: AIHandoff) -> Bool {
    switch self {
    case .readerFeedback:
      return handoff.sourceType == .capture
        && handoff.sourceID == handoff.id
        && handoff.taskType == .readerFeedbackCuration
    default:
      let metadata = metadata(handoffID: handoff.id)
      return handoff.matches(
        sourceType: metadata.sourceType,
        sourceID: metadata.sourceID,
        taskType: metadata.taskType,
        dayOffset: metadata.dayOffset
      )
    }
  }

  func applyingScope(to review: AIHandoffReview) -> AIHandoffReview {
    guard case let .menuDayComplement(_, dayOffset) = self,
      case let .menuComplement(complementReview) = review
    else { return review }

    let plan = MenuComplementPlan(items: complementReview.plan.items.map { suggestion in
      var suggestion = suggestion
      suggestion.dayOffset = dayOffset
      return suggestion
    })
    return .menuComplement(AIHandoffMenuComplementReview(
      handoffID: complementReview.handoffID,
      menuID: complementReview.menuID,
      plan: plan,
      unparsedBlocks: complementReview.unparsedBlocks
    ))
  }
}

enum WorkbenchHandoffTask: Sendable {
  case compare
  case experiments

  var handoffTaskType: AIHandoffTaskType {
    switch self {
    case .compare: .workbenchCompare
    case .experiments: .workbenchExperiments
    }
  }
}

enum HandoffAppOperations {
  private static func scopedMenuContext(
    detail: MenuDetailData,
    dayOffset: Int
  ) -> MenuChatContext {
    MenuChatContext(detail: detail).scoped(toDayOffset: dayOffset)
  }

  private static func menuDayPrepPlanHandoff(
    detail: MenuDetailData,
    dayOffset: Int,
    metadata: HandoffExportSource.Metadata,
    mode: AIHandoffToken.PromptMode,
    now: Date,
    handoffID: AIHandoff.ID
  ) -> AIHandoff {
    let context = scopedMenuContext(detail: detail, dayOffset: dayOffset)
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "\(metadata.taskType.title): \(detail.menu.title), Day \(dayOffset + 1)",
      context: "\(MenuDayHandoffScope.prepInstruction(dayOffset: dayOffset))\n\n\(context.prepPrompt())",
      mode: mode
    )
    return AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      dayOffset: metadata.dayOffset,
      createdAt: now,
      exportedPrompt: prompt
    )
  }

  private static func menuPrepPlanHandoff(
    detail: MenuDetailData,
    metadata: HandoffExportSource.Metadata,
    mode: AIHandoffToken.PromptMode,
    now: Date,
    handoffID: AIHandoff.ID
  ) -> AIHandoff {
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "\(metadata.taskType.title): \(detail.menu.title)",
      context: MenuChatContext(detail: detail).prepPrompt(),
      mode: mode
    )
    return AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      createdAt: now,
      exportedPrompt: prompt
    )
  }

  private static func menuComplementHandoff(
    detail: MenuDetailData,
    metadata: HandoffExportSource.Metadata,
    mode: AIHandoffToken.PromptMode,
    now: Date,
    handoffID: AIHandoff.ID
  ) -> AIHandoff {
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "\(metadata.taskType.title): \(detail.menu.title)",
      context: MenuHandoffContext(detail: detail).complementPrompt(),
      mode: mode,
      deliverableFormat: .menuComplement
    )
    return AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      createdAt: now,
      exportedPrompt: prompt
    )
  }

  private static func recipeSectionHandoff(
    detail: RecipeDetailData,
    section: PlaybookSectionKind,
    metadata: HandoffExportSource.Metadata,
    mode: AIHandoffToken.PromptMode,
    now: Date,
    handoffID: AIHandoff.ID
  ) -> AIHandoff {
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "\(metadata.taskType.title): \(detail.recipe.title)",
      context: RecipeHandoffContext(detail: detail).prompt(for: section),
      mode: mode,
      deliverableFormat: section.deliverableFormat
    )
    return AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      createdAt: now,
      exportedPrompt: prompt
    )
  }

  private static func recipeAdjustmentHandoff(
    detail: RecipeDetailData,
    metadata: HandoffExportSource.Metadata,
    mode: AIHandoffToken.PromptMode,
    now: Date,
    handoffID: AIHandoff.ID
  ) -> AIHandoff {
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "\(metadata.taskType.title): \(detail.recipe.title)",
      context: RecipeHandoffContext(detail: detail).prompt(forTask: .adjustRecipe),
      mode: mode
    )
    return AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      createdAt: now,
      exportedPrompt: prompt
    )
  }

  private static func menuDayComplementHandoff(
    detail: MenuDetailData,
    dayOffset: Int,
    metadata: HandoffExportSource.Metadata,
    mode: AIHandoffToken.PromptMode,
    now: Date,
    handoffID: AIHandoff.ID
  ) -> AIHandoff {
    let context = scopedMenuContext(detail: detail, dayOffset: dayOffset)
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "\(metadata.taskType.title): \(detail.menu.title), Day \(dayOffset + 1)",
      context: "\(MenuDayHandoffScope.complementInstruction(dayOffset: dayOffset))\n\n\(MenuHandoffContext(menu: context).complementPrompt())",
      mode: mode,
      deliverableFormat: .menuComplement
    )
    return AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      dayOffset: metadata.dayOffset,
      createdAt: now,
      exportedPrompt: prompt
    )
  }

  private static func mealPlanHandoffContext(
    mealPlanID: MealPlanItem.ID,
    in database: any DatabaseWriter
  ) async throws -> (MealPlanItem, MealPlanHandoffContext) {
    try await database.read { db in
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
  }

  private static func readerFeedbackHandoff(
    handoffID: AIHandoff.ID,
    metadata: HandoffExportSource.Metadata,
    context: ReaderFeedbackHandoffContext,
    mode: AIHandoffToken.PromptMode,
    now: Date
  ) -> AIHandoff {
    AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      dayOffset: metadata.dayOffset,
      createdAt: now,
      exportedPrompt: AIHandoffToken.prompt(
        handoffID: handoffID,
        title: metadata.taskType.title,
        context: context.prompt(),
        mode: mode,
        deliverableFormat: .readerFeedbackCuration
      )
    )
  }

  static func export(
    source: HandoffExportSource,
    mode: AIHandoffToken.PromptMode,
    in database: any DatabaseWriter,
    now: Date,
    handoffID: AIHandoff.ID
  ) async throws -> HandoffExport {
    let handoff: AIHandoff
    var externalProjectName: String? = nil
    let metadata = source.metadata(handoffID: handoffID)

    switch source {
    case let .menu(menuID):
      guard let detail = try await database.read({ db in
        try MenuDetailRequest(menuID: menuID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      handoff = menuPrepPlanHandoff(
        detail: detail,
        metadata: metadata,
        mode: mode,
        now: now,
        handoffID: handoffID
      )
      externalProjectName = detail.menu.externalProjectName

    case let .menuComplement(menuID):
      guard let detail = try await database.read({ db in
        try MenuDetailRequest(menuID: menuID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      handoff = menuComplementHandoff(
        detail: detail,
        metadata: metadata,
        mode: mode,
        now: now,
        handoffID: handoffID
      )
      externalProjectName = detail.menu.externalProjectName

    case let .menuDay(menuID, dayOffset):
      guard let detail = try await database.read({ db in
        try MenuDetailRequest(menuID: menuID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      handoff = menuDayPrepPlanHandoff(
        detail: detail,
        dayOffset: dayOffset,
        metadata: metadata,
        mode: mode,
        now: now,
        handoffID: handoffID
      )
      externalProjectName = detail.menu.externalProjectName

    case let .menuDayComplement(menuID, dayOffset):
      guard let detail = try await database.read({ db in
        try MenuDetailRequest(menuID: menuID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      handoff = menuDayComplementHandoff(
        detail: detail,
        dayOffset: dayOffset,
        metadata: metadata,
        mode: mode,
        now: now,
        handoffID: handoffID
      )
      externalProjectName = detail.menu.externalProjectName

    case let .recipeSection(recipeID, section):
      guard let detail = try await database.read({ db in
        try RecipeDetailRequest(recipeID: recipeID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      handoff = recipeSectionHandoff(
        detail: detail,
        section: section,
        metadata: metadata,
        mode: mode,
        now: now,
        handoffID: handoffID
      )

    case let .recipeAdjustment(recipeID):
      guard let detail = try await database.read({ db in
        try RecipeDetailRequest(recipeID: recipeID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      handoff = recipeAdjustmentHandoff(
        detail: detail,
        metadata: metadata,
        mode: mode,
        now: now,
        handoffID: handoffID
      )

    case let .mealPlan(mealPlanID):
      let context = try await mealPlanHandoffContext(mealPlanID: mealPlanID, in: database)
      let prompt = AIHandoffToken.prompt(
        handoffID: handoffID,
        title: "\(metadata.taskType.title): \(context.0.title)",
        context: context.1.makeAheadPrompt(),
        mode: mode,
        deliverableFormat: .mealPlanMakeAheadStrategy
      )
      handoff = AIHandoff(
        id: handoffID,
        sourceType: metadata.sourceType,
        sourceID: metadata.sourceID,
        taskType: metadata.taskType,
        createdAt: now,
        exportedPrompt: prompt
      )

    case let .mealPlanComplement(mealPlanID):
      let context = try await mealPlanHandoffContext(mealPlanID: mealPlanID, in: database)
      let prompt = AIHandoffToken.prompt(
        handoffID: handoffID,
        title: "\(metadata.taskType.title): \(context.0.title)",
        context: context.1.complementPrompt(),
        mode: mode,
        deliverableFormat: .mealPlanComplement
      )
      handoff = AIHandoff(
        id: handoffID,
        sourceType: metadata.sourceType,
        sourceID: metadata.sourceID,
        taskType: metadata.taskType,
        createdAt: now,
        exportedPrompt: prompt
      )

    case let .readerFeedback(context):
      handoff = readerFeedbackHandoff(handoffID: handoffID, metadata: metadata, context: context, mode: mode, now: now)

    case let .workbench(workbenchID, task):
      guard let workbenchContext = try await database.read({ db in
        try WorkbenchChatContextRequest(workbenchID: workbenchID).fetch(db)
      }) else {
        throw HandoffIntentSurfaceError.sourceNotFound
      }
      let context: String
      let deliverableFormat: AIHandoffToken.DeliverableFormat
      switch task {
      case .compare:
        context = workbenchContext.compareHandoffPrompt()
        deliverableFormat = .menuPrepPlan
      case .experiments:
        context = workbenchContext.experimentsHandoffPrompt()
        deliverableFormat = .workbenchExperiments
      }
      let prompt = AIHandoffToken.prompt(
        handoffID: handoffID,
        title: "\(metadata.taskType.title): \(workbenchContext.title)",
        context: context,
        mode: mode,
        deliverableFormat: deliverableFormat
      )
      handoff = AIHandoff(
        id: handoffID,
        sourceType: metadata.sourceType,
        sourceID: metadata.sourceID,
        taskType: metadata.taskType,
        createdAt: now,
        exportedPrompt: prompt
      )
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
    guard let result = AIHandoffReturnContract.strippingMarker(from: result) else {
      throw AIHandoffReturnContractError.instructionsOutOfDate
    }
    return try await database.write { db in
      try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: result,
        in: db,
        now: now
      )
    }
  }

  static func stageReviewForKnownSource(
    source: HandoffExportSource,
    result: String,
    in database: any DatabaseWriter,
    now: Date,
    handoffID: AIHandoff.ID
  ) async throws -> AIHandoffReview {
    guard let result = AIHandoffReturnContract.strippingMarker(from: result) else {
      throw AIHandoffReturnContractError.instructionsOutOfDate
    }
    let metadata = source.metadata(handoffID: handoffID)
    let handoff = AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      dayOffset: metadata.dayOffset,
      createdAt: now,
      exportedPrompt: ""
    )
    return try await database.write { db in
      try AIHandoffRepository.create(handoff, in: db)
      return try AIHandoffIntentImport.stageReview(
        handoffID: handoff.id,
        result: result,
        in: db,
        now: now
      )
    }
  }

  static func stageOnboardReview(
    source: HandoffExportSource,
    result: String,
    in database: any DatabaseWriter,
    now: Date,
    handoffID: AIHandoff.ID
  ) async throws -> AIHandoffReview {
    let metadata = source.metadata(handoffID: handoffID)
    let handoff = AIHandoff(
      id: handoffID,
      sourceType: metadata.sourceType,
      sourceID: metadata.sourceID,
      taskType: metadata.taskType,
      createdAt: now,
      exportedPrompt: ""
    )
    return try await database.read { db in
      try AIHandoffIntentImport.stageOnboardReview(
        handoff: handoff,
        result: result,
        in: db
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
