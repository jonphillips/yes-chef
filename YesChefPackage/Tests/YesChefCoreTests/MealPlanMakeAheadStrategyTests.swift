import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MealPlanMakeAheadStrategyTests {
    @Test
    func mealPlanMakeAheadStrategyParsesConcreteSteps() {
      let plan = MealPlanMakeAheadStrategyClient.parse(
        """
        {"title":"  Saturday prep  ","mealSlot":"lunch","steps":[
          {"when":"  Morning  ","task":"Make the vinaigrette.","sourceItem":"meal:abc"},
          {"when":"1 hour before","task":"Toast the almonds.","sourceItem":null},
          {"when":"later","sourceItem":"not enough"},
          {"when":"  ","task":"Skip me."}
        ]}
        """
      )

      expectNoDifference(
        plan,
        MealPlanMakeAheadStrategy(
          title: "Saturday prep",
          mealSlot: .lunch,
          steps: [
            MealPlanMakeAheadStep(
              when: "Morning",
              task: "Make the vinaigrette.",
              sourceItem: "meal:abc"
            ),
            MealPlanMakeAheadStep(
              when: "1 hour before",
              task: "Toast the almonds."
            ),
          ]
        )
      )
      expectNoDifference(
        plan.rendered(),
        """
        Saturday prep - Lunch
        Morning: Make the vinaigrette.
        1 hour before: Toast the almonds.
        """
      )
    }

    @Test
    func mealPlanMakeAheadStrategyClientSendsRequestedModelTierAndDayContext() async throws {
      let recorder = MealPlanMakeAheadRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"steps":[]}"#)
        }
      } operation: {
        let client = MealPlanMakeAheadStrategyClient.liveValue
        _ = try await client(
          selection: "Sequence the day.",
          messages: [RecipeChatMessage(role: .user, text: "Build a prep strategy.")],
          context: "Meal plan day context with make-ahead notes",
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.anthropic))
      expectNoDifference(request?.reasoningEffort, .high)
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.makeAheadPrepPlan.rawValue)
      #expect(request?.messages.first?.text.contains("Meal plan day context:\nMeal plan day context") == true)
      #expect(request?.messages.first?.text.contains("User-selected subject:\nSequence the day.") == true)
      #expect(request?.system?.contains("Sequence and select distinct prep steps") == true)
      #expect(request?.system?.contains("Do not flatten multiple recipes into one blob") == true)
    }

    @Test
    @MainActor
    func stagedMakeAheadStrategyReviewItemWritesOnlyWhenCommitted() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_100_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 806_200_000)
      let committedAt = now.addingTimeInterval(60)
      let itemID = SampleUUIDSequence.uuid(15_710)
      var extractedSelection: String?
      var extractedContext: [RecipeChatMessage] = []

      let action = ChatApplyAction<MealPlanMakeAheadStrategy>(
        title: "Build make-ahead strategy -> Meal plan note",
        extractingTitle: "Building make-ahead strategy...",
        reviewTitle: "Review make-ahead strategy",
        commitTitle: "Add Strategy Note",
        committingTitle: "Adding strategy note...",
        committedTitle: "Added Strategy Note",
        extract: { selection, context in
          extractedSelection = selection
          extractedContext = context
          return MealPlanMakeAheadStrategy(
            title: "Saturday prep",
            mealSlot: .dinner,
            steps: [
              MealPlanMakeAheadStep(
                when: "Morning",
                task: "Make the sauce.",
                sourceItem: "meal:abc"
              )
            ]
          )
        },
        commit: { _ in }
      )
      let erased = AnyChatApplyAction(action) { strategy in
        let summary = strategy.rendered().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return [] }
        return [
          ChatApplyReviewItem(
            title: strategy.title,
            summary: summary,
            commitTitle: action.commitTitle,
            committingTitle: action.committingTitle,
            committedTitle: action.committedTitle,
            commit: {
              _ = try await database.write { db in
                try MealCalendarRepository.addMakeAheadStrategyNote(
                  strategy,
                  on: scheduledDate,
                  in: db,
                  now: committedAt,
                  uuid: { itemID }
                )
              }
            }
          )
        ]
      }
      let messages = [
        RecipeChatMessage(role: .assistant, text: "Use the sauce and salad make-ahead notes.")
      ]

      let items = try await erased.run("Use the saved make-ahead notes.", messages)

      expectNoDifference(extractedSelection, "Use the saved make-ahead notes.")
      expectNoDifference(extractedContext, messages)
      expectNoDifference(items.map(\.summary), ["Saturday prep - Dinner\nMorning: Make the sauce."])
      try await database.read { db in
        expectNoDifference(try MealPlanItem.fetchAll(db), [])
      }

      try await items[0].commit()

      try await database.read { db in
        let mealPlanItems = try MealPlanItem.fetchAll(db)
        expectNoDifference(mealPlanItems.map(\.title), ["Saturday prep"])
        expectNoDifference(mealPlanItems.map(\.kind), [.note])
        expectNoDifference(mealPlanItems.map(\.recipeID), [nil])
        expectNoDifference(mealPlanItems.map(\.notes), ["Morning: Make the sauce."])
        expectNoDifference(mealPlanItems.map(\.scheduledDate), [scheduledDate])
        expectNoDifference(mealPlanItems.map(\.mealSlot), [.dinner])
        expectNoDifference(mealPlanItems.map(\.dateModified), [committedAt])
      }
    }

    @Test
    func addMakeAheadStrategyNoteUsesDayOrdering() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_300_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 806_400_000)
      var uuids = SampleUUIDSequence(start: 15_810)

      try database.write { db in
        _ = try MealCalendarRepository.addNoteItem(
          title: "Existing note",
          notes: nil,
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let strategyID = try MealCalendarRepository.addMakeAheadStrategyNote(
          MealPlanMakeAheadStrategy(
            title: "Sunday prep",
            mealSlot: .dinner,
            steps: [
              MealPlanMakeAheadStep(when: "Day before", task: "Make dessert.")
            ]
          ),
          on: scheduledDate,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let strategy = try #require(try MealPlanItem.find(strategyID).fetchOne(db))
        expectNoDifference(strategy.sortOrder, 1)
        expectNoDifference(strategy.title, "Sunday prep")
        expectNoDifference(strategy.kind, .note)
        expectNoDifference(strategy.recipeID, nil)
        expectNoDifference(strategy.notes, "Day before: Make dessert.")
        expectNoDifference(strategy.scheduledDate, scheduledDate)
      }
    }
  }
}

private actor MealPlanMakeAheadRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
