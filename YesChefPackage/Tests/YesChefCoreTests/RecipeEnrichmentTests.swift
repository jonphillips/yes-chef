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
    func replacingServeWithPlanPreservesModelIdentityAndHandAuthoredRows() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 826_000_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(36_410)
      let limeCremaID = SampleUUIDSequence.uuid(36_411)
      let handAuthoredID = SampleUUIDSequence.uuid(36_412)
      let cabbageSlawID = SampleUUIDSequence.uuid(36_413)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Chili",
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        for row in [
          RecipeServeWith(
            id: limeCremaID, recipeID: recipeID, title: "Lime crema", note: "Spoon over each bowl.",
            sortOrder: 0, provenance: .model, dateCreated: createdAt, dateModified: createdAt
          ),
          RecipeServeWith(
            id: handAuthoredID, recipeID: recipeID, title: "Pickled onions",
            sortOrder: LearningOrdering.rankStride, provenance: .handAuthored,
            dateCreated: createdAt, dateModified: createdAt
          ),
        ] {
          try RecipeServeWith.insert { row }.execute(db)
        }

        try RecipeRepository.replaceServeWithPlan(
          ServeWithPlan(items: [
            ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithSuggestion(title: "Cabbage slaw"),
          ]),
          recipeID: recipeID,
          in: db,
          now: updatedAt,
          uuid: { cabbageSlawID }
        )
      }

      try database.read { db in
        expectNoDifference(
          try RecipeServeWithRepository.serveWith(for: recipeID, in: db),
          [
            RecipeServeWith(
              id: limeCremaID, recipeID: recipeID, title: "Lime crema", note: "Spoon over each bowl.",
              sortOrder: 0, provenance: .model, dateCreated: createdAt, dateModified: createdAt
            ),
            RecipeServeWith(
              id: handAuthoredID, recipeID: recipeID, title: "Pickled onions",
              sortOrder: LearningOrdering.rankStride, provenance: .handAuthored,
              dateCreated: createdAt, dateModified: createdAt
            ),
            RecipeServeWith(
              id: cabbageSlawID, recipeID: recipeID, title: "Cabbage slaw",
              sortOrder: LearningOrdering.rankStride * 2, provenance: .model,
              dateCreated: updatedAt, dateModified: updatedAt
            ),
          ]
        )
      }
    }

    @Test
    func editingAndReorderingServeWithPreservesRowIdentity() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 826_000_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(36_400)
      let firstID = SampleUUIDSequence.uuid(36_401)
      let secondID = SampleUUIDSequence.uuid(36_402)
      let thirdID = SampleUUIDSequence.uuid(36_403)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Chili",
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        for (id, title, sortOrder) in [
          (firstID, "Lime crema", 0),
          (secondID, "Cornbread", LearningOrdering.rankStride),
          (thirdID, "Cabbage slaw", LearningOrdering.rankStride * 2),
        ] {
          try RecipeServeWith.insert {
            RecipeServeWith(
              id: id, recipeID: recipeID, title: title, sortOrder: sortOrder,
              provenance: .model, dateCreated: createdAt, dateModified: createdAt
            )
          }
          .execute(db)
        }
        try RecipeServeWithRepository.update(id: firstID, title: "Charred lime crema", in: db, now: updatedAt)
        _ = try RecipeServeWithRepository.reorder(
          movingIDs: [thirdID], destination: .before(secondID), for: recipeID, in: db, now: updatedAt
        )
      }

      try database.read { db in
        expectNoDifference(
          try RecipeServeWithRepository.serveWith(for: recipeID, in: db),
          [
            RecipeServeWith(
              id: firstID, recipeID: recipeID, title: "Charred lime crema", sortOrder: 0,
              provenance: .model, dateCreated: createdAt, dateModified: updatedAt
            ),
            RecipeServeWith(
              id: thirdID, recipeID: recipeID, title: "Cabbage slaw", sortOrder: LearningOrdering.rankStride / 2,
              provenance: .model, dateCreated: createdAt, dateModified: updatedAt
            ),
            RecipeServeWith(
              id: secondID, recipeID: recipeID, title: "Cornbread", sortOrder: LearningOrdering.rankStride,
              provenance: .model, dateCreated: createdAt, dateModified: createdAt
            ),
          ]
        )
      }
    }

    @Test
    func recipeChatContextUsesServeWithRows() throws {
      let now = Date(timeIntervalSinceReferenceDate: 826_200_000)
      let recipeDetail = RecipeDetailData(
        recipe: Recipe(
          id: SampleUUIDSequence.uuid(36_510),
          title: "Chili",
          dateCreated: now,
          dateModified: now
        ),
        serveWith: [
          RecipeServeWith(
            id: SampleUUIDSequence.uuid(36_511), recipeID: SampleUUIDSequence.uuid(36_510), title: "Cornbread",
            sortOrder: 0, provenance: .model, dateCreated: now, dateModified: now
          )
        ]
      )
      expectNoDifference(try RecipeChatRecipeContext(detail: recipeDetail).serveWith.map(\.title), ["Cornbread"])
    }

    @Test
    func absentServeWithDataIsAnEmptyList() throws {
      expectNoDifference(try ServeWithCoding.decode(nil, recipeID: SampleUUIDSequence.uuid(36_511)), [])
    }
  }
}
