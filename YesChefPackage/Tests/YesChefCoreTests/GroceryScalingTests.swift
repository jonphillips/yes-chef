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

    @Test
    func rangeGroceryUsesUpperBoundAndMergesWithSingleQuantity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_300_000)
      let rangeRecipeID = SampleUUIDSequence.uuid(18_301)
      let otherRecipeID = SampleUUIDSequence.uuid(18_311)
      let rangeSectionID = SampleUUIDSequence.uuid(18_302)
      let otherSectionID = SampleUUIDSequence.uuid(18_312)
      var uuids = SampleUUIDSequence(start: 18_320)
      let rangeLine = IngredientParser.lines(
        from: "8-10 ounces kale",
        recipeID: rangeRecipeID,
        sectionID: rangeSectionID,
        uuid: { uuids.next() }
      )[0]
      let otherLine = IngredientParser.lines(
        from: "6 ounces kale",
        recipeID: otherRecipeID,
        sectionID: otherSectionID,
        uuid: { uuids.next() }
      )[0]

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        try insertRecipeFixture(
          recipeID: rangeRecipeID,
          sectionID: rangeSectionID,
          title: "Range Kale",
          lines: [rangeLine],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: otherRecipeID,
          sectionID: otherSectionID,
          title: "Plain Kale",
          lines: [otherLine],
          now: now,
          in: db
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: rangeRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let rangeOnly = try #require(try GroceryItemListRequest().fetch(db).first { $0.item.title == "kale" })
        expectNoDifference(rangeOnly.item.quantity, 10)
        expectNoDifference(rangeOnly.item.quantityText, "10")
        _ = try GroceryRepository.addRecipe(
          recipeID: otherRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let kale = try #require(try GroceryItemListRequest().fetch(db).first { $0.item.title == "kale" })
        expectNoDifference(kale.item.quantity, 16)
        expectNoDifference(kale.item.quantityText, "16")
      }
    }

    @Test
    func scaledRangeGroceryUsesScaledUpperBound() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_310_000)
      let recipeID = SampleUUIDSequence.uuid(18_401)
      let sectionID = SampleUUIDSequence.uuid(18_402)
      var uuids = SampleUUIDSequence(start: 18_420)
      let line = IngredientParser.lines(
        from: "8-10 ounces kale",
        recipeID: recipeID,
        sectionID: sectionID,
        uuid: { uuids.next() }
      )[0]

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Scaled Range Kale",
          lines: [line],
          now: now,
          in: db,
          viewScale: 2
        )
        let itemIDs = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let item = try #require(try GroceryItemListRequest().fetch(db).first { itemIDs.contains($0.id) })
        expectNoDifference(item.item.quantity, 20)
        expectNoDifference(item.item.quantityText, "20")
      }
    }
  }
}
