import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct AIHandoffAdvisoryTests {
  @Test
  func readerFeedbackReturnAcceptsOnlyLabeledTips() {
    let returned = AIHandoffReturn.readerFeedbackReturn(
      from: """
      Here are the useful changes:
      Tip: Salt and drain the cucumbers before dressing them.
      ## More ideas
      Tip: Use two garlic cloves for a more pronounced flavor.
      Tip: use two garlic cloves for a more pronounced flavor.
      """
    )

    expectNoDifference(
      returned.tips.map(\.text),
      [
        "Salt and drain the cucumbers before dressing them.",
        "Use two garlic cloves for a more pronounced flavor.",
      ]
    )
    expectNoDifference(returned.unparsedLines, ["Here are the useful changes:", "## More ideas"])
  }

  @Test
  func menuComplementHandoffStagesDistinctReviewedSuggestionsWithoutWriting() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_050)
    let handoffID = SampleUUIDSequence.uuid(38_051)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Menu.insert {
        Menu(id: menuID, title: "Beach Menu", dayCount: 2, dateCreated: now, dateModified: now)
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .menu,
          sourceID: menuID,
          taskType: .menuComplement,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        I found two concrete suggestions:
        Note: Cucumber herb salad
        Day 1 - Dinner
        Cucumber, dill, and lemon.
        Note: Charred peaches
        Day 2 - Snack
        """,
        in: db,
        now: now
      )

      guard case let .menuComplement(complementReview) = review else {
        Issue.record("Expected a menu-complement review.")
        return
      }
      expectNoDifference(
        complementReview.plan.items,
        [
          MenuComplementSuggestion(
            title: "Cucumber herb salad",
            body: "Cucumber, dill, and lemon.",
            dayOffset: 0,
            mealSlot: .dinner
          ),
          MenuComplementSuggestion(title: "Charred peaches", dayOffset: 1, mealSlot: .snack),
        ]
      )
      expectNoDifference(complementReview.unparsedBlocks, ["I found two concrete suggestions:"])
      #expect(try MenuItem.fetchAll(db).isEmpty)
    }
  }

  @Test
  func regeneratingPrepPlanStagesACleanReplacementInsteadOfOmissionEvidence() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_054)
    let handoffID = SampleUUIDSequence.uuid(38_055)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Menu.insert {
        Menu(id: menuID, title: "Beach Menu", dayCount: 2, dateCreated: now, dateModified: now)
      }
      .execute(db)
      try PrepPlanStepRecord.insert {
        PrepPlanStepRecord(
          id: SampleUUIDSequence.uuid(38_056),
          menuID: menuID,
          sortOrder: 0,
          session: "Friday",
          task: "Salt the chicken",
          sourceDish: SampleUUIDSequence.uuid(38_057)
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .menu,
          sourceID: menuID,
          taskType: .prepPlan,
          createdAt: now,
          regenerates: true,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageMenuPrepPlanReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Sunday morning:
        - Make the salsa → Sunday dinner
        """,
        in: db,
        now: now
      )

      expectNoDifference(review.advisoryNotes, [])
      expectNoDifference(review.prepPlanIntent, .regenerate)
      expectNoDifference(review.replacementStepCount, 1)
      #expect(try AIHandoffRepository.handoff(id: handoffID, in: db)?.prepPlanIntent == .regenerate)
    }
  }

  @Test
  func refiningPrepPlanStillSurfacesDroppedSteps() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_058)
    let handoffID = SampleUUIDSequence.uuid(38_059)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Menu.insert {
        Menu(id: menuID, title: "Beach Menu", dayCount: 2, dateCreated: now, dateModified: now)
      }
      .execute(db)
      try PrepPlanStepRecord.insert {
        PrepPlanStepRecord(
          id: SampleUUIDSequence.uuid(38_060),
          menuID: menuID,
          sortOrder: 0,
          session: "Friday",
          task: "Salt the chicken"
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .menu,
          sourceID: menuID,
          taskType: .prepPlan,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageMenuPrepPlanReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Sunday morning:
        - Make the salsa → Sunday dinner
        """,
        in: db,
        now: now
      )

      expectNoDifference(
        review.advisoryNotes,
        ["Existing prep step missing from returned plan: Friday: Salt the chicken"]
      )
      expectNoDifference(review.prepPlanIntent, .refine)
    }
  }

  @Test
  func readerFeedbackCaptureHandoffStagesTipsBackToTheDraftWithoutALearning() throws {
    @Dependency(\.defaultDatabase) var database
    let handoffID = SampleUUIDSequence.uuid(38_052)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .capture,
          sourceID: handoffID,
          taskType: .readerFeedbackCuration,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )
      let review = try AIHandoffIntentImport.stageReaderFeedbackReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        \(AIHandoffReturnContract.marker)
        Tip: Salt and drain the cucumbers before dressing them.
        These were the strongest returns:
        Tip: Use two garlic cloves for a more pronounced flavor.
        """,
        in: db,
        now: now
      )

      expectNoDifference(
        review.tips.map(\.text),
        [
          "Salt and drain the cucumbers before dressing them.",
          "Use two garlic cloves for a more pronounced flavor.",
        ]
      )
      expectNoDifference(review.unparsedLines, ["These were the strongest returns:"])
      #expect(try Learning.fetchAll(db).isEmpty)
      #expect(try AIHandoffRepository.handoff(id: handoffID, in: db)?.status == .imported)
    }
  }

  @Test
  func readerFeedbackCaptureHandoffAcceptsTheCopiedPromptJSONReturn() throws {
    @Dependency(\.defaultDatabase) var database
    let handoffID = SampleUUIDSequence.uuid(38_070)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    let comments = [
      RawComment(text: "A lower rack browned the bottom well.", helpfulCount: 9),
      RawComment(text: "Another vote for the lower rack.", helpfulCount: 4),
    ]

    try database.write { db in
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .capture,
          sourceID: handoffID,
          taskType: .readerFeedbackCuration,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageReaderFeedbackReview(
        handoffID: handoffID,
        result: """
        [
          {
            "text": "Bake on the lower rack for a well-browned bottom.",
            "kind": "consensusDistilled",
            "supportCount": 2,
            "commentNumbers": [1, 2]
          }
        ]
        """,
        comments: comments,
        in: db,
        now: now
      )

      expectNoDifference(
        review.tips,
        [
          ReaderFeedbackTip(
            text: "Bake on the lower rack for a well-browned bottom.",
            provenanceKind: .consensusDistilled,
            supportCount: 2,
            backingComments: [
              ReaderFeedbackBackingComment(
                commentNumber: 1,
                text: "A lower rack browned the bottom well.",
                helpfulCount: 9
              ),
              ReaderFeedbackBackingComment(
                commentNumber: 2,
                text: "Another vote for the lower rack.",
                helpfulCount: 4
              ),
            ]
          )
        ]
      )
      #expect(try AIHandoffRepository.handoff(id: handoffID, in: db)?.status == .imported)
    }
  }

  @Test
  func readerFeedbackCaptureHandoffExplainsUnlabeledReturns() throws {
    @Dependency(\.defaultDatabase) var database
    let handoffID = SampleUUIDSequence.uuid(38_053)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .capture,
          sourceID: handoffID,
          taskType: .readerFeedbackCuration,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      #expect(throws: AIHandoffIntentImportError.unparsedReaderFeedbackLines([
        "Salt and drain the cucumbers before dressing them.",
      ])) {
        try AIHandoffIntentImport.stageReaderFeedbackReview(
          handoffID: handoffID,
          result: """
          YC-HANDOFF: \(handoffID.uuidString)
          \(AIHandoffReturnContract.marker)
          Salt and drain the cucumbers before dressing them.
          """,
          in: db,
          now: now
        )
      }
    }
  }
}
