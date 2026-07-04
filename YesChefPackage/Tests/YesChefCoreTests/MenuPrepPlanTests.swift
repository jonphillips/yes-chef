import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuPrepPlanTests {
    @Test
    func menuPrepPlanParsesAndCodesNullableSourceDish() throws {
      let sourceDishID = SampleUUIDSequence.uuid(15_000)

      let plan = MenuPrepPlanClient.parse(
        """
        {"steps":[
          {
            "when":"2 days out",
            "task":"Make the barbecue sauce.",
            "sourceDish":"\(sourceDishID.uuidString)"
          },
          {
            "when":"morning of day 2",
            "task":"Set out serving platters.",
            "sourceDish":null
          },
          {
            "when":"later",
            "sourceDish":"not enough"
          }
        ]}
        """
      )

      expectNoDifference(
        plan,
        MenuPrepPlan(
          steps: [
            PrepPlanStep(
              when: "2 days out",
              task: "Make the barbecue sauce.",
              sourceDish: sourceDishID
            ),
            PrepPlanStep(
              when: "morning of day 2",
              task: "Set out serving platters."
            ),
          ]
        )
      )

      let data = try #require(try MenuPrepPlanCoding.encode(plan.steps))
      expectNoDifference(MenuPrepPlanCoding.decode(data), plan.steps)
      expectNoDifference(try MenuPrepPlanCoding.encode([]), nil)
    }

    @Test
    func menuPrepPlanClientSendsRequestedModelTierAndMenuContext() async throws {
      let recorder = ModelRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"steps":[]}"#)
        }
      } operation: {
        let client = MenuPrepPlanClient.liveValue
        _ = try await client(
          selection: "Sequence the prep.",
          messages: [RecipeChatMessage(role: .user, text: "Build a prep plan.")],
          context: "Menu context",
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.anthropic))
      #expect(request?.messages.first?.text.contains("Menu context:\nMenu context") == true)
      #expect(request?.messages.first?.text.contains("User-selected subject:\nSequence the prep.") == true)
    }

    @Test
    @MainActor
    func stagedMenuPrepPlanReviewItemWritesOnlyWhenCommitted() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_300_000)
      let committedAt = now.addingTimeInterval(60)
      let menuID = SampleUUIDSequence.uuid(15_100)
      let sourceDishID = SampleUUIDSequence.uuid(15_101)
      var extractedSelection: String?
      var extractedContext: [RecipeChatMessage] = []

      try await database.write { db in
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Weekend Menu",
            dayCount: 2,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      let action = ChatApplyAction<MenuPrepPlan>(
        title: "Build prep plan -> Prep Plan section",
        extractingTitle: "Building prep plan...",
        reviewTitle: "Review prep plan",
        commitTitle: "Commit to Prep Plan",
        committingTitle: "Saving prep plan...",
        committedTitle: "Saved to Prep Plan",
        extract: { selection, context in
          extractedSelection = selection
          extractedContext = context
          return MenuPrepPlan(
            steps: [
              PrepPlanStep(
                when: "Day before",
                task: "Marinate the chicken.",
                sourceDish: sourceDishID
              )
            ]
          )
        },
        commit: { plan in
          try await database.write { db in
            try MenuRepository.applyPrepPlan(plan, to: menuID, in: db, now: committedAt)
          }
        }
      )
      let erased = AnyChatApplyAction(action) { $0.rendered() }
      let messages = [
        RecipeChatMessage(role: .assistant, text: "Use the existing chicken make-ahead note.")
      ]

      let items = try await erased.run("Use the chicken note.", messages)

      expectNoDifference(extractedSelection, "Use the chicken note.")
      expectNoDifference(extractedContext, messages)
      expectNoDifference(items.map(\.summary), ["Day before: Marinate the chicken."])
      try await database.read { db in
        let menu = try #require(try Menu.find(menuID).fetchOne(db))
        expectNoDifference(MenuPrepPlanCoding.decode(menu.prepPlan), [])
      }

      try await items[0].commit()

      try await database.read { db in
        let menu = try #require(try Menu.find(menuID).fetchOne(db))
        expectNoDifference(
          MenuPrepPlanCoding.decode(menu.prepPlan),
          [
            PrepPlanStep(
              when: "Day before",
              task: "Marinate the chicken.",
              sourceDish: sourceDishID
            )
          ]
        )
        expectNoDifference(menu.dateModified, committedAt)
      }
    }

    @Test
    func applyAndClearMenuPrepPlanReplacesSnapshot() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_400_000)
      let modifiedAt = now.addingTimeInterval(60)
      let clearedAt = now.addingTimeInterval(120)
      let menuID = SampleUUIDSequence.uuid(15_200)
      let sourceDishID = SampleUUIDSequence.uuid(15_201)

      try database.write { db in
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Prep Menu",
            dayCount: 2,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        try MenuRepository.applyPrepPlan(
          MenuPrepPlan(
            steps: [
              PrepPlanStep(
                when: "2 days out",
                task: "Make the sauce.",
                sourceDish: sourceDishID
              )
            ]
          ),
          to: menuID,
          in: db,
          now: modifiedAt
        )
      }

      try database.read { db in
        let menu = try #require(try Menu.find(menuID).fetchOne(db))
        expectNoDifference(
          MenuPrepPlanCoding.decode(menu.prepPlan),
          [
            PrepPlanStep(
              when: "2 days out",
              task: "Make the sauce.",
              sourceDish: sourceDishID
            )
          ]
        )
        expectNoDifference(menu.dateModified, modifiedAt)
      }

      try database.write { db in
        try MenuRepository.clearPrepPlan(menuID: menuID, in: db, now: clearedAt)
      }

      try database.read { db in
        let menu = try #require(try Menu.find(menuID).fetchOne(db))
        expectNoDifference(menu.prepPlan, nil)
        expectNoDifference(menu.dateModified, clearedAt)
      }
    }
  }
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
