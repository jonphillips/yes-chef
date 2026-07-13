import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryScalingTests {
    @Test
    func recipeScaleScalesParsedGroceryQuantitiesAndPreservesFreeText() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_280_000)
      let recipeID = SampleUUIDSequence.uuid(18_001)
      let sectionID = SampleUUIDSequence.uuid(18_002)
      var uuids = SampleUUIDSequence(start: 18_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Scaled Soup",
          lines: [
            IngredientLine(
              id: SampleUUIDSequence.uuid(18_003),
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "1½ cups stock",
              quantity: 1.5,
              quantityText: "1½",
              unit: "cups",
              item: "stock",
              sortOrder: 0,
              confidence: .medium
            ),
            IngredientLine(
              id: SampleUUIDSequence.uuid(18_004),
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "salt to taste",
              quantityText: "to taste",
              item: "salt",
              sortOrder: 1,
              confidence: .low
            ),
          ],
          now: now,
          in: db,
          viewScale: 2
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let rows = try GroceryItemListRequest().fetch(db)
        let stock = try #require(rows.first { $0.item.title == "stock" })
        let salt = try #require(rows.first { $0.item.title == "salt" })
        expectNoDifference(stock.item.quantity, 3)
        expectNoDifference(stock.item.quantityText, "3")
        expectNoDifference(salt.item.quantity, nil)
        expectNoDifference(salt.item.quantityText, "to taste")
      }
    }

    @Test
    func unscaledRecipePreservesFractionalQuantityText() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_290_000)
      let recipeID = SampleUUIDSequence.uuid(18_101)
      let sectionID = SampleUUIDSequence.uuid(18_102)
      var uuids = SampleUUIDSequence(start: 18_200)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Half Batch",
          lines: [
            IngredientLine(
              id: SampleUUIDSequence.uuid(18_103),
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "½ cup cream",
              quantity: 0.5,
              quantityText: "½",
              unit: "cup",
              item: "cream",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let cream = try #require(
          try GroceryItemListRequest().fetch(db).first { $0.item.title == "cream" }
        )
        expectNoDifference(cream.item.quantity, 0.5)
        expectNoDifference(cream.item.quantityText, "½")
      }
    }
  }
}
