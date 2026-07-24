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
      #expect(try MenuItem.fetchAll(db).isEmpty)
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
        Salt and drain the cucumbers before dressing them.
        Use two garlic cloves for a more pronounced flavor.
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
      #expect(try Learning.fetchAll(db).isEmpty)
      #expect(try AIHandoffRepository.handoff(id: handoffID, in: db)?.status == .imported)
    }
  }
}
