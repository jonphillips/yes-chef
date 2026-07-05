import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuComplementTests {
    @Test
    func menuComplementParsesConcreteMenuItems() {
      let plan = MenuComplementClient.parse(
        """
        {"items":[
          {"kind":"note","title":"  Cucumber herb salad  ","dayOffset":0,"mealSlot":"dinner"},
          {"kind":"recipe","title":"Cardamom buns","dayOffset":1,"mealSlot":"breakfast"},
          {"kind":"reservation","title":"Cafe brunch","dayOffset":1,"mealSlot":"lunch"},
          {"kind":"note","title":"No slot","dayOffset":1},
          {"kind":"note","title":"  ","dayOffset":1,"mealSlot":"snack"}
        ]}
        """
      )

      expectNoDifference(
        plan,
        MenuComplementPlan(
          items: [
            MenuComplementSuggestion(
              kind: .note,
              title: "Cucumber herb salad",
              dayOffset: 0,
              mealSlot: .dinner
            ),
            MenuComplementSuggestion(
              kind: .note,
              title: "Cardamom buns",
              dayOffset: 1,
              mealSlot: .breakfast
            ),
            MenuComplementSuggestion(
              kind: .note,
              title: "Cafe brunch",
              dayOffset: 1,
              mealSlot: .lunch
            ),
          ]
        )
      )
    }

    @Test
    func menuComplementClientSendsRequestedModelTierAndMenuContext() async throws {
      let recorder = MenuComplementRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"items":[]}"#)
        }
      } operation: {
        let client = MenuComplementClient.liveValue
        _ = try await client(
          selection: "What goes with day two dinner?",
          messages: [RecipeChatMessage(role: .user, text: "Suggest something bright.")],
          context: "Menu context",
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.anthropic))
      expectNoDifference(request?.reasoningEffort, .medium)
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.complements.rawValue)
      #expect(request?.messages.first?.text.contains("Menu context:\nMenu context") == true)
      #expect(request?.messages.first?.text.contains("User-selected subject:\nWhat goes with day two dinner?") == true)
    }

    @Test
    @MainActor
    func menuComplementReviewItemsInsertOnlyTheCommittedSuggestion() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_500_000)
      let committedAt = now.addingTimeInterval(60)
      let menuID = SampleUUIDSequence.uuid(15_300)
      let itemIDs = [
        SampleUUIDSequence.uuid(15_310),
        SampleUUIDSequence.uuid(15_311),
      ]
      var extractedSelection: String?
      var extractedContext: [RecipeChatMessage] = []

      try await database.write { db in
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Complement Menu",
            dayCount: 2,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      let action = ChatApplyAction<MenuComplementPlan>(
        title: "What complements this? -> Menu items",
        extractingTitle: "Finding complements...",
        reviewTitle: "Review complement",
        commitTitle: "Add to Menu",
        committingTitle: "Adding to menu...",
        committedTitle: "Added to Menu",
        extract: { selection, context in
          extractedSelection = selection
          extractedContext = context
          return MenuComplementPlan(
            items: [
              MenuComplementSuggestion(
                kind: .note,
                title: "Cucumber herb salad",
                dayOffset: 0,
                mealSlot: .dinner
              ),
              MenuComplementSuggestion(
                kind: .note,
                title: "Garlic flatbread",
                dayOffset: 1,
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
            summary: suggestion.rendered(),
            commitTitle: action.commitTitle,
            committingTitle: action.committingTitle,
            committedTitle: action.committedTitle,
            commit: {
              _ = try await database.write { db in
                try MenuRepository.addComplementItem(
                  suggestion,
                  to: menuID,
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
      expectNoDifference(items.map(\.commitTitle), ["Add to Menu", "Add to Menu"])
      try await database.read { db in
        expectNoDifference(try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db), [])
      }

      try await items[0].commit()

      try await database.read { db in
        let menuItems = try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db)
        expectNoDifference(menuItems.map(\.title), ["Cucumber herb salad"])
        expectNoDifference(menuItems.map(\.kind), [.note])
        expectNoDifference(menuItems.map(\.dayOffset), [0])
        expectNoDifference(menuItems.map(\.mealSlot), [.dinner])
        expectNoDifference(menuItems.map(\.dateModified), [committedAt])
      }
    }

    @Test
    func addComplementItemUsesMenuOrderingAndValidatesDayOffset() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_600_000)
      let menuID = SampleUUIDSequence.uuid(15_400)
      var uuids = SampleUUIDSequence(start: 15_410)

      try database.write { db in
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Ordering Menu",
            dayCount: 2,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        _ = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Existing Salad",
          notes: nil,
          dayOffset: 1,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let complementID = try MenuRepository.addComplementItem(
          MenuComplementSuggestion(
            kind: .note,
            title: "Roasted carrots",
            dayOffset: 1,
            mealSlot: .dinner
          ),
          to: menuID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let complement = try #require(try MenuItem.find(complementID).fetchOne(db))
        expectNoDifference(complement.sortOrder, 1)
        expectNoDifference(complement.title, "Roasted carrots")
        expectNoDifference(complement.recipeID, nil)

        #expect(
          throws: MenuRepositoryError.invalidDayOffset(2),
          performing: {
            _ = try MenuRepository.addComplementItem(
              MenuComplementSuggestion(
                kind: .note,
                title: "Too late",
                dayOffset: 2,
                mealSlot: .dinner
              ),
              to: menuID,
              in: db,
              now: now,
              uuid: { uuids.next() }
            )
          }
        )
      }
    }
  }
}

private actor MenuComplementRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
