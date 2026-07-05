import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MealPlanComplementTests {
    @Test
    func mealPlanComplementParsesConcreteMealPlanItems() {
      let plan = MealPlanComplementClient.parse(
        """
        {"items":[
          {"kind":"note","title":"  Cucumber herb salad  ","mealSlot":"dinner"},
          {"kind":"recipe","title":"Cardamom buns","mealSlot":"breakfast"},
          {"kind":"reservation","title":"Cafe brunch","mealSlot":"lunch"},
          {"kind":"note","title":"No slot"},
          {"kind":"note","title":"  ","mealSlot":"snack"}
        ]}
        """
      )

      expectNoDifference(
        plan,
        MealPlanComplementPlan(
          items: [
            MealPlanComplementSuggestion(
              kind: .note,
              title: "Cucumber herb salad",
              mealSlot: .dinner
            ),
            MealPlanComplementSuggestion(
              kind: .note,
              title: "Cardamom buns",
              mealSlot: .breakfast
            ),
            MealPlanComplementSuggestion(
              kind: .note,
              title: "Cafe brunch",
              mealSlot: .lunch
            ),
          ]
        )
      )
    }

    @Test
    func mealPlanComplementClientSendsRequestedModelTierAndDayContext() async throws {
      let recorder = MealPlanComplementRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"items":[]}"#)
        }
      } operation: {
        let client = MealPlanComplementClient.liveValue
        _ = try await client(
          selection: "What goes with Tuesday dinner?",
          messages: [RecipeChatMessage(role: .user, text: "Suggest something bright.")],
          context: "Meal plan day context",
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.anthropic))
      expectNoDifference(request?.reasoningEffort, .medium)
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.complements.rawValue)
      #expect(request?.messages.first?.text.contains("Meal plan day context:\nMeal plan day context") == true)
      #expect(request?.messages.first?.text.contains("User-selected subject:\nWhat goes with Tuesday dinner?") == true)
      #expect(
        request?.messages.first?.text.contains("Choose only the meal slot for each suggestion") == true
      )
    }

    @Test
    @MainActor
    func mealPlanComplementReviewItemsInsertOnlyTheCommittedSuggestion() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_700_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 805_800_000)
      let committedAt = now.addingTimeInterval(60)
      let itemIDs = [
        SampleUUIDSequence.uuid(15_510),
        SampleUUIDSequence.uuid(15_511),
      ]
      var extractedSelection: String?
      var extractedContext: [RecipeChatMessage] = []

      let action = ChatApplyAction<MealPlanComplementPlan>(
        title: "What complements this day? -> Meal plan items",
        extractingTitle: "Finding complements...",
        reviewTitle: "Review complement",
        commitTitle: "Add to Meal Plan",
        committingTitle: "Adding to meal plan...",
        committedTitle: "Added to Meal Plan",
        extract: { selection, context in
          extractedSelection = selection
          extractedContext = context
          return MealPlanComplementPlan(
            items: [
              MealPlanComplementSuggestion(
                kind: .note,
                title: "Cucumber herb salad",
                mealSlot: .dinner
              ),
              MealPlanComplementSuggestion(
                kind: .note,
                title: "Garlic flatbread",
                mealSlot: .lunch
              ),
            ]
          )
        },
        commit: { _ in }
      )
      let erased = AnyChatApplyAction(action) { plan in
        plan.items.enumerated().map { index, suggestion in
          ChatApplyReviewItem(
            title: suggestion.title,
            summary: suggestion.rendered(dayTitle: "Tuesday, July 8"),
            commitTitle: action.commitTitle,
            committingTitle: action.committingTitle,
            committedTitle: action.committedTitle,
            commit: {
              _ = try await database.write { db in
                try MealCalendarRepository.addComplementItem(
                  suggestion,
                  on: scheduledDate,
                  in: db,
                  now: committedAt,
                  uuid: { itemIDs[index] }
                )
              }
            }
          )
        }
      }
      let messages = [
        RecipeChatMessage(role: .assistant, text: "A crisp salad would balance the grilled mains.")
      ]

      let items = try await erased.run("Add the salad idea.", messages)

      expectNoDifference(extractedSelection, "Add the salad idea.")
      expectNoDifference(extractedContext, messages)
      expectNoDifference(items.map(\.title), ["Cucumber herb salad", "Garlic flatbread"])
      expectNoDifference(items.map(\.commitTitle), ["Add to Meal Plan", "Add to Meal Plan"])
      try await database.read { db in
        expectNoDifference(try MealPlanItem.fetchAll(db), [])
      }

      try await items[0].commit()

      try await database.read { db in
        let mealPlanItems = try MealPlanItem.fetchAll(db)
        expectNoDifference(mealPlanItems.map(\.title), ["Cucumber herb salad"])
        expectNoDifference(mealPlanItems.map(\.kind), [.note])
        expectNoDifference(mealPlanItems.map(\.recipeID), [nil])
        expectNoDifference(mealPlanItems.map(\.scheduledDate), [scheduledDate])
        expectNoDifference(mealPlanItems.map(\.mealSlot), [.dinner])
        expectNoDifference(mealPlanItems.map(\.dateModified), [committedAt])
      }
    }

    @Test
    func addComplementItemUsesDayOrderingAndCoercesSuggestionsToNotes() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_900_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 806_000_000)
      var uuids = SampleUUIDSequence(start: 15_610)

      try database.write { db in
        _ = try MealCalendarRepository.addNoteItem(
          title: "Existing Salad",
          notes: nil,
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let complementID = try MealCalendarRepository.addComplementItem(
          MealPlanComplementSuggestion(
            kind: .recipe,
            title: "Roasted carrots",
            mealSlot: .dinner
          ),
          on: scheduledDate,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let complement = try #require(try MealPlanItem.find(complementID).fetchOne(db))
        expectNoDifference(complement.sortOrder, 1)
        expectNoDifference(complement.title, "Roasted carrots")
        expectNoDifference(complement.kind, .note)
        expectNoDifference(complement.recipeID, nil)
        expectNoDifference(complement.scheduledDate, scheduledDate)
      }
    }
  }
}

private actor MealPlanComplementRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
