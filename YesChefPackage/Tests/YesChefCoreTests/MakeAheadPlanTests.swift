import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Synchronization
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MakeAheadPlanTests {
    @Test
    func parseDropsMalformedElementsButKeepsUsableSteps() {
      let plan = MakeAheadPlanClient.parse(
        """
        Here is the JSON:
        {
          "steps": [
            {
              "when": "2 days before",
              "task": "Make the sauce and refrigerate it.",
              "why": "The flavor improves after resting."
            },
            {
              "when": "Morning of"
            },
            {
              "when": "Before serving",
              "task": "Warm the sauce gently."
            }
          ]
        }
        """
      )

      expectNoDifference(
        plan,
        MakeAheadPlan(
          steps: [
            MakeAheadStep(
              when: "2 days before",
              task: "Make the sauce and refrigerate it.",
              why: "The flavor improves after resting."
            ),
            MakeAheadStep(
              when: "Before serving",
              task: "Warm the sauce gently."
            ),
          ]
        )
      )
    }

    @Test
    func renderedPlanFlattensForRecipeStorage() {
      let plan = MakeAheadPlan(
        steps: [
          MakeAheadStep(when: "Day before", task: "Toast the nuts.", why: "They stay crisp once cooled."),
          MakeAheadStep(when: "Just before dinner", task: "Dress the salad."),
        ]
      )

      expectNoDifference(
        plan.rendered(),
        """
        Day before: Toast the nuts.
        Why: They stay crisp once cooled.

        Just before dinner: Dress the salad.
        """
      )
    }

    @Test
    func enrichmentClientsParseFocusedJSON() {
      expectNoDifference(
        ChefItUpPlanClient.parse(#"{"text":"Brown the butter before mixing it into the batter."}"#),
        ChefItUpPlan(text: "Brown the butter before mixing it into the batter.")
      )
      expectNoDifference(
        ServeWithPlanClient.parse(
          """
          {"items":[
            {"title":"Cilantro-scallion rice","note":"Stir in butter right before serving."},
            {"title":"Cucumber salad"}
          ]}
          """
        ),
        ServeWithPlan(
          items: [
            ServeWithSuggestion(title: "Cilantro-scallion rice", note: "Stir in butter right before serving."),
            ServeWithSuggestion(title: "Cucumber salad"),
          ]
        )
      )
    }

    @Test
    @MainActor
    func recipeChatSendDoesNotIncludeAssistantPlaceholderInRequest() async {
      let recorder = ModelRequestRecorder()

      await withDependencies {
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: "Yes, make the sauce a day ahead.")
        }
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        await model.send("Can I make this ahead?")

        let request = await recorder.first()
        expectNoDifference(request?.messages, [.user("Can I make this ahead?")])
        expectNoDifference(request?.reasoningEffort, .medium)
        expectNoDifference(model.messages.map(\.role), [.user, .assistant])
        expectNoDifference(
          model.messages.map(\.text),
          ["Can I make this ahead?", "Yes, make the sauce a day ahead."]
        )
      }
    }

    @Test
    func enrichmentClientsSendHighEffortAndTaskPreferenceKeys() async throws {
      let recorder = ModelRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"text":""}"#)
        }
      } operation: {
        let chefItUp = ChefItUpPlanClient.liveValue
        _ = try await chefItUp(
          selection: "Make it special.",
          messages: [],
          context: "Recipe context",
          tier: .frontier(.openai)
        )
      }

      let chefItUpRequest = await recorder.first()
      expectNoDifference(chefItUpRequest?.reasoningEffort, .high)
      expectNoDifference(chefItUpRequest?.promptPreferenceKey, AIPromptPreferenceKind.chefItUp.rawValue)

      let serveWithRecorder = ModelRequestRecorder()
      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await serveWithRecorder.append(request)
          return ModelResponse(text: #"{"items":[]}"#)
        }
      } operation: {
        let serveWith = ServeWithPlanClient.liveValue
        _ = try await serveWith(
          selection: "Suggest sides.",
          messages: [],
          context: "Recipe context",
          tier: .frontier(.openai)
        )
      }

      let serveWithRequest = await serveWithRecorder.first()
      expectNoDifference(serveWithRequest?.reasoningEffort, .high)
      expectNoDifference(serveWithRequest?.promptPreferenceKey, AIPromptPreferenceKind.serveWith.rawValue)
    }

    @Test
    func makeAheadClientSendsRequestedModelTier() async throws {
      let recorder = ModelRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"steps":[]}"#)
        }
      } operation: {
        let client = MakeAheadPlanClient.liveValue
        _ = try await client(
          selection: "Make the sauce a day ahead.",
          messages: [RecipeChatMessage(role: .user, text: "Can I prep this ahead?")],
          context: "Recipe context",
          tier: .frontier(.openai)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.openai))
      expectNoDifference(request?.reasoningEffort, .high)
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.makeAheadPrepPlan.rawValue)
      #expect(request?.messages.first?.text.contains("User-selected subject:\nMake the sauce a day ahead.") == true)
    }

    @Test
    @MainActor
    func recipeChatDefaultsToOnlyConfiguredProvider() {
      withDependencies {
        $0.apiKeyStore = apiKeyStore([.openai: "sk-openai"])
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        model.useFrontier = true

        expectNoDifference(model.selectedProvider, .openai)
        expectNoDifference(model.activeTier, .frontier(.openai))
      }
    }

    @Test
    @MainActor
    func recipeChatUsesStoredProviderWhenConfigured() {
      withDependencies {
        $0.apiKeyStore = apiKeyStore([.anthropic: "sk-ant", .openai: "sk-openai"])
        $0.recipeChatProviderPreference = RecipeChatProviderPreference(
          current: { .openai },
          set: { _ in }
        )
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        model.useFrontier = true

        expectNoDifference(model.selectedProvider, .openai)
        expectNoDifference(model.activeTier, .frontier(.openai))
      }
    }

    @Test
    @MainActor
    func recipeChatPersistsSelectedProvider() {
      let storedProvider = Mutex<FrontierProvider?>(nil)

      withDependencies {
        $0.apiKeyStore = apiKeyStore([.anthropic: "sk-ant", .openai: "sk-openai"])
        $0.recipeChatProviderPreference = RecipeChatProviderPreference(
          current: { storedProvider.withLock { $0 } },
          set: { provider in storedProvider.withLock { $0 = provider } }
        )
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        model.selectedProvider = .openai

        expectNoDifference(storedProvider.withLock { $0 }, .openai)
      }
    }

    @Test
    @MainActor
    func recipeChatUsesStoredFrontierTierWhenConfigured() {
      withDependencies {
        $0.apiKeyStore = apiKeyStore([.openai: "sk-openai"])
        $0.recipeChatTierPreference = RecipeChatTierPreference(
          current: { true },
          set: { _ in }
        )
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        expectNoDifference(model.useFrontier, true)
        expectNoDifference(model.activeTier, .frontier(.openai))
      }
    }

    @Test
    @MainActor
    func recipeChatIgnoresStoredFrontierTierWithoutConfiguredProvider() {
      withDependencies {
        $0.apiKeyStore = apiKeyStore([:])
        $0.recipeChatTierPreference = RecipeChatTierPreference(
          current: { true },
          set: { _ in }
        )
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        expectNoDifference(model.useFrontier, false)
        expectNoDifference(model.activeTier, .onDevice)
      }
    }

    @Test
    @MainActor
    func recipeChatPersistsFrontierTierChoice() {
      let storedUseFrontier = Mutex<Bool?>(nil)

      withDependencies {
        $0.apiKeyStore = apiKeyStore([.openai: "sk-openai"])
        $0.recipeChatTierPreference = RecipeChatTierPreference(
          current: { storedUseFrontier.withLock { $0 } },
          set: { useFrontier in storedUseFrontier.withLock { $0 = useFrontier } }
        )
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
        )

        model.useFrontier = true
        expectNoDifference(storedUseFrontier.withLock { $0 }, true)

        model.useFrontier = false
        expectNoDifference(storedUseFrontier.withLock { $0 }, false)
      }
    }

    @Test
    func recipeChatContextSerializesRecipeDetail() throws {
      let now = Date(timeIntervalSinceReferenceDate: 820_000_000)
      let recipeID = SampleUUIDSequence.uuid(600)
      let ingredientSectionID = SampleUUIDSequence.uuid(601)
      let instructionSectionID = SampleUUIDSequence.uuid(602)
      let detail = RecipeDetailData(
        recipe: Recipe(
          id: recipeID,
          title: "Tomato Tart",
          summary: "A weeknight tart.",
          servingsText: "4 servings",
          prepTimeMinutes: 20,
          cookTimeMinutes: 35,
          totalTimeMinutes: 55,
          dateCreated: now,
          dateModified: now,
          makeAhead: "Day before: Make the pastry."
        ),
        ingredientSections: [
          IngredientSection(id: ingredientSectionID, recipeID: recipeID, name: "Filling", sortOrder: 0)
        ],
        ingredientLines: [
          IngredientLine(
            id: SampleUUIDSequence.uuid(603),
            recipeID: recipeID,
            sectionID: ingredientSectionID,
            originalText: "2 tomatoes",
            sortOrder: 0
          )
        ],
        instructionSections: [
          InstructionSection(id: instructionSectionID, recipeID: recipeID, name: nil, sortOrder: 0)
        ],
        instructionSteps: [
          InstructionStep(
            id: SampleUUIDSequence.uuid(604),
            recipeID: recipeID,
            sectionID: instructionSectionID,
            text: "Bake until browned.",
            sortOrder: 0
          )
        ],
        notes: [
          RecipeNote(
            id: SampleUUIDSequence.uuid(605),
            recipeID: recipeID,
            text: "Use ripe tomatoes.",
            noteType: .general,
            dateCreated: now,
            dateModified: now
          ),
          RecipeNote(
            id: SampleUUIDSequence.uuid(606),
            recipeID: recipeID,
            text: "Blind-bake the crust or it goes soggy.",
            noteType: .readerFeedback,
            dateCreated: now,
            dateModified: now
          ),
        ]
      )

      let context = RecipeChatContext.recipe(RecipeChatRecipeContext(detail: detail))

      expectNoDifference(
        context.serialized(),
        """
        The user is looking at this recipe:
        - Title: Tomato Tart
        - Summary: A weeknight tart.
        - Servings: 4 servings
        - Prep time: 20 minutes
        - Cook time: 35 minutes
        - Total time: 55 minutes
        Ingredients:
        - Filling:
          - 2 tomatoes
        Instructions:
        - Bake until browned.
        Notes:
        - Use ripe tomatoes.
        Reader Feedback (curated tips from reader comments, not the recipe author):
        - Blind-bake the crust or it goes soggy.
        Current make-ahead section:
        Day before: Make the pastry.
        """
      )
    }

    @Test
    func applyMakeAheadPlanReplacesFieldAndClearUndoRemovesIt() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 821_000_000)
      let modifiedAt = now.addingTimeInterval(60)
      let clearedAt = now.addingTimeInterval(120)
      let recipeID = SampleUUIDSequence.uuid(620)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Braised Beans",
            dateCreated: now,
            dateModified: now,
            makeAhead: "Old plan"
          )
        }
        .execute(db)

        try RecipeRepository.applyMakeAheadPlan(
          MakeAheadPlan(
            steps: [
              MakeAheadStep(when: "Day before", task: "Cook the beans.", why: "They reheat well.")
            ]
          ),
          to: recipeID,
          in: db,
          now: modifiedAt
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(
          recipe.makeAhead,
          """
          Day before: Cook the beans.
          Why: They reheat well.
          """
        )
        expectNoDifference(recipe.dateModified, modifiedAt)
      }

      try database.write { db in
        try RecipeRepository.clearMakeAhead(recipeID: recipeID, in: db, now: clearedAt)
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.makeAhead, nil)
        expectNoDifference(recipe.dateModified, clearedAt)
      }
    }

    @Test
    func recipeEnrichmentWritesOwnFieldsAndUndoRemovesIndependently() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 825_000_000)
      let modifiedAt = now.addingTimeInterval(60)
      let removedAt = now.addingTimeInterval(120)
      let recipeID = SampleUUIDSequence.uuid(36_201)
      var uuids = SampleUUIDSequence(start: 36_300)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Chili", dateCreated: now, dateModified: now)
        }
        .execute(db)

        try RecipeRepository.applyChefItUpPlan(
          ChefItUpPlan(text: "Toast the spices in oil before adding the tomatoes."),
          to: recipeID,
          in: db,
          now: modifiedAt
        )
        try RecipeRepository.appendServeWithPlan(
          ServeWithPlan(
            items: [
              ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
              ServeWithSuggestion(title: "Skillet cornbread"),
            ]
          ),
          to: recipeID,
          in: db,
          now: modifiedAt,
          uuid: { uuids.next() }
        )
      }

      let firstServeWithID: ServeWithItem.ID = try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        let serveWith = ServeWithCoding.decode(recipe.serveWith)
        expectNoDifference(recipe.chefItUp, "Toast the spices in oil before adding the tomatoes.")
        expectNoDifference(
          serveWith.map { ServeWithSuggestion(title: $0.title, note: $0.note) },
          [
            ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithSuggestion(title: "Skillet cornbread"),
          ]
        )
        return try #require(serveWith.first?.id)
      }

      try database.write { db in
        try RecipeRepository.clearChefItUp(recipeID: recipeID, in: db, now: removedAt)
        try RecipeRepository.removeServeWithItem(firstServeWithID, recipeID: recipeID, in: db, now: removedAt)
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.chefItUp, nil)
        expectNoDifference(ServeWithCoding.decode(recipe.serveWith).map(\.title), ["Skillet cornbread"])
        expectNoDifference(recipe.dateModified, removedAt)
      }
    }

    @Test
    @MainActor
    func stagedMakeAheadReviewItemWritesOnlyWhenCommitted() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 823_000_000)
      let committedAt = now.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(660)
      var extractedSelection: String?
      var extractedContext: [RecipeChatMessage] = []

      try await database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Tomato Sauce",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      let action = ChatApplyAction<MakeAheadPlan>(
        title: "Create Prep Plan",
        extractingTitle: "Summarizing make-ahead...",
        reviewTitle: "Review make-ahead",
        commitTitle: "Commit to Make-ahead",
        committingTitle: "Saving make-ahead...",
        committedTitle: "Saved to Make-ahead",
        extract: { selection, context in
          extractedSelection = selection
          extractedContext = context
          return MakeAheadPlan(
            steps: [
              MakeAheadStep(when: "Day before", task: "Make the sauce.")
            ]
          )
        },
        commit: { plan in
          try await database.write { db in
            try RecipeRepository.applyMakeAheadPlan(plan, to: recipeID, in: db, now: committedAt)
          }
        }
      )
      let erased = AnyChatApplyAction(action) { $0.rendered() }
      let messages = [
        RecipeChatMessage(role: .assistant, text: "Make the sauce a day ahead. Also grate cheese.")
      ]

      let items = try await erased.run("Make the sauce a day ahead.", messages)

      expectNoDifference(extractedSelection, "Make the sauce a day ahead.")
      expectNoDifference(extractedContext, messages)
      expectNoDifference(items.map(\.summary), ["Day before: Make the sauce."])
      try await database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.makeAhead, nil)
      }

      try await items[0].commit(items[0].summary)

      try await database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.makeAhead, "Day before: Make the sauce.")
        expectNoDifference(recipe.dateModified, committedAt)
      }
    }

    @Test
    func editorSavePreservesExistingMakeAheadSection() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 822_000_000)
      let savedAt = now.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(640)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Soup",
            dateCreated: now,
            dateModified: now,
            makeAhead: "Morning of: Chop the vegetables."
          )
        }
        .execute(db)

        var draft = RecipeEditorDraft()
        draft.id = recipeID
        draft.title = "Better Soup"
        draft.dateCreated = now

        try RecipeRepository.save(
          draft: draft,
          in: db,
          now: savedAt,
          uuid: { SampleUUIDSequence.uuid(641) }
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.title, "Better Soup")
        expectNoDifference(recipe.makeAhead, "Morning of: Chop the vegetables.")
      }
    }
  }
}

private func apiKeyStore(_ keys: [FrontierProvider: String]) -> APIKeyStore {
  let storage = Mutex(keys)
  return APIKeyStore(
    read: { provider in storage.withLock { $0[provider] } },
    write: { provider, key in storage.withLock { $0[provider] = key } }
  )
}

private actor ModelRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
