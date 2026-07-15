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
    func menuPrepPlanParsesAndCodesWorkSessionSteps() throws {
      let sourceDishID = SampleUUIDSequence.uuid(15_000)

      let plan = MenuPrepPlanClient.parse(
        """
        {"steps":[
          {
            "session":"Wednesday evening",
            "task":"Make the barbecue sauce.",
            "serves":"Thursday dinner",
            "sourceDish":"\(sourceDishID.uuidString)"
          },
          {
            "session":"Anytime, get ahead",
            "task":"Set out serving platters.",
            "serves":null,
            "sourceDish":null
          },
          {
            "session":"Later",
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
              session: "Wednesday evening",
              task: "Make the barbecue sauce.",
              serves: "Thursday dinner",
              sourceDish: sourceDishID
            ),
            PrepPlanStep(
              session: "Anytime, get ahead",
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
    func menuPrepPlanDecodesLegacyWhenSteps() {
      let sourceDishID = SampleUUIDSequence.uuid(15_120)
      let legacyData = Data(
        """
        [{"when":"Day before","task":"Marinate the chicken.","sourceDish":"\(sourceDishID.uuidString)"}]
        """.utf8
      )

      expectNoDifference(
        MenuPrepPlanCoding.decode(legacyData),
        [
          PrepPlanStep(
            session: "Day before",
            task: "Marinate the chicken.",
            sourceDish: sourceDishID
          )
        ]
      )
    }

    @Test
    func menuPrepPlanParsesLegacyWhenModelResponse() {
      let sourceDishID = SampleUUIDSequence.uuid(15_121)

      expectNoDifference(
        MenuPrepPlanClient.parse(
          """
          {"steps":[
            {
              "when":"Thursday evening",
              "task":"Salt the pork.",
              "serves":"Friday dinner",
              "sourceDish":"\(sourceDishID.uuidString)"
            }
          ]}
          """
        ),
        MenuPrepPlan(
          steps: [
            PrepPlanStep(
              session: "Thursday evening",
              task: "Salt the pork.",
              serves: "Friday dinner",
              sourceDish: sourceDishID
            )
          ]
        )
      )
    }

    @Test
    func menuPrepPlanHeaderLineRoundTripDoesNotReattachSourceDishByTaskText() {
      let sourceDishID = SampleUUIDSequence.uuid(15_120)
      let plan = MenuPrepPlan(
        steps: [
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Marinate the chicken.",
            serves: "Thursday dinner",
            sourceDish: sourceDishID
          ),
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Chop the herbs.",
            serves: "Thursday dinner",
            sourceDish: sourceDishID
          ),
          PrepPlanStep(
            session: "At service",
            task: "Warm the tortillas."
          ),
        ]
      )

      expectNoDifference(
        plan.editableReviewText(),
        """
        Wednesday evening:
        - Marinate the chicken. → Thursday dinner
        - Chop the herbs. → Thursday dinner
        At service:
        - Warm the tortillas.
        """
      )

      expectNoDifference(
        plan.applyingEditableReviewText(plan.editableReviewText()),
        MenuPrepPlan(
          steps: [
            PrepPlanStep(
              session: "Wednesday evening",
              task: "Marinate the chicken.",
              serves: "Thursday dinner"
            ),
            PrepPlanStep(
              session: "Wednesday evening",
              task: "Chop the herbs.",
              serves: "Thursday dinner"
            ),
            PrepPlanStep(session: "At service", task: "Warm the tortillas."),
          ]
        )
      )

      let edited = plan.applyingEditableReviewText(
        """
        Wednesday evening:
        - Marinate the chicken. → Thursday dinner
        - Chop herbs and scallions. → Thursday dinner
        """
      )

      expectNoDifference(
        edited.steps,
        [
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Marinate the chicken.",
            serves: "Thursday dinner"
          ),
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Chop herbs and scallions.",
            serves: "Thursday dinner"
          ),
        ]
      )
    }

    @Test
    func menuPrepPlanAcceptsLiteralSessionHeaders() {
      let plan = MenuPrepPlan().applyingEditableReviewText(
        """
        Session: Wednesday evening
        - Salt the chicken → Thursday dinner
        """
      )

      expectNoDifference(
        plan.steps,
        [
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Salt the chicken",
            serves: "Thursday dinner"
          )
        ]
      )
    }

    @Test
    func menuPrepPlanAcceptsASCIIArrowFromExternalPaste() {
      let plan = MenuPrepPlan().applyingEditableReviewText(
        """
        Wednesday evening:
        - Salt the chicken -> Thursday dinner
        """
      )

      expectNoDifference(
        plan.steps,
        [
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Salt the chicken",
            serves: "Thursday dinner"
          )
        ]
      )
    }

    @Test
    func menuPrepPlanReportsEveryUnparsedInboundLine() {
      let parsed = MenuPrepPlan().parsingEditableReviewText(
        """
        - This bullet has no session.
        Wednesday evening:
        - → Missing task
        - Salt the chicken → Thursday dinner
        """
      )

      expectNoDifference(
        parsed.plan.steps,
        [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
      )
      expectNoDifference(
        parsed.unparsedLines,
        ["- This bullet has no session.", "- → Missing task"]
      )
    }

    @Test
    func legacyFlexibleSessionProseSortsBeforeOtherSessionBands() {
      let sessions = ["The day before", "Anytime this week", "At service"]
      let ordered = sessions.sorted { lhs, rhs in
        PrepPlanSessionBand(matching: lhs) == .flexible
          && PrepPlanSessionBand(matching: rhs) != .flexible
      }

      expectNoDifference(ordered, ["Anytime this week", "The day before", "At service"])
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
      expectNoDifference(request?.reasoningEffort, .high)
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.makeAheadPrepPlan.rawValue)
      #expect(request?.messages.first?.text.contains("Menu context:\nMenu context") == true)
      #expect(request?.messages.first?.text.contains("User-selected subject:\nSequence the prep.") == true)
      #expect(request?.system?.contains("\"session\"") == true)
      #expect(request?.system?.contains("separable, atomic, context-free tasks") == true)
      #expect(request?.system?.contains("Do not generate choreography") == true)
      #expect(request?.system?.contains("The recipes hold the cooking") == true)
      #expect(request?.system?.contains("invent grounded sequencing") == false)
    }

    @Test
    @MainActor
    func stagedMenuPrepPlanReviewItemWritesOnlyWhenCommitted() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_300_000)
      let committedAt = now.addingTimeInterval(60)
      let menuID = SampleUUIDSequence.uuid(15_100)
      let sourceDishID = SampleUUIDSequence.uuid(15_101)
      let stepID = SampleUUIDSequence.uuid(15_102)
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
                session: "Day before",
                task: "Marinate the chicken.",
                sourceDish: sourceDishID
              )
            ]
          )
        },
        commit: { plan in
          try await database.write { db in
            try MenuRepository.applyPrepPlan(
              plan,
              to: menuID,
              in: db,
              now: committedAt,
              uuid: { stepID }
            )
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
      expectNoDifference(items.map(\.summary), ["Day before:\n- Marinate the chicken."])
      try await database.read { db in
        expectNoDifference(try PrepPlanStepRepository.steps(for: menuID, in: db), [])
      }

      try await items[0].commit(items[0].summary)

      try await database.read { db in
        let menu = try #require(try Menu.find(menuID).fetchOne(db))
        expectNoDifference(
          try PrepPlanStepRepository.steps(for: menuID, in: db),
          [
            PrepPlanStepRecord(
              id: stepID,
              menuID: menuID,
              sortOrder: 0,
              session: "Day before",
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
      let stepID = SampleUUIDSequence.uuid(15_202)

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
                session: "2 days out",
                task: "Make the sauce.",
                sourceDish: sourceDishID
              )
            ]
          ),
          to: menuID,
          in: db,
          now: modifiedAt,
          uuid: { stepID }
        )
      }

      try database.read { db in
        let menu = try #require(try Menu.find(menuID).fetchOne(db))
        expectNoDifference(
          try PrepPlanStepRepository.steps(for: menuID, in: db),
          [
            PrepPlanStepRecord(
              id: stepID,
              menuID: menuID,
              sortOrder: 0,
              session: "2 days out",
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
        expectNoDifference(try PrepPlanStepRepository.steps(for: menuID, in: db), [])
        expectNoDifference(menu.dateModified, clearedAt)
      }
    }

    @Test
    func prepPlanRowsKeepStableIDsAndSourceDishWhenReorderedAndEdited() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_500_000)
      let menuID = SampleUUIDSequence.uuid(15_300)
      let firstID = SampleUUIDSequence.uuid(15_301)
      let secondID = SampleUUIDSequence.uuid(15_302)
      let sourceDishID = SampleUUIDSequence.uuid(15_303)

      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Stable IDs", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        var ids = [firstID, secondID].makeIterator()
        try MenuRepository.applyPrepPlan(
          MenuPrepPlan(
            steps: [
              PrepPlanStep(session: "The day before", task: "Salt the chicken", sourceDish: sourceDishID),
              PrepPlanStep(session: "At service", task: "Warm the tortillas"),
            ]
          ),
          to: menuID,
          in: db,
          now: now,
          uuid: { ids.next()! }
        )
        _ = try PrepPlanStepRepository.reorder(id: secondID, direction: .earlier, in: db, now: now)
        try PrepPlanStepRepository.update(
          id: firstID,
          session: "The day before",
          task: "Salt the chicken overnight",
          serves: "Saturday dinner",
          in: db,
          now: now
        )
      }

      try database.read { db in
        expectNoDifference(
          try PrepPlanStepRepository.steps(for: menuID, in: db),
          [
            PrepPlanStepRecord(
              id: secondID,
              menuID: menuID,
              sortOrder: 0,
              session: "At service",
              task: "Warm the tortillas"
            ),
            PrepPlanStepRecord(
              id: firstID,
              menuID: menuID,
              sortOrder: 1,
              session: "The day before",
              task: "Salt the chicken overnight",
              serves: "Saturday dinner",
              sourceDish: sourceDishID
            ),
          ]
        )
      }
    }

    @Test
    func textImportReplacesSourceDishLinksInsteadOfMatchingThemByTaskText() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_600_000)
      let menuID = SampleUUIDSequence.uuid(15_400)
      let linkedStepID = SampleUUIDSequence.uuid(15_401)
      let textImportStepID = SampleUUIDSequence.uuid(15_402)
      let sourceDishID = SampleUUIDSequence.uuid(15_403)

      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Source Links", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try MenuRepository.applyPrepPlan(
          MenuPrepPlan(
            steps: [
              PrepPlanStep(
                session: "The day before",
                task: "Salt the chicken",
                sourceDish: sourceDishID
              )
            ]
          ),
          to: menuID,
          in: db,
          now: now,
          uuid: { linkedStepID }
        )
        let pastedPlan = MenuPrepPlan().applyingEditableReviewText(
          """
          The day before:
          - Salt the chicken
          """
        )
        try MenuRepository.applyPrepPlan(
          pastedPlan,
          to: menuID,
          in: db,
          now: now,
          uuid: { textImportStepID }
        )
      }

      try database.read { db in
        expectNoDifference(
          try PrepPlanStepRepository.steps(for: menuID, in: db),
          [
            PrepPlanStepRecord(
              id: textImportStepID,
              menuID: menuID,
              sortOrder: 0,
              session: "The day before",
              task: "Salt the chicken"
            )
          ]
        )
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
