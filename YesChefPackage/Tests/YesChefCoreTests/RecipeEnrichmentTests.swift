import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeEnrichmentTests {
    @Test
    func playbookEnrichmentTextNormalizesPastedBullets() {
      let display = PlaybookEnrichmentText.displayText(for: """
      - Make the sauce.
      * Toast the spices.
      • Cool before storing.
      – Reheat gently.
      """)

      expectNoDifference(
        display,
        PlaybookEnrichmentDisplayText(
          text: """
          • Make the sauce.
          • Toast the spices.
          • Cool before storing.
          • Reheat gently.
          """,
          hasBulletedLines: true
        )
      )
    }

    @Test
    func playbookEnrichmentTextLeavesSingleLineParagraphsAsProse() {
      let display = PlaybookEnrichmentText.displayText(for: """
      Make this the day before.

      Chill completely.
      Reheat gently.
      """)

      expectNoDifference(
        display,
        PlaybookEnrichmentDisplayText(
          text: """
          Make this the day before.

          • Chill completely.
          • Reheat gently.
          """,
          hasBulletedLines: true
        )
      )
      expectNoDifference(
        PlaybookEnrichmentText.displayText(for: "A single line of prose."),
        PlaybookEnrichmentDisplayText(text: "A single line of prose.", hasBulletedLines: false)
      )
    }

    @Test
    func playbookEnrichmentTextBulletsPlainMultilineText() {
      expectNoDifference(
        PlaybookEnrichmentText.displayText(for: "Salt the chicken.\nRoast until browned."),
        PlaybookEnrichmentDisplayText(
          text: "• Salt the chicken.\n• Roast until browned.",
          hasBulletedLines: true
        )
      )
    }

    @Test
    func serveWithUnionPrefillPreservesExistingRowsAndDeduplicatesExactReturn() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 826_000_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(36_410)
      let limeCremaID = SampleUUIDSequence.uuid(36_411)
      let cornbreadID = SampleUUIDSequence.uuid(36_412)
      let cabbageSlawID = SampleUUIDSequence.uuid(36_413)
      let existingItems = [
        ServeWithItem(id: limeCremaID, title: "Lime crema", note: "Spoon over each bowl."),
        ServeWithItem(id: cornbreadID, title: "Skillet cornbread"),
      ]
      let existingPlan = ServeWithPlan(
        items: existingItems.map { ServeWithSuggestion(title: $0.title, note: $0.note) }
      )
      let existingData = try ServeWithCoding.encode(existingItems)
      let prefilledPlan = existingPlan.unioning(
        ServeWithPlan(
          items: [
            ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithSuggestion(title: "Cabbage slaw"),
          ]
        )
      )

      expectNoDifference(
        prefilledPlan,
        ServeWithPlan(
          items: [
            ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithSuggestion(title: "Skillet cornbread"),
            ServeWithSuggestion(title: "Cabbage slaw"),
          ]
        )
      )

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Chili",
            dateCreated: createdAt,
            dateModified: createdAt,
            serveWith: existingData
          )
        }
        .execute(db)

        try RecipeRepository.replaceServeWithPlan(
          prefilledPlan,
          recipeID: recipeID,
          in: db,
          now: updatedAt,
          uuid: { cabbageSlawID }
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(
          ServeWithCoding.decode(recipe.serveWith),
          [
            ServeWithItem(id: limeCremaID, title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithItem(id: cornbreadID, title: "Skillet cornbread"),
            ServeWithItem(id: cabbageSlawID, title: "Cabbage slaw"),
          ]
        )
      }
    }

    @Test
    func replacingServeWithPlanPreservesUnchangedItemIDs() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 826_000_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(36_400)
      let unchangedItemID = SampleUUIDSequence.uuid(36_401)
      let removedItemID = SampleUUIDSequence.uuid(36_402)
      let addedItemID = SampleUUIDSequence.uuid(36_403)

      try database.write { db in
        let existingItems = [
          ServeWithItem(id: unchangedItemID, title: "Lime crema", note: "Spoon over each bowl."),
          ServeWithItem(id: removedItemID, title: "Skillet cornbread"),
        ]
        let existingData = try ServeWithCoding.encode(existingItems)
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Chili",
            dateCreated: createdAt,
            dateModified: createdAt,
            serveWith: existingData
          )
        }
        .execute(db)

        try RecipeRepository.replaceServeWithPlan(
          ServeWithPlan(
            items: [
              ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
              ServeWithSuggestion(title: "Cabbage slaw"),
            ]
          ),
          recipeID: recipeID,
          in: db,
          now: updatedAt,
          uuid: { addedItemID }
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(
          ServeWithCoding.decode(recipe.serveWith),
          [
            ServeWithItem(id: unchangedItemID, title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithItem(id: addedItemID, title: "Cabbage slaw"),
          ]
        )
        expectNoDifference(recipe.dateModified, updatedAt)
      }
    }
  }
}
