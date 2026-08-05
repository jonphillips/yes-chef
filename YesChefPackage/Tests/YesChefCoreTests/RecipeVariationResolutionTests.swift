import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeVariationResolutionTests {
    @Test
    func unresolvedAnchorsPreserveResolvableChangesAndMarkTheGrocerySourceForRepair() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_275_000)
      let recipeID = SampleUUIDSequence.uuid(32_451)
      let sectionID = SampleUUIDSequence.uuid(32_452)
      let lemonID = SampleUUIDSequence.uuid(32_453)
      let variationID = SampleUUIDSequence.uuid(32_454)
      let activeVariationID = SampleUUIDSequence.uuid(32_455)
      let variationPayload = try RecipeVariationPayload(
        ingredientOps: [
          .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
          .remove(
            RecipeIngredientReference(
              id: SampleUUIDSequence.uuid(32_456),
              originalText: "1 teaspoon stale juice"
            )
          ),
        ],
        methodStepReplacements: []
      )
      .encodedData()
      var uuids = SampleUUIDSequence(start: 32_550)

      let groceryListID = try database.write { db in
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
            item: "lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: recipeID,
            name: "Lime",
            sortIndex: 0,
            deltas: variationPayload,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try RecipeActiveVariation.insert {
          RecipeActiveVariation(
            id: activeVariationID,
            recipeID: recipeID,
            variationID: variationID,
            dateModified: now
          )
        }
        .execute(db)

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
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let variation = try #require(detail.activeVariation)
        let resolution = try detail.resolved(applying: variation)
        expectNoDifference(resolution.detail.ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
        expectNoDifference(resolution.unresolvedAnchors, [.ingredient("1 teaspoon stale juice")])

        let rows = try GroceryItemListRequest().fetch(db)
          .filter { $0.item.groceryListID == groceryListID }
        expectNoDifference(rows.map(\.item.title), ["lime juice"])
        expectNoDifference(
          rows.flatMap(\.sources).compactMap(\.sourceSubtitle),
          ["Variation: Lime (needs repair)"]
        )
      }
    }
  }
}
