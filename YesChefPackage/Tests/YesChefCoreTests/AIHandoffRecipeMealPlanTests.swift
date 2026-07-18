import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

extension AIHandoffTests {
  @Test
  func promptsUseTheSourceSpecificReviewFormat() {
    let recipePrompt = AIHandoffToken.prompt(
      handoffID: SampleUUIDSequence.uuid(38_035),
      context: "Recipe context",
      mode: .immediate,
      deliverableFormat: .recipeMakeAhead
    )
    let mealPlanPrompt = AIHandoffToken.prompt(
      handoffID: SampleUUIDSequence.uuid(38_036),
      context: "Meal-plan context",
      mode: .immediate,
      deliverableFormat: .mealPlanMakeAheadStrategy
    )

    #expect(recipePrompt.contains("completed recipe make-ahead notes"))
    #expect(recipePrompt.contains("Complete the sauce up to two days ahead"))
    #expect(mealPlanPrompt.contains("completed meal-plan make-ahead strategy"))
    #expect(mealPlanPrompt.contains("Two days ahead: Make the sauce."))
  }

  @Test
  func recipeContextOmitsCurrentMakeAheadWhenRegeneratingFresh() {
    let context = RecipeChatRecipeContext(
      title: "Chili",
      makeAhead: "Make the sauce two days ahead.",
      learnings: ["Salt the beans early."]
    )

    // Default (in-app chat) keeps current state so the assistant sees it.
    let refining = context.serialized()
    #expect(refining.contains("Current make-ahead section:"))
    #expect(refining.contains("Make the sauce two days ahead."))

    // A section hand-off regenerates fresh — no existing Playbook section can bias the response.
    let fresh = context.serialized(excludingPlaybookSections: Set(PlaybookSectionKind.allCases))
    #expect(!fresh.contains("Current make-ahead section:"))
    #expect(!fresh.contains("Make the sauce two days ahead."))
  }

  @Test
  func sectionHandoffPromptsAreScopedAndServeWithPinsItsEditableFormat() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(
      title: "Chili",
      makeAhead: "Current make-ahead note",
      chefItUp: "Current Chef It Up note",
      serveWith: [ServeWithItem(id: SampleUUIDSequence.uuid(38_041), title: "Current side")]
    ))

    let chefItUp = context.prompt(for: .chefItUp)
    let serveWith = context.prompt(for: .serveWith)

    #expect(chefItUp.contains("Chef It Up preferences:"))
    #expect(!chefItUp.contains("Current make-ahead note"))
    #expect(!chefItUp.contains("Current Chef It Up note"))
    #expect(!chefItUp.contains("Current side"))
    #expect(serveWith.contains("exactly as `title: note`"))
    #expect(serveWith.contains("Do not use bullets, Markdown emphasis, an introduction"))
  }

  @Test
  func mealPlanHandoffContextKeepsMethodsAndAllIngredients() {
    let recipeID = SampleUUIDSequence.uuid(38_037)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    let recipe = Recipe(id: recipeID, title: "Birria", dateCreated: now, dateModified: now)
    let row = MealPlanItemRowData(
      item: MealPlanItem(
        id: SampleUUIDSequence.uuid(38_038),
        kind: .recipe,
        recipeID: recipeID,
        title: recipe.title,
        scheduledDate: now,
        mealSlot: .dinner,
        sortOrder: 0,
        dateCreated: now,
        dateModified: now
      ),
      recipe: recipe,
      recipeIngredientLines: ["3 pounds beef chuck", "2 dried guajillo chiles"]
    )

    let serialized = MealPlanHandoffContext(
      title: "Tuesday, July 14",
      rows: [row],
      recipeMethodLinesByID: [recipeID: ["Toast the chiles.", "Braise the beef."]]
    )
    .serialized()

    #expect(serialized.contains("3 pounds beef chuck"))
    #expect(serialized.contains("2 dried guajillo chiles"))
    #expect(serialized.contains("Toast the chiles."))
    #expect(serialized.contains("Braise the beef."))
  }

  @Test
  func recipeHandoffStagesMakeAheadAndLearningsWithoutWritingTheRecipe() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(38_031)
    let handoffID = SampleUUIDSequence.uuid(38_032)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Birria", dateCreated: now, dateModified: now)
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .recipe,
          sourceID: recipeID,
          taskType: .recipeMakeAhead,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Make the chile sauce up to two days ahead and refrigerate it.
        YC-LEARNINGS:
        - Birria improves after resting overnight.
        """,
        in: db,
        now: now
      )

      guard case let .recipeMakeAhead(recipeReview) = review else {
        Issue.record("Expected a recipe make-ahead review.")
        return
      }
      expectNoDifference(recipeReview.recipeID, recipeID)
      expectNoDifference(
        recipeReview.makeAhead,
        "Make the chile sauce up to two days ahead and refrigerate it."
      )
      expectNoDifference(recipeReview.learnings, ["Birria improves after resting overnight."])
      #expect(try Recipe.find(recipeID).fetchOne(db)?.makeAhead == nil)
    }
  }

  @Test
  func chefItUpTokenCannotMatchOrStageAMakeAheadReview() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(38_042)
    let chefItUpHandoffID = SampleUUIDSequence.uuid(38_043)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Birria", dateCreated: now, dateModified: now)
      }
      .execute(db)
      let handoff = AIHandoff(
        id: chefItUpHandoffID,
        sourceType: .recipe,
        sourceID: recipeID,
        taskType: .chefItUp,
        createdAt: now,
        exportedPrompt: "YC-HANDOFF: \(chefItUpHandoffID.uuidString)"
      )
      try AIHandoffRepository.create(handoff, in: db)

      #expect(!handoff.matches(sourceType: .recipe, sourceID: recipeID, taskType: .recipeMakeAhead))
      #expect(handoff.matches(sourceType: .recipe, sourceID: recipeID, taskType: .chefItUp))

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: chefItUpHandoffID,
        result: """
        YC-HANDOFF: \(chefItUpHandoffID.uuidString)
        Bloom the chiles in oil before blending the sauce.
        """,
        in: db,
        now: now
      )

      guard case let .recipeChefItUp(sectionReview) = review else {
        Issue.record("A Chef It Up token must not stage a Make-ahead review.")
        return
      }
      expectNoDifference(sectionReview.section, .chefItUp)
      expectNoDifference(sectionReview.text, "Bloom the chiles in oil before blending the sauce.")
    }
  }

  @Test
  func mealPlanHandoffStagesStrategyAndReportsUnparsedLines() throws {
    @Dependency(\.defaultDatabase) var database
    let itemID = SampleUUIDSequence.uuid(38_033)
    let handoffID = SampleUUIDSequence.uuid(38_034)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try MealPlanItem.insert {
        MealPlanItem(
          id: itemID,
          kind: .note,
          title: "Birria night",
          scheduledDate: now,
          mealSlot: .dinner,
          sortOrder: 0,
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .mealPlan,
          sourceID: itemID,
          taskType: .mealPlanMakeAheadStrategy,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Make-ahead strategy - Dinner
        Two days ahead: Make the chile sauce.
        This sentence has no timing label.
        YC-LEARNINGS:
        - Birria improves after resting overnight.
        """,
        in: db,
        now: now
      )

      guard case let .mealPlanMakeAhead(mealPlanReview) = review else {
        Issue.record("Expected a meal-plan make-ahead review.")
        return
      }
      expectNoDifference(mealPlanReview.mealPlanItemID, itemID)
      expectNoDifference(
        mealPlanReview.strategy.steps,
        [MealPlanMakeAheadStep(when: "Two days ahead", task: "Make the chile sauce.")]
      )
      expectNoDifference(mealPlanReview.unparsedStrategyLines, ["This sentence has no timing label."])
      expectNoDifference(mealPlanReview.learnings, ["Birria improves after resting overnight."])
    }
  }
}
