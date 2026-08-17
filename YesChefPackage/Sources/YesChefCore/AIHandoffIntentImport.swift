import Foundation
import SQLiteData

public extension AIHandoffIntentImport {
  /// Capture has no durable recipe target until the cook saves the draft. Its
  /// in-app transport stages tips back into that open editor.
  static func stageReaderFeedbackReview(
    handoffID: AIHandoff.ID,
    result: String,
    captureID: UUID,
    comments: [RawComment] = [],
    allowUnmatchedToken: Bool = false,
    in db: Database,
    now: Date
  ) throws -> AIHandoffReaderFeedbackResult {
    let markedResult = try AIHandoffReturnContract.strippingMarker(from: result)
    let payload: String
    if let routedText = AIHandoffToken.stripping(from: markedResult.text) {
      guard
        routedText.handoffID == handoffID || allowUnmatchedToken
      else {
        throw AIHandoffIntentImportError.wrongTask
      }
      payload = routedText.payload
    } else {
      // Reader-feedback curation is the one copied prompt whose deliverable is strict JSON.
      // Its capture-local transport can therefore accept the JSON directly after it has selected
      // this durable handoff by the prompt it just copied. Keep ordinary handoff returns on the
      // contract-marker route, and keep legacy `Tip:` returns there as well.
      guard
        ReaderFeedbackCurationClient.parseJSONReturn(
          markedResult.text,
          comments: ReaderFeedbackCurationClient.preparedComments(comments)
        ) != nil
      else { throw AIHandoffReturnContractError.instructionsOutOfDate }
      payload = markedResult.text
    }
    guard
      let handoff = try AIHandoffRepository.handoff(id: handoffID, in: db),
      handoff.sourceType == .capture,
      handoff.sourceID == captureID,
      handoff.taskType == .readerFeedbackCuration,
      handoff.status == .awaitingReturn,
      handoff.importedAt == nil
    else { throw AIHandoffIntentImportError.wrongTask }

    let returned = AIHandoffReturn.readerFeedbackReturn(from: payload, comments: comments)
    guard !returned.tips.isEmpty else {
      if !returned.unparsedLines.isEmpty {
        throw AIHandoffIntentImportError.unparsedReaderFeedbackLines(returned.unparsedLines)
      }
      throw AIHandoffIntentImportError.emptyPlan
    }
    try AIHandoffRepository.markImported(id: handoffID, at: now, in: db)
    return AIHandoffReaderFeedbackResult(
      review: AIHandoffReaderFeedbackReview(
        handoffID: handoffID,
        tips: returned.tips,
        unparsedLines: returned.unparsedLines
      ),
      warning: markedResult.warning
    )
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

  /// Stages a terminal response from an in-app discussion. The discussion has no exported
  /// handoff row or routing token, but its result must still flow through the same return parsers
  /// and review states as a pasted handoff.
  ///
  /// An onboard model may include the external contract marker because it learned the convention
  /// during a discussion. It is optional here: the app, rather than a copied external project,
  /// owns this transport.
  static func stageOnboardReview(
    handoff: AIHandoff,
    result: String,
    in db: Database
  ) throws -> AIHandoffReviewResult {
    let contract = try AIHandoffReturnContract.strippingMarker(from: result)
    let review = try AIHandoffReviewStager.stage(handoff: handoff, payload: contract.text, in: db)
    return AIHandoffReviewResult(review: review, warning: contract.warning)
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
      let currentPlan = MenuPrepPlan(steps: steps.map(PrepPlanStep.init))
      let returned = AIHandoffReturn.menuPrepPlan(from: payload, currentPlan: currentPlan)
      let baseline: MenuPrepPlan
      switch handoff.prepPlanIntent {
      case .refine:
        baseline = currentPlan
      case .regenerate:
        baseline = MenuPrepPlan()
      }
      let advisoryNotes = AIHandoffReturn.omittedCurrentPrepStepEvidence(
        proposedPlan: returned.plan,
        currentPlan: baseline
      ) + AIHandoffReturn.droppedSourceDishEvidence(
        proposedPlan: returned.plan,
        currentPlan: baseline
      )
      guard !returned.plan.steps.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      return .menuPrepPlan(AIHandoffMenuPrepPlanReview(
        handoffID: handoff.id, menuID: menu.id, plan: returned.plan,
        learnings: returned.learnings, unparsedPlanLines: returned.unparsedLines,
        advisoryNotes: advisoryNotes,
        prepPlanIntent: handoff.prepPlanIntent,
        replacementStepCount: currentPlan.steps.count
      ))
    case .menuComplement:
      let returned = AIHandoffReturn.menuComplement(from: payload, dayCount: menu.dayCount)
      guard !returned.plan.items.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .menuComplement(AIHandoffMenuComplementReview(
        handoffID: handoff.id, menuID: menu.id, plan: returned.plan, unparsedBlocks: returned.unparsedBlocks
      ))
    case .recipeMakeAhead, .chefItUp, .serveWith, .adjustRecipe, .mealPlanMakeAheadStrategy,
      .mealPlanComplement, .readerFeedbackCuration, .workbenchCompare, .workbenchExperiments,
      .workbenchDraft:
      throw AIHandoffIntentImportError.wrongTask
    }
  }

  private static func recipeReview(handoff: AIHandoff, payload: String, in db: Database) throws -> AIHandoffReview {
    guard let recipe = try Recipe.find(handoff.sourceID).fetchOne(db), !recipe.archived else {
      throw AIHandoffIntentImportError.wrongTask
    }
    let returned = AIHandoffReturn.plainText(from: payload)
    guard returned.unparsedLines.isEmpty else {
      throw AIHandoffIntentImportError.unparsedLearningLines(returned.unparsedLines)
    }
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
        text: returned.deliverable,
        currentServeWith: try RecipeServeWithRepository.serveWith(for: recipe.id, in: db).map(\.item),
        learnings: returned.learnings
      ))
    case .adjustRecipe:
      guard !returned.deliverable.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .recipeAdjustmentBrief(AIHandoffRecipeAdjustmentBriefReview(
        handoffID: handoff.id,
        recipeID: recipe.id,
        variationID: handoff.variationID,
        brief: returned.deliverable,
        learnings: returned.learnings
      ))
    case .prepPlan, .mealPlanMakeAheadStrategy, .mealPlanComplement, .menuComplement,
      .readerFeedbackCuration, .workbenchCompare, .workbenchExperiments, .workbenchDraft:
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
        strategy: parsed.strategy, learnings: returned.learnings,
        unparsedStrategyLines: parsed.unparsedLines + returned.unparsedLines
      ))
    case .mealPlanComplement:
      let returned = AIHandoffReturn.mealPlanComplement(from: payload)
      guard !returned.plan.items.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
      return .mealPlanComplement(AIHandoffMealPlanComplementReview(
        handoffID: handoff.id, mealPlanItemID: item.id, scheduledDate: item.scheduledDate,
        plan: returned.plan, unparsedBlocks: returned.unparsedBlocks
      ))
    case .prepPlan, .recipeMakeAhead, .chefItUp, .serveWith, .adjustRecipe, .menuComplement,
      .readerFeedbackCuration, .workbenchCompare, .workbenchExperiments, .workbenchDraft:
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
      guard returned.unparsedLines.isEmpty else {
        throw AIHandoffIntentImportError.unparsedLearningLines(returned.unparsedLines)
      }
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
    case .workbenchDraft:
      // Extraction, not synthesis (ADR-0042 Amd 2): the outboard's schema.org JSON-LD is parsed for
      // free by the deterministic extractor into the existing draft. A declined/empty draft degrades
      // to a loud `.emptyPlan` rather than promoting an empty recipe into review.
      let returned = AIHandoffReturn.workbenchDraft(from: payload, capturedAt: handoff.createdAt)
      // `fromJSONLD` returns nil only for the ADR declined case (no ingredients and no
      // instructions); a missing rationale is not a decline, so do not gate on `isEmpty` (which is
      // rationale-sensitive) — the review sheet fills an empty rationale.
      guard let draftRecipe = returned.draftRecipe else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      return .workbenchDraft(AIHandoffWorkbenchDraftReview(
        handoffID: handoff.id, workbenchID: handoff.sourceID,
        draftRecipe: draftRecipe, learnings: returned.learnings
      ))
    case .prepPlan, .learning, .recipeMakeAhead, .chefItUp, .serveWith, .adjustRecipe,
      .mealPlanMakeAheadStrategy, .mealPlanComplement, .menuComplement, .readerFeedbackCuration:
      throw AIHandoffIntentImportError.wrongTask
    }
  }
}
