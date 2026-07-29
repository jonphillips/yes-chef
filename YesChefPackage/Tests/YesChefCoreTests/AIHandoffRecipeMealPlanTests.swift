import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import LLMClientKit
import Synchronization
import Testing
import YesChefCore

extension AIHandoffTests {
  @Test
  func onboardRecipeReturnUsesTheSharedHandoffReviewParserWithoutAnExportedHandoff() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(38_020)
    let reviewID = SampleUUIDSequence.uuid(38_021)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Brown Butter Cookies", dateCreated: now, dateModified: now)
      }
      .execute(db)
    }

    let review = try database.read { db in
      try AIHandoffIntentImport.stageOnboardReview(
        handoff: AIHandoff(
          id: reviewID,
          sourceType: .recipe,
          sourceID: recipeID,
          taskType: .recipeMakeAhead,
          createdAt: now,
          exportedPrompt: ""
        ),
        result: """
        Mix and chill the dough the day before baking.
        YC-LEARNINGS:
        - Browned butter benefits from a short cool-down before it meets the sugar.
        """,
        in: db
      )
    }

    guard case let .recipeMakeAhead(onboardReview) = review else {
      Issue.record("Expected an onboard recipe make-ahead review.")
      return
    }
    expectNoDifference(onboardReview.handoffID, reviewID)
    expectNoDifference(onboardReview.recipeID, recipeID)
    expectNoDifference(onboardReview.makeAhead, "Mix and chill the dough the day before baking.")
    expectNoDifference(
      onboardReview.learnings,
      ["Browned butter benefits from a short cool-down before it meets the sugar."]
    )
  }

  @Test
  func recipeAdjustmentPromptUsesTheHandValidatedBriefShapeAndKeepsWholeRecipeContext() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(
      title: "Brown Butter Cookies",
      makeAhead: "Chill the dough overnight.",
      learnings: ["Do not add bacon to this cookie."]
    ))

    let prompt = context.prompt(forTask: .adjustRecipe)

    #expect(prompt.contains("Discuss it freely: argue, push back, ask"))
    #expect(prompt.contains("Take the butter to 120g and brown it before creaming"))
    #expect(prompt.contains("Move the salt into the flour instead of the wet mix"))
    #expect(prompt.contains("Rest the dough 20 minutes before shaping"))
    #expect(prompt.contains("Do not return a rewritten recipe, an ingredient list, JSON, IDs"))
    #expect(prompt.contains("considered and rejected"))
    #expect(prompt.contains("Current make-ahead section:"))
    #expect(prompt.contains("Chill the dough overnight."))
    #expect(prompt.contains("Do not add bacon to this cookie."))
  }

  @Test
  func recipeAdjustmentHandoffStagesAProseBriefAndLearningsWithoutWritingTheRecipe() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(38_030)
    let handoffID = SampleUUIDSequence.uuid(38_031)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Brown Butter Cookies", dateCreated: now, dateModified: now)
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .recipe,
          sourceID: recipeID,
          taskType: .adjustRecipe,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Take the butter to 120g and brown it before creaming — more nutty depth, less spread.
        YC-LEARNINGS:
        - Bacon was considered and rejected because it would overpower the cookie.
        """,
        in: db,
        now: now
      )

      guard case let .recipeAdjustmentBrief(briefReview) = review else {
        Issue.record("Expected a recipe-adjustment brief review.")
        return
      }
      expectNoDifference(briefReview.recipeID, recipeID)
      expectNoDifference(
        briefReview.brief,
        "Take the butter to 120g and brown it before creaming — more nutty depth, less spread."
      )
      expectNoDifference(
        briefReview.learnings,
        ["Bacon was considered and rejected because it would overpower the cookie."]
      )
      expectNoDifference(try Recipe.find(recipeID).fetchOne(db)?.title, "Brown Butter Cookies")
    }
  }

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
    #expect(mealPlanPrompt.contains("completed meal-plan make-ahead strategy"))
    #expect(!recipePrompt.contains(AIHandoffReturnContract.marker))
    #expect(!mealPlanPrompt.contains(AIHandoffReturnContract.marker))
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

    // A section hand-off regenerates fresh — its existing content must not bias the next return.
    let fresh = context.serialized(excludingPlaybookSections: [.makeAhead])
    #expect(!fresh.contains("Current make-ahead section:"))
    #expect(!fresh.contains("Make the sauce two days ahead."))
  }

  @Test
  func sectionHandoffPromptsExcludeOnlyTheSectionBeingRegenerated() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(
      title: "Chili",
      makeAhead: "Current make-ahead note",
      chefItUp: "Current Chef It Up note",
      serveWith: [ServeWithItem(id: SampleUUIDSequence.uuid(38_041), title: "Current side")]
    ))

    let makeAhead = context.prompt(for: .makeAhead)
    let chefItUp = context.prompt(for: .chefItUp)
    let serveWith = context.prompt(for: .serveWith)

    #expect(!makeAhead.contains("Current make-ahead note"))
    #expect(makeAhead.contains("Current Chef It Up note"))
    #expect(makeAhead.contains("Current side"))
    #expect(chefItUp.contains("Chef It Up preferences:"))
    #expect(chefItUp.contains("Current make-ahead note"))
    #expect(!chefItUp.contains("Current Chef It Up note"))
    #expect(chefItUp.contains("Current side"))
    #expect(serveWith.contains("Current make-ahead note"))
    #expect(serveWith.contains("Current Chef It Up note"))
    #expect(!serveWith.contains("Current side"))
    #expect(serveWith.contains("exactly as `title: note`"))
    #expect(serveWith.contains("Do not use bullets, Markdown emphasis, an introduction"))
  }

  @Test
  func sectionDiscussAskSharesTheExternalDiscussionOpeningWithoutItsToken() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(title: "Chili"))

    let ask = context.discussAsk(for: .chefItUp)
    let outboardAsk = AIHandoffToken.discussAsk(
      context: context.prompt(for: .chefItUp),
      deliverableFormat: .recipeChefItUp
    )
    let exported = AIHandoffToken.prompt(
      handoffID: SampleUUIDSequence.uuid(38_042),
      context: context.prompt(for: .chefItUp),
      deliverableFormat: .recipeChefItUp
    )

    #expect(ask.contains("You are preparing practical Chef It Up notes for one recipe."))
    #expect(ask.contains("When the user asks you to finalize, return the paste-ready Chef It Up notes."))
    #expect(ask.contains("The format above describes the finalized return"))
    #expect(!ask.contains(AIHandoffToken.prefix))
    #expect(!outboardAsk.contains("The format above describes the finalized return"))
    #expect(exported.hasSuffix(outboardAsk))
  }

  @Test
  func menuDiscussAskSharesTheExternalDiscussionOpeningWithoutItsToken() {
    let context = MenuChatContext(title: "Beach Menu", dayCount: 2)

    let ask = context.discussAsk()
    let outboardAsk = AIHandoffToken.discussAsk(context: context.prepPrompt())
    let exported = AIHandoffToken.prompt(
      handoffID: SampleUUIDSequence.uuid(38_043),
      context: context.prepPrompt()
    )

    #expect(ask.contains("You weave a staged prep plan for one multi-day menu"))
    #expect(ask.contains("When the user asks you to finalize, return the paste-ready prep plan."))
    #expect(ask.contains("The format above describes the finalized return"))
    #expect(!ask.contains(AIHandoffToken.prefix))
    #expect(!outboardAsk.contains("The format above describes the finalized return"))
    #expect(exported.hasSuffix(outboardAsk))
  }

  @Test
  func menuContextCanScopeAHandOffToOneDayWithoutLeakingOtherDishes() {
    let context = MenuChatContext(
      title: "Weekend Menu",
      dayCount: 2,
      items: [
        MenuChatItemContext(
          id: SampleUUIDSequence.uuid(38_044),
          title: "Friday Pizza",
          kind: .recipe,
          dayOffset: 0,
          mealSlot: .dinner,
          sortOrder: 0
        ),
        MenuChatItemContext(
          id: SampleUUIDSequence.uuid(38_045),
          title: "Saturday Soup",
          kind: .recipe,
          dayOffset: 1,
          mealSlot: .dinner,
          sortOrder: 0
        ),
      ]
    )

    let scoped = context.scoped(toDayOffset: 1)
    let prompt = MenuHandoffContext(menu: scoped).complementPrompt()

    #expect(prompt.contains("Saturday Soup"))
    #expect(!prompt.contains("Friday Pizza"))
  }

  @Test
  func dayScopedPrepPromptKeepsTheWholeCurrentPlanWhileScopingDishes() {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12))!
    let dayTwoDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
    let context = MenuChatContext(
      title: "Weekend Menu",
      dayCount: 2,
      placementStartDate: startDate,
      prepPlan: [
        PrepPlanStepRecord(
          id: SampleUUIDSequence.uuid(38_046), menuID: SampleUUIDSequence.uuid(38_047), sortOrder: 0,
          session: "Friday", task: "Salt the pizza dough"
        ),
        PrepPlanStepRecord(
          id: SampleUUIDSequence.uuid(38_048), menuID: SampleUUIDSequence.uuid(38_047), sortOrder: 1,
          session: "Saturday", task: "Soak the beans"
        ),
      ],
      items: [
        MenuChatItemContext(
          id: SampleUUIDSequence.uuid(38_049), title: "Friday Pizza", kind: .recipe, dayOffset: 0,
          mealSlot: .dinner, sortOrder: 0
        ),
        MenuChatItemContext(
          id: SampleUUIDSequence.uuid(38_050), title: "Saturday Soup", kind: .recipe, dayOffset: 1,
          mealSlot: .dinner, sortOrder: 0
        ),
      ]
    )

    let scoped = context.scoped(toDayOffset: 1)
    let instruction = MenuDayHandoffScope.prepInstruction(
      dayOffset: 1,
      placementStartDate: scoped.placementStartDate
    )
    let prompt = "\(instruction)\n\n\(scoped.prepPrompt())"

    #expect(scoped.dayCount == 1)
    #expect(scoped.items.map(\.title) == ["Saturday Soup"])
    #expect(scoped.prepPlan.map(\.task) == ["Salt the pizza dough", "Soak the beans"])
    #expect(prompt.contains("Salt the pizza dough"))
    #expect(prompt.contains("preserve every existing step for other days verbatim and in place"))
    #expect(prompt.contains("Day 2 (\(dayTwoDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))"))
  }

  @Test
  func dayScopedPrepAndComplementInstructionsHaveDifferentHorizonRules() {
    let prep = MenuDayHandoffScope.prepInstruction(dayOffset: 0)
    let complement = MenuDayHandoffScope.complementInstruction(dayOffset: 0)

    #expect(!prep.contains("do not plan for another day"))
    #expect(complement.contains("do not plan for another day"))
  }

  @Test
  func onboardSectionPromptsLeaveTheRecipeToTheChatSystemPromptAndKeepLearnings() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(
      title: "Cumin Chili",
      makeAhead: "Salt the beans overnight.",
      chefItUp: "Toast the cumin.",
      serveWith: [ServeWithItem(id: SampleUUIDSequence.uuid(38_044), title: "Cornbread")],
      learnings: ["Keep the heat modest for the children."]
    ))

    for section in PlaybookSectionKind.allCases {
      let outboard = context.prompt(for: section)
      let onboard = context.prompt(for: section, destination: .onboard)

      #expect(!onboard.contains("Cumin Chili"))
      #expect(onboard.contains("Keep the heat modest for the children."))
      #expect(outboard.contains(onboard.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
  }

  @Test
  func onboardMenuPromptLeavesOutTransportAndMenuContext() {
    let context = MenuChatContext(title: "Beach Menu", dayCount: 2)
    let outboard = context.prepPrompt()
    let onboard = context.prepPrompt(destination: .onboard)

    #expect(outboard.contains("This text will be pasted back into the recipe app"))
    #expect(!onboard.contains("This text will be pasted back into the recipe app"))
    #expect(!onboard.contains("Beach Menu"))
    #expect(outboard.contains(onboard.trimmingCharacters(in: .whitespacesAndNewlines)))
  }

  @Test
  @MainActor
  func seedIfColdSeedsOnlyNewThreadsAndLeavesWarmThreadsAlone() async {
    let recipeID = SampleUUIDSequence.uuid(38_045)
    await withDependencies {
      $0.date.now = Date(timeIntervalSinceReferenceDate: 840_000_000)
      $0.uuid = .incrementing
      $0.modelClient = StubModelClient.constant("Start with the sauce.")
    } operation: {
      let cold = RecipeChatModel(
        context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
      )
      #expect(
        await cold.seedIfCold(
          "Open the make-ahead discussion.",
          summary: "Started Make-ahead discussion."
        ) == .seeded
      )
      #expect(cold.messages.map(\.text) == ["Open the make-ahead discussion.", "Start with the sauce."])
      #expect(cold.seedSummary(for: cold.messages[0].id) == "Started Make-ahead discussion.")

      let warm = RecipeChatModel(
        context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
      )
      let existingMessages = warm.messages
      // A warm thread reports `.alreadyWarm`, never `.failed` — the caller keeps the panel's scope.
      #expect(await warm.seedIfCold("Do not send this second opener.") == .alreadyWarm)
      expectNoDifference(warm.messages, existingMessages)
      #expect(warm.seedSummary(for: warm.messages[0].id) == nil)
    }
  }

  @Test
  @MainActor
  func seedSummaryDoesNotReplaceTheSeedTextInModelHistory() async {
    let recordedMessages = Mutex<[[ModelMessage]]>([])

    await withDependencies {
      $0.uuid = .incrementing
      $0.modelClient = StubModelClient { request in
        recordedMessages.withLock { $0.append(request.messages) }
        return ModelResponse(text: "Start with the sauce.")
      }
    } operation: {
      let model = RecipeChatModel(
        context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
      )
      await model.seedIfCold(
        "Open the full make-ahead discussion.",
        summary: "Started Make-ahead discussion."
      )
      await model.send("What should I do first?")

      let latest = recordedMessages.withLock { $0.last ?? [] }
      #expect(latest.map(\.text) == [
        "Open the full make-ahead discussion.",
        "Start with the sauce.",
        "What should I do first?",
      ])
    }
  }

  @Test
  @MainActor
  func failedColdSeedDoesNotLeaveAnOrphanedUserMessage() async {
    await withDependencies {
      $0.uuid = .incrementing
      $0.modelClient = StubModelClient { _ in throw SeedFailure.unavailable }
    } operation: {
      let model = RecipeChatModel(
        context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
      )
      #expect(await model.seedIfCold("Open the make-ahead discussion.") == .failed)
      expectNoDifference(model.messages, [])
      #expect(model.errorText != nil)
    }
  }

  /// The Playbook hands off in `.discuss` mode, and each context owns its format. Chef It Up stays a flat
  /// line list; make-ahead carries the shared timing vocabulary so it matches the onboard extractor and the
  /// stored `Recipe.makeAhead` field instead of drifting back into a generic headed report.
  @Test
  func blobSectionPromptsPinTheirReturnFormat() {
    let context = RecipeHandoffContext(recipe: RecipeChatRecipeContext(title: "Chili"))

    let chefItUp = context.prompt(for: .chefItUp)
    #expect(chefItUp.contains("one upgrade per line"))
    #expect(chefItUp.contains("No headings, no section titles, no nested or Markdown bullets"))
    #expect(chefItUp.contains("no assessment of what the recipe already does well"))
    #expect(chefItUp.contains("Six lines at most"))

    let makeAhead = context.prompt(for: .makeAhead)
    #expect(makeAhead.contains("one make-ahead step per line as `When: task`"))
    #expect(makeAhead.contains(MakeAheadTiming.canonicalLabelList))
    #expect(makeAhead.contains("no assessment of what the recipe already does well"))
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
        Recipe(
          id: recipeID,
          title: "Birria",
          dateCreated: now,
          dateModified: now,
          makeAhead: "Salt the beef the day before."
        )
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
      expectNoDifference(recipeReview.currentMakeAhead, "Salt the beef the day before.")
      expectNoDifference(recipeReview.learnings, ["Birria improves after resting overnight."])
      expectNoDifference(
        try Recipe.find(recipeID).fetchOne(db)?.makeAhead,
        "Salt the beef the day before."
      )
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
        Recipe(
          id: recipeID,
          title: "Birria",
          dateCreated: now,
          dateModified: now,
          chefItUp: "Finish with fresh lime."
        )
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
      expectNoDifference(sectionReview.currentText, "Finish with fresh lime.")
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

  @Test
  func workbenchComparisonStagesProseForHumanReviewWithoutWritingTheLog() throws {
    @Dependency(\.defaultDatabase) var database
    let workbenchID = SampleUUIDSequence.uuid(38_004)
    let handoffID = SampleUUIDSequence.uuid(38_005)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Workbench.insert {
        Workbench(
          id: workbenchID,
          title: "Cookie Study",
          sortOrder: 0,
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .workbench,
          sourceID: workbenchID,
          taskType: .workbenchCompare,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Hydration: Candidate B uses more water, which should leave a more open crumb.
        YC-LEARNINGS:
        - Higher hydration needs gentler handling.
        """,
        in: db,
        now: now
      )

      guard case let .workbenchCompare(compare) = review else {
        Issue.record("Expected a workbench comparison review.")
        return
      }
      expectNoDifference(compare.workbenchID, workbenchID)
      expectNoDifference(
        compare.comparison,
        "Hydration: Candidate B uses more water, which should leave a more open crumb."
      )
      expectNoDifference(compare.learnings, ["Higher hydration needs gentler handling."])
      #expect(try WorkbenchLogEntry.fetchAll(db).isEmpty)
    }
  }

  @Test
  func workbenchExperimentsParseRunTogetherBlocksAndIgnoreLearnings() throws {
    @Dependency(\.defaultDatabase) var database
    let workbenchID = SampleUUIDSequence.uuid(38_006)
    let handoffID = SampleUUIDSequence.uuid(38_007)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Workbench.insert {
        Workbench(
          id: workbenchID,
          title: "Cookie Study",
          sortOrder: 0,
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .workbench,
          sourceID: workbenchID,
          taskType: .workbenchExperiments,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Hypothesis: Resting the dough overnight will deepen caramel flavor.
        Change: Chill the mixed dough for one night before baking.
        Rationale: More time lets the flour hydrate and sugars develop.
        Hypothesis: Brown butter will add nuttiness without thinning the cookie.
        Change: Replace melted butter with cooled brown butter by weight.
        Rationale: Browning adds flavor while preserving the fat quantity.
        YC-LEARNINGS:
        - Brown butter always improves cookies.
        """,
        in: db,
        now: now
      )

      guard case let .workbenchExperiments(experimentsReview) = review else {
        Issue.record("Expected an experiments review.")
        return
      }
      expectNoDifference(experimentsReview.workbenchID, workbenchID)
      expectNoDifference(
        experimentsReview.experiments,
        [
          WorkbenchExperiment(
            id: 0,
            hypothesis: "Resting the dough overnight will deepen caramel flavor.",
            change: "Chill the mixed dough for one night before baking.",
            rationale: "More time lets the flour hydrate and sugars develop."
          ),
          WorkbenchExperiment(
            id: 1,
            hypothesis: "Brown butter will add nuttiness without thinning the cookie.",
            change: "Replace melted butter with cooled brown butter by weight.",
            rationale: "Browning adds flavor while preserving the fat quantity."
          ),
        ]
      )
      #expect(try WorkbenchLogEntry.fetchAll(db).isEmpty)
    }
  }

  @Test
  func workbenchExperimentsKeepMalformedBlocksLoud() {
    let returned = AIHandoffReturn.workbenchExperiments(
      from: """
      Hypothesis: Add a second yolk for chewiness.
      Change: Add one extra yolk.
      This explanation has no label.
      """
    )

    expectNoDifference(returned.experiments, [])
    expectNoDifference(
      returned.unparsedBlocks,
      [
        """
        Hypothesis: Add a second yolk for chewiness.
        Change: Add one extra yolk.
        This explanation has no label.
        """,
      ]
    )
  }
}

private enum SeedFailure: Error, Sendable {
  case unavailable
}
