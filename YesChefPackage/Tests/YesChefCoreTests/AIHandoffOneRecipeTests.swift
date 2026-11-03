import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension AIHandoffTests {
  @Test func oneRecipePromptContainsEveryDeliverableAndCurrentContext() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(
      title: "Soup", makeAhead: "Chill overnight."
    ))
    let prompt = context.prompt(forTask: .recipe)
    for label in ["YC-REVISION:", "YC-NEW-RECIPE:", "YC-MAKE-AHEAD:", "YC-CHEF-IT-UP:",
                  "YC-SERVE-WITH:", "YC-LEARNINGS:"] {
      #expect(prompt.contains(label))
    }
    #expect(prompt.contains("Chill overnight."))
    #expect(prompt.contains("currently"))
    for rule in ["on its own line first", "earliest to just before", "replace N",
                 "No headings", "no nested or Markdown bullets", "or `title` when no note is useful",
                 "Do not return a rewritten recipe, an ingredient list, JSON, IDs"] {
      #expect(prompt.contains(rule))
    }
  }

  @Test func oneRecipeRoutesLabelsAndAllowsAnotherReturn() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(39_100)
    let handoffID = SampleUUIDSequence.uuid(39_101)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      try AIHandoffRepository.create(.init(id: handoffID, sourceType: .recipe, sourceID: recipeID,
        taskType: .recipe, createdAt: now, exportedPrompt: ""), in: db)
      let cases: [(String, (AIHandoffReview) -> Bool)] = [
        ("YC-MAKE-AHEAD:\nTomorrow: Chill", { if case .recipeMakeAhead = $0 { true } else { false } }),
        ("YC-CHEF-IT-UP:\nBrown butter", { if case .recipeChefItUp = $0 { true } else { false } }),
        ("YC-SERVE-WITH:\nBread: Toasted", { if case .recipeServeWith = $0 { true } else { false } }),
        ("YC-REVISION:\nBrown the butter", { if case .recipeAdjustmentBrief = $0 { true } else { false } }),
        ("YC-LEARNINGS:\n- No garlic", {
          if case let .recipeMakeAhead(review) = $0 { review.learnings == ["No garlic"] } else { false }
        }),
        ("Unlabeled text", { if case .recipeUnfiled = $0 { true } else { false } }),
        ("YC-FUTURE:\nKeep this", { if case .recipeUnfiled = $0 { true } else { false } }),
      ]
      for (body, matches) in cases {
        let result = try AIHandoffIntentImport.stageReview(handoffID: handoffID, result: body, in: db, now: now)
        guard case let .recipeItems(_, items) = result, let first = items.first else {
          Issue.record("Expected recipe items for \(body)"); continue
        }
        #expect(matches(first))
      }
      let combined = try AIHandoffIntentImport.stageReview(handoffID: handoffID,
        result: "YC-REVISION:\nRevise\nYC-MAKE-AHEAD:\nTomorrow: Chill\nYC-CHEF-IT-UP:\nBrown butter", in: db,
        now: now.addingTimeInterval(20))
      guard case let .recipeItems(_, items) = combined else { Issue.record("Expected items"); return }
      #expect(items.count == 3)
      if case .recipeAdjustmentBrief = items.last {} else { Issue.record("Revision should be last") }
      expectNoDifference(try AIHandoffRepository.handoff(id: handoffID, in: db)?.importedAt, now)
    }
  }

  @Test func newRecipeAndLegacyAdjustmentRouteThroughCore() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(39_110)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    let json = """
    {"@context":"https://schema.org","@type":"Recipe","name":"Cabbage","recipeIngredient":["1 cabbage"],"recipeInstructions":[{"@type":"HowToStep","text":"Char the cabbage."}]}
    """
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      for (index, task) in [AIHandoffTaskType.recipe, .adjustRecipe].enumerated() {
        let id = SampleUUIDSequence.uuid(39_111 + index)
        try AIHandoffRepository.create(.init(id: id, sourceType: .recipe, sourceID: recipeID,
          taskType: task, createdAt: now, exportedPrompt: ""), in: db)
        let body = task == .recipe ? "YC-NEW-RECIPE:\n\(json)" : json
        let review = try AIHandoffIntentImport.stageReview(handoffID: id, result: body, in: db, now: now)
        guard case .recipeNew = review else { Issue.record("Expected new recipe"); continue }
        #expect(try AIHandoffRepository.handoff(id: id, in: db)?.importedAt == now)
      }
      let id = SampleUUIDSequence.uuid(39_113)
      try AIHandoffRepository.create(.init(id: id, sourceType: .recipe, sourceID: recipeID,
        taskType: .recipe, createdAt: now, exportedPrompt: ""), in: db)
      #expect(throws: (any Error).self) {
        try AIHandoffIntentImport.stageReview(handoffID: id,
          result: "YC-NEW-RECIPE:\n\(json)\nYC-MAKE-AHEAD:\nChill", in: db, now: now)
      }
    }
  }

  @Test func onlyRecipeAcceptsRepeatReturns() {
    let others: [AIHandoffTaskType] = [.prepPlan, .learning, .recipeMakeAhead, .chefItUp, .serveWith,
      .adjustRecipe, .mealPlanMakeAheadStrategy, .mealPlanComplement, .menuComplement, .readerFeedbackCuration,
      .workbenchCompare, .workbenchExperiments, .workbenchDraft]
    #expect(AIHandoffTaskType.recipe.acceptsRepeatReturns)
    #expect(others.allSatisfy { !$0.acceptsRepeatReturns })
  }
  @Test func emptyLabelsAndInvalidNewRecipesAreRejectedWithoutConsumingTheHandoff() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(39_200)
    let id = SampleUUIDSequence.uuid(39_201)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      try AIHandoffRepository.create(.init(id: id, sourceType: .recipe, sourceID: recipeID,
        taskType: .recipe, createdAt: now, exportedPrompt: ""), in: db)
      for body in ["YC-MAKE-AHEAD:", "YC-LEARNINGS:", "YC-LEARNINGS:\n- "] {
        #expect(throws: AIHandoffIntentImportError.emptyPlan) {
          try AIHandoffIntentImport.stageReview(handoffID: id, result: body, in: db, now: now)
        }
      }
      #expect(throws: AIHandoffIntentImportError.invalidNewRecipe) {
        try AIHandoffIntentImport.stageReview(handoffID: id, result: "YC-NEW-RECIPE:\nnot JSON", in: db, now: now)
      }
      #expect(throws: AIHandoffIntentImportError.newRecipeMustStandAlone) {
        try AIHandoffIntentImport.stageReview(handoffID: id,
          result: "Preamble\nYC-NEW-RECIPE:\n{}", in: db, now: now)
      }
      #expect(try AIHandoffRepository.handoff(id: id, in: db)?.importedAt == nil)
    }
  }

}
