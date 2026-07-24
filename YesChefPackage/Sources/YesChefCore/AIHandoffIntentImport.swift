import Foundation
import SQLiteData

public extension AIHandoffIntentImport {
  /// Capture has no durable recipe target until the cook saves the draft. Its
  /// in-app transport stages tips back into that open editor.
  static func stageReaderFeedbackReview(
    handoffID: AIHandoff.ID,
    result: String,
    in db: Database,
    now: Date
  ) throws -> AIHandoffReaderFeedbackReview {
    guard let markedResult = AIHandoffReturnContract.strippingMarker(from: result) else {
      throw AIHandoffIntentImportError.instructionsOutOfDate
    }
    let routedText = AIHandoffToken.stripping(from: markedResult)
    guard let routedText, routedText.handoffID == handoffID,
      let handoff = try AIHandoffRepository.handoff(id: handoffID, in: db),
      handoff.sourceType == .capture,
      handoff.sourceID == handoffID,
      handoff.taskType == .readerFeedbackCuration,
      handoff.status == .awaitingReturn,
      handoff.importedAt == nil
    else { throw AIHandoffIntentImportError.wrongTask }

    let tips = AIHandoffReturn.readerFeedback(from: routedText.payload)
    guard !tips.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
    try AIHandoffRepository.markImported(id: handoffID, at: now, in: db)
    return AIHandoffReaderFeedbackReview(handoffID: handoffID, tips: tips)
  }

  static func stageMenuPrepPlanReview(
    handoffID: AIHandoff.ID?,
    result: String,
    in db: Database,
    now: Date
  ) throws -> AIHandoffMenuPrepPlanReview {
    guard case let .menuPrepPlan(review) = try stageReview(
      handoffID: handoffID,
      result: result,
      in: db,
      now: now
    ) else { throw AIHandoffIntentImportError.wrongTask }
    return review
  }

  static func stageReview(
    handoffID: AIHandoff.ID?,
    result: String,
    in db: Database,
    now: Date
  ) throws -> AIHandoffReview {
    let routedText = AIHandoffToken.stripping(from: result)
    guard let id = handoffID ?? routedText?.handoffID else {
      throw AIHandoffIntentImportError.missingHandoffID
    }
    guard let handoff = try AIHandoffRepository.handoff(id: id, in: db) else {
      throw AIHandoffIntentImportError.handoffNotFound(id)
    }
    guard handoff.status == .awaitingReturn, handoff.importedAt == nil else {
      throw AIHandoffIntentImportError.duplicate
    }
    let review = try AIHandoffReviewStager.stage(
      handoff: handoff,
      payload: routedText?.payload ?? result,
      in: db
    )
    try AIHandoffRepository.markImported(id: handoff.id, at: now, in: db)
    return review
  }
}

private enum AIHandoffReviewStager {
  static func stage(handoff: AIHandoff, payload: String, in db: Database) throws -> AIHandoffReview {
    switch handoff.sourceType {
    case .menu: try menuReview(handoff: handoff, payload: payload, in: db)
    case .recipe: try recipeReview(handoff: handoff, payload: payload, in: db)
    case .mealPlan: try mealPlanReview(handoff: handoff, payload: payload, in: db)
    case .workbench: try workbenchReview(handoff: handoff, payload: payload, in: db)
    case .capture: throw AIHandoffIntentImportError.wrongTask
    }
  }

  private static func menuReview(handoff: AIHandoff, payload: String, in db: Database) throws -> AIHandoffReview {
    guard let menu = try Menu.find(handoff.sourceID).fetchOne(db) else {
      throw AIHandoffIntentImportError.wrongTask
    }
    switch handoff.taskType {
    case .prepPlan, .learning:
      let steps = try PrepPlanStepRepository.steps(for: menu.id, in: db)
      let returned = AIHandoffReturn.menuPrepPlan(from: payload, currentPlan: MenuPrepPlan(steps: steps.map(PrepPlanStep.init)))
      guard !returned.plan.steps.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      return .menuPrepPlan(AIHandoffMenuPrepPlanReview(
        handoffID: handoff.id, menuID: menu.id, plan: returned.plan,
        learnings: returned.learnings, unparsedPlanLines: returned.unparsedLines
      ))
    case .menuComplement:
      let returned = AIHandoffReturn.menuComplement(from: payload, dayCount: menu.dayCount)
      guard returned.unparsedBlocks.isEmpty else {
        throw AIHandoffIntentImportError.unparsedPlanText(returned.unparsedBlocks)
      }
      guard !returned.plan.items.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .menuComplement(AIHandoffMenuComplementReview(
        handoffID: handoff.id, menuID: menu.id, plan: returned.plan, unparsedBlocks: []
      ))
    default:
      throw AIHandoffIntentImportError.wrongTask
    }
  }

  private static func recipeReview(handoff: AIHandoff, payload: String, in db: Database) throws -> AIHandoffReview {
    guard let recipe = try Recipe.find(handoff.sourceID).fetchOne(db), !recipe.archived else {
      throw AIHandoffIntentImportError.wrongTask
    }
    let returned = AIHandoffReturn.plainText(from: payload)
    guard !returned.deliverable.isEmpty || !returned.learnings.isEmpty else {
      throw AIHandoffIntentImportError.emptyPlan
    }
    switch handoff.taskType {
    case .recipeMakeAhead, .learning:
      return .recipeMakeAhead(AIHandoffRecipeMakeAheadReview(
        handoffID: handoff.id, recipeID: recipe.id, makeAhead: returned.deliverable,
        currentMakeAhead: recipe.makeAhead, learnings: returned.learnings
      ))
    case .chefItUp:
      return .recipeChefItUp(AIHandoffRecipeSectionReview(
        handoffID: handoff.id, recipeID: recipe.id, section: .chefItUp,
        text: returned.deliverable, currentText: recipe.chefItUp, learnings: returned.learnings
      ))
    case .serveWith:
      return .recipeServeWith(AIHandoffRecipeSectionReview(
        handoffID: handoff.id, recipeID: recipe.id, section: .serveWith,
        text: returned.deliverable, currentServeWith: ServeWithCoding.decode(recipe.serveWith),
        learnings: returned.learnings
      ))
    case .adjustRecipe:
      guard !returned.deliverable.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .recipeAdjustmentBrief(AIHandoffRecipeAdjustmentBriefReview(
        handoffID: handoff.id, recipeID: recipe.id, brief: returned.deliverable, learnings: returned.learnings
      ))
    default:
      throw AIHandoffIntentImportError.wrongTask
    }
  }

  private static func mealPlanReview(handoff: AIHandoff, payload: String, in db: Database) throws -> AIHandoffReview {
    guard let item = try MealPlanItem.find(handoff.sourceID).fetchOne(db) else {
      throw AIHandoffIntentImportError.wrongTask
    }
    switch handoff.taskType {
    case .mealPlanMakeAheadStrategy, .learning:
      let returned = AIHandoffReturn.plainText(from: payload)
      let parsed = MealPlanMakeAheadStrategy.parsingEditableReviewText(returned.deliverable)
      guard !parsed.strategy.steps.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      return .mealPlanMakeAhead(AIHandoffMealPlanMakeAheadReview(
        handoffID: handoff.id, mealPlanItemID: item.id, scheduledDate: item.scheduledDate,
        strategy: parsed.strategy, learnings: returned.learnings, unparsedStrategyLines: parsed.unparsedLines
      ))
    case .mealPlanComplement:
      let returned = AIHandoffReturn.mealPlanComplement(from: payload)
      guard returned.unparsedBlocks.isEmpty else {
        throw AIHandoffIntentImportError.unparsedPlanText(returned.unparsedBlocks)
      }
      guard !returned.plan.items.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .mealPlanComplement(AIHandoffMealPlanComplementReview(
        handoffID: handoff.id, mealPlanItemID: item.id, scheduledDate: item.scheduledDate,
        plan: returned.plan, unparsedBlocks: []
      ))
    default:
      throw AIHandoffIntentImportError.wrongTask
    }
  }

  private static func workbenchReview(handoff: AIHandoff, payload: String, in db: Database) throws -> AIHandoffReview {
    guard try Workbench.find(handoff.sourceID).fetchOne(db) != nil else {
      throw AIHandoffIntentImportError.wrongTask
    }
    switch handoff.taskType {
    case .workbenchCompare:
      let returned = AIHandoffReturn.plainText(from: payload)
      guard !returned.deliverable.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      return .workbenchCompare(AIHandoffWorkbenchCompareReview(
        handoffID: handoff.id, workbenchID: handoff.sourceID,
        comparison: returned.deliverable, learnings: returned.learnings
      ))
    case .workbenchExperiments:
      let returned = AIHandoffReturn.workbenchExperiments(from: payload)
      guard returned.unparsedBlocks.isEmpty else {
        throw AIHandoffIntentImportError.unparsedExperimentBlocks(returned.unparsedBlocks)
      }
      guard !returned.experiments.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .workbenchExperiments(AIHandoffWorkbenchExperimentsReview(
        handoffID: handoff.id, workbenchID: handoff.sourceID, experiments: returned.experiments
      ))
    default:
      throw AIHandoffIntentImportError.wrongTask
    }
  }
}
