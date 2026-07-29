import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeEnrichmentTests {
    @Test
    func chefItUpClientFailsLoudlyWhenAStrictResponseIsTruncated() async {
      await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(text: #"{\"text\":\""#, stopReason: "length")
        }
      } operation: {
        await #expect(throws: StructuredModelResponseError.responseTruncated) {
          _ = try await ChefItUpPlanClient.liveValue(
            selection: "Make it special.",
            messages: [],
            context: "Recipe context",
            tier: .frontier(.openai)
          )
        }
      }
    }

    @Test
    func serveWithClientFailsLoudlyWhenAStrictResponseIsTruncated() async {
      await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(text: #"{\"items\":["#, stopReason: "length")
        }
      } operation: {
        await #expect(throws: StructuredModelResponseError.responseTruncated) {
          _ = try await ServeWithPlanClient.liveValue(
            selection: "Suggest sides.",
            messages: [],
            context: "Recipe context",
            tier: .frontier(.openai)
          )
        }
      }
    }

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
          try ServeWithCoding.decode(recipe.serveWith, recipeID: recipeID),
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
          try ServeWithCoding.decode(recipe.serveWith, recipeID: recipeID),
          [
            ServeWithItem(id: unchangedItemID, title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithItem(id: addedItemID, title: "Cabbage slaw"),
          ]
        )
        expectNoDifference(recipe.dateModified, updatedAt)
      }
    }

    @Test
    func corruptServeWithDataFailsLoudlyAndCannotBeOverwritten() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 826_100_000)
      let repairedAt = createdAt.addingTimeInterval(150)
      let clearedAt = createdAt.addingTimeInterval(180)
      let recipeID = SampleUUIDSequence.uuid(36_500)
      let itemID = SampleUUIDSequence.uuid(36_501)
      let corruptData = Data("not Serve With JSON".utf8)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Chili",
            dateCreated: createdAt,
            dateModified: createdAt,
            serveWith: corruptData
          )
        }
        .execute(db)

        #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeID)) {
          _ = try ServeWithCoding.decode(corruptData, recipeID: recipeID)
        }
        #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeID)) {
          try RecipeRepository.appendServeWithPlan(
            ServeWithPlan(items: [ServeWithSuggestion(title: "Cornbread")]),
            to: recipeID,
            in: db,
            now: createdAt.addingTimeInterval(30),
            uuid: { itemID }
          )
        }
        #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeID)) {
          try RecipeRepository.replaceServeWithPlan(
            ServeWithPlan(items: [ServeWithSuggestion(title: "Cornbread")]),
            recipeID: recipeID,
            in: db,
            now: createdAt.addingTimeInterval(60),
            uuid: { itemID }
          )
        }
        #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeID)) {
          try RecipeRepository.removeServeWithItem(
            itemID,
            recipeID: recipeID,
            in: db,
            now: createdAt.addingTimeInterval(120)
          )
        }
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.serveWith, corruptData)
        expectNoDifference(recipe.dateModified, createdAt)
      }

      _ = try database.write { db in
        #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeID)) {
          try RecipeRepository.repairServeWith(corruptData, recipeID: recipeID, in: db, now: repairedAt)
        }
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.serveWith, corruptData)
        expectNoDifference(recipe.dateModified, createdAt)
      }

      let repairedData = try #require(try ServeWithCoding.encode([
        ServeWithItem(id: itemID, title: "Cornbread")
      ]))
      try database.write { db in
        try RecipeRepository.repairServeWith(repairedData, recipeID: recipeID, in: db, now: repairedAt)
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.serveWith, repairedData)
        expectNoDifference(recipe.dateModified, repairedAt)
      }

      try database.write { db in
        try RecipeRepository.clearServeWith(recipeID: recipeID, in: db, now: clearedAt)
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.serveWith, nil)
        expectNoDifference(recipe.dateModified, clearedAt)
      }
    }

    @Test
    func corruptServeWithDataPreventsRecipeChatAndHandoffContexts() throws {
      let now = Date(timeIntervalSinceReferenceDate: 826_200_000)
      let recipeDetail = RecipeDetailData(
        recipe: Recipe(
          id: SampleUUIDSequence.uuid(36_510),
          title: "Chili",
          dateCreated: now,
          dateModified: now,
          serveWith: Data("not Serve With JSON".utf8)
        )
      )

      #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeDetail.recipe.id)) {
        _ = try RecipeChatRecipeContext(detail: recipeDetail)
      }
      #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeDetail.recipe.id)) {
        _ = try RecipeHandoffContext(detail: recipeDetail)
      }

      let workbenchID = SampleUUIDSequence.uuid(36_520)
      let workbenchDetail = WorkbenchDetailData(
        workbench: Workbench(
          id: workbenchID,
          title: "Chili comparison",
          sortOrder: 0,
          dateCreated: now,
          dateModified: now
        ),
        candidateRows: [
          WorkbenchCandidateRowData(
            candidate: WorkbenchCandidate(
              id: SampleUUIDSequence.uuid(36_521),
              workbenchID: workbenchID,
              recipeID: recipeDetail.recipe.id,
              recipeTitleSnapshot: recipeDetail.recipe.title,
              sortOrder: 0,
              dateCreated: now
            ),
            recipeDetail: recipeDetail
          )
        ]
      )
      #expect(throws: ServeWithCodingError.malformedData(recipeID: recipeDetail.recipe.id)) {
        _ = try WorkbenchChatContext(detail: workbenchDetail, references: [])
      }
    }

    @Test
    func absentServeWithDataIsAnEmptyList() throws {
      expectNoDifference(try ServeWithCoding.decode(nil, recipeID: SampleUUIDSequence.uuid(36_511)), [])
    }
  }
}
