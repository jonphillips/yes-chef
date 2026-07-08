import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeVariationTests {
    @Test
    func keepAsVariationPersistsPayloadSelectsItAndResolvesWithoutChangingBase() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_250_000)
      let recipeID = SampleUUIDSequence.uuid(32_001)
      let sectionID = SampleUUIDSequence.uuid(32_002)
      let lemonID = SampleUUIDSequence.uuid(32_003)
      var uuids = SampleUUIDSequence(start: 32_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lemonID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
      }

      let variation = try database.write { db in
        try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            summary: "Lime version",
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
              .add(line: "1 teaspoon lime zest", sectionName: "Sauce"),
            ],
            methodNote: "Taste before serving."
          ),
          recipeID: recipeID,
          name: "Lime",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let baseDetail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(baseDetail.ingredientLines.map(\.originalText), ["1 tablespoon lemon juice"])
        expectNoDifference(baseDetail.variations.map(\.name), ["Lime"])
        expectNoDifference(baseDetail.activeVariationID, variation.id)
        expectNoDifference(baseDetail.activeVariation?.note, "Taste before serving.")

        let resolved = try baseDetail.resolved(applying: variation)
        expectNoDifference(resolved.ingredientLines.map(\.originalText), [
          "2 tablespoons lime juice",
          "1 teaspoon lime zest",
        ])
        let highlights = try baseDetail.variationIngredientHighlights(for: variation)
        expectNoDifference(highlights[lemonID], .changed)
        #expect(highlights.values.contains(.added))
      }
    }

    @Test
    func variationNeedsReviewErrorUsesUserFacingDescription() {
      let error = RecipeAdjustmentError.variationNeedsReview(
        "Smoky",
        "The adjustment references an ingredient that could not be matched: 1 teaspoon paprika"
      )

      expectNoDifference(
        error.localizedDescription,
        "\"Smoky\" needs review before this recipe can be overwritten: The adjustment references an ingredient that could not be matched: 1 teaspoon paprika"
      )
      #expect(String(describing: error) != error.localizedDescription)
    }

    @Test
    func addedIngredientHighlightUsesResolvedLineIDWhenRecipeHasNoIngredientSections() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_255_000)
      let recipeID = SampleUUIDSequence.uuid(32_601)
      let variationID = SampleUUIDSequence.uuid(32_602)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Lime Rice", dateCreated: now, dateModified: now)
      )
      let variation = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Zesty",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [
            .add(line: "1 teaspoon lime zest", sectionName: nil)
          ],
          methodStepReplacements: []
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      let resolved = try detail.resolved(applying: variation)
      let addedLine = try #require(resolved.ingredientLines.first)
      let highlights = try detail.variationIngredientHighlights(for: variation)

      expectNoDifference(resolved.ingredientSections.count, 1)
      expectNoDifference(addedLine.originalText, "1 teaspoon lime zest")
      expectNoDifference(highlights[addedLine.id], RecipeVariationIngredientHighlight?.some(.added))
    }

    @Test
    func addedIngredientHighlightUsesResolvedLineIDWhenAddTextContainsNewline() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_256_000)
      let recipeID = SampleUUIDSequence.uuid(32_611)
      let variationID = SampleUUIDSequence.uuid(32_612)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Lime Rice", dateCreated: now, dateModified: now)
      )
      let variation = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Extra Lime",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [
            .add(line: "1 teaspoon lime zest\n1 tablespoon lime juice", sectionName: nil)
          ],
          methodStepReplacements: []
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      let resolved = try detail.resolved(applying: variation)
      let addedLine = try #require(resolved.ingredientLines.first)
      let highlights = try detail.variationIngredientHighlights(for: variation)

      expectNoDifference(resolved.ingredientSections.count, 1)
      expectNoDifference(addedLine.originalText, "1 teaspoon lime zest")
      expectNoDifference(highlights[addedLine.id], RecipeVariationIngredientHighlight?.some(.added))
    }

    @Test
    func overwriteBlocksWhenExistingVariationNoLongerResolvesAgainstProposedBase() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_260_000)
      let recipeID = SampleUUIDSequence.uuid(32_201)
      let sectionID = SampleUUIDSequence.uuid(32_202)
      let paprikaID = SampleUUIDSequence.uuid(32_203)
      var uuids = SampleUUIDSequence(start: 32_300)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Stew", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: paprikaID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 teaspoon paprika",
            sortOrder: 0
          )
        }
        .execute(db)
        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: paprikaID), line: "1 teaspoon smoked paprika")
            ]
          ),
          recipeID: recipeID,
          name: "Smoky",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      try database.write { db in
        #expect(throws: RecipeAdjustmentError.self) {
          try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
            RecipeAdjustmentProposal(
              ingredientOps: [
                .remove(RecipeIngredientReference(id: paprikaID))
              ]
            ),
            recipeID: recipeID,
            in: db,
            now: now.addingTimeInterval(60),
            uuid: { uuids.next() }
          )
        }
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.ingredientLines.map(\.originalText), ["1 teaspoon paprika"])
      }
    }

    @Test
    func groceryGenerationUsesActiveVariationFold() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_270_000)
      let recipeID = SampleUUIDSequence.uuid(32_401)
      let sectionID = SampleUUIDSequence.uuid(32_402)
      let lemonID = SampleUUIDSequence.uuid(32_403)
      var uuids = SampleUUIDSequence(start: 32_500)

      let listID = try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lemonID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            quantity: 1,
            quantityText: "1",
            unit: "tablespoon",
            item: "lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
              .add(line: "1 teaspoon lime zest", sectionName: "Sauce"),
            ]
          ),
          recipeID: recipeID,
          name: "Lime",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        return listID
      }

      try database.read { db in
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { $0.item.groceryListID == listID }
        expectNoDifference(rows.map(\.item.title), ["lime juice", "lime zest"])
        expectNoDifference(
          rows.flatMap(\.sources).compactMap(\.sourceSubtitle).sorted(),
          ["Variation: Lime", "Variation: Lime"]
        )
      }
    }
  }
}
