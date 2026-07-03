import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MeasureTests {
    @Test
    func mergesKnownUnitsWithinTheSameDimension() throws {
      expectNoDifference(
        Measure(quantity: 2, unit: "cups").merged(with: Measure(quantity: 1, unit: "cup")),
        Measure(quantity: 3, unit: "cups")
      )
      expectNoDifference(
        Measure(quantity: 8, unit: "oz").merged(with: Measure(quantity: 1, unit: "lb")),
        Measure(quantity: 24, unit: "oz")
      )
    }

    @Test
    func comparesKnownUnitsWithinTheSameDimension() {
      expectNoDifference(
        Measure(quantity: 5, unit: "tablespoons").compare(to: Measure(quantity: 0.25, unit: "cup")),
        .over
      )
      expectNoDifference(
        Measure(quantity: 3, unit: "tablespoons").compare(to: Measure(quantity: 0.25, unit: "cup")),
        .underOrEqual
      )
    }

    @Test
    func refusesCrossDimensionAndUnknownUnits() {
      expectNoDifference(
        Measure(quantity: 1, unit: "cup").merged(with: Measure(quantity: 1, unit: "lb")),
        nil
      )
      expectNoDifference(
        Measure(quantity: 1, unit: "cup").compare(to: Measure(quantity: 1, unit: "lb")),
        .incomparable
      )
      expectNoDifference(
        Measure(quantity: 1, unit: "splash").merged(with: Measure(quantity: 1, unit: "splash")),
        Measure(quantity: 2, unit: "splash")
      )
      expectNoDifference(
        Measure(quantity: 1, unit: "splash").compare(to: Measure(quantity: 1, unit: "cup")),
        .incomparable
      )
      expectNoDifference(
        Measure(quantity: 2, unit: "splash").compare(to: Measure(quantity: 1, unit: "splash")),
        .over
      )
    }

    @Test
    func generatedGroceriesMergeCompatibleMeasures() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 821_000_000)
      var uuids = SampleUUIDSequence(start: 46_000)

      let firstRecipeID = SampleUUIDSequence.uuid(46_101)
      let firstSectionID = SampleUUIDSequence.uuid(46_102)
      let firstCheeseID = SampleUUIDSequence.uuid(46_103)
      let secondRecipeID = SampleUUIDSequence.uuid(46_201)
      let secondSectionID = SampleUUIDSequence.uuid(46_202)
      let secondCheeseID = SampleUUIDSequence.uuid(46_203)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Mac",
          lines: [
            IngredientLine(
              id: firstCheeseID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "8 oz cheddar",
              quantity: 8,
              quantityText: "8",
              unit: "oz",
              item: "cheddar",
              shoppingCategory: "Dairy",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Gratin",
          lines: [
            IngredientLine(
              id: secondCheeseID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1 lb cheddar",
              quantity: 1,
              quantityText: "1",
              unit: "lb",
              item: "cheddar",
              shoppingCategory: "Dairy",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )

        for recipeID in [firstRecipeID, secondRecipeID] {
          _ = try GroceryRepository.addRecipe(
            recipeID: recipeID,
            groceryListID: listID,
            in: db,
            now: now,
            uuid: { uuids.next() }
          )
        }

        let rows = try GroceryItemListRequest().fetch(db)
        let cheeseRow = try #require(rows.first { $0.item.title == "cheddar" })
        expectNoDifference(cheeseRow.item.quantity, 24)
        expectNoDifference(cheeseRow.item.quantityText, "24")
        expectNoDifference(cheeseRow.item.unit, "oz")
        expectNoDifference(cheeseRow.sources.map(\.ingredientLineID), [firstCheeseID, secondCheeseID].map(Optional.some))
      }
    }

    @Test
    func generatedGroceriesKeepIncompatibleMeasuresSeparate() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 821_100_000)
      var uuids = SampleUUIDSequence(start: 47_000)

      let firstRecipeID = SampleUUIDSequence.uuid(47_101)
      let firstSectionID = SampleUUIDSequence.uuid(47_102)
      let volumeSugarID = SampleUUIDSequence.uuid(47_103)
      let secondRecipeID = SampleUUIDSequence.uuid(47_201)
      let secondSectionID = SampleUUIDSequence.uuid(47_202)
      let weightSugarID = SampleUUIDSequence.uuid(47_203)
      let thirdRecipeID = SampleUUIDSequence.uuid(47_301)
      let thirdSectionID = SampleUUIDSequence.uuid(47_302)
      let firstUnknownID = SampleUUIDSequence.uuid(47_303)
      let fourthRecipeID = SampleUUIDSequence.uuid(47_401)
      let fourthSectionID = SampleUUIDSequence.uuid(47_402)
      let secondUnknownID = SampleUUIDSequence.uuid(47_403)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Tea",
          lines: [
            IngredientLine(
              id: volumeSugarID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "1 cup sugar",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "sugar",
              shoppingCategory: "Baking",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Cake",
          lines: [
            IngredientLine(
              id: weightSugarID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1 lb sugar",
              quantity: 1,
              quantityText: "1",
              unit: "lb",
              item: "sugar",
              shoppingCategory: "Baking",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: thirdRecipeID,
          sectionID: thirdSectionID,
          title: "Risotto",
          lines: [
            IngredientLine(
              id: firstUnknownID,
              recipeID: thirdRecipeID,
              sectionID: thirdSectionID,
              originalText: "1 splash wine",
              quantity: 1,
              quantityText: "1",
              unit: "splash",
              item: "wine",
              shoppingCategory: "Wine",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: fourthRecipeID,
          sectionID: fourthSectionID,
          title: "Sauce",
          lines: [
            IngredientLine(
              id: secondUnknownID,
              recipeID: fourthRecipeID,
              sectionID: fourthSectionID,
              originalText: "1 splash wine",
              quantity: 1,
              quantityText: "1",
              unit: "splash",
              item: "wine",
              shoppingCategory: "Wine",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )

        for recipeID in [firstRecipeID, secondRecipeID, thirdRecipeID, fourthRecipeID] {
          _ = try GroceryRepository.addRecipe(
            recipeID: recipeID,
            groceryListID: listID,
            in: db,
            now: now,
            uuid: { uuids.next() }
          )
        }

        let rows = try GroceryItemListRequest().fetch(db)
        let sugarRows = rows.filter { $0.item.title == "sugar" }
        expectNoDifference(sugarRows.map(\.item.unit), ["cup", "lb"])
        expectNoDifference(sugarRows.flatMap(\.sources).map(\.ingredientLineID), [volumeSugarID, weightSugarID].map(Optional.some))

        let wineRow = try #require(rows.first { $0.item.title == "wine" })
        expectNoDifference(rows.filter { $0.item.title == "wine" }.count, 1)
        expectNoDifference(wineRow.item.quantity, 2)
        expectNoDifference(wineRow.item.quantityText, "2")
        expectNoDifference(wineRow.item.unit, "splash")
        expectNoDifference(wineRow.sources.map(\.ingredientLineID), [firstUnknownID, secondUnknownID].map(Optional.some))
      }
    }

    @Test
    func deletingSourceClearsLegacyIncompatibleQuantityInsteadOfLeavingStaleTotal() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 821_200_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 821_201_000)
      let listID = SampleUUIDSequence.uuid(48_001)
      let itemID = SampleUUIDSequence.uuid(48_002)
      let firstRecipeID = SampleUUIDSequence.uuid(48_101)
      let firstSectionID = SampleUUIDSequence.uuid(48_102)
      let volumeSugarID = SampleUUIDSequence.uuid(48_103)
      let secondRecipeID = SampleUUIDSequence.uuid(48_201)
      let secondSectionID = SampleUUIDSequence.uuid(48_202)
      let weightSugarID = SampleUUIDSequence.uuid(48_203)
      let thirdRecipeID = SampleUUIDSequence.uuid(48_301)
      let thirdSectionID = SampleUUIDSequence.uuid(48_302)
      let deletedSugarID = SampleUUIDSequence.uuid(48_303)
      let deletedSourceID = SampleUUIDSequence.uuid(48_403)

      try database.write { db in
        try GroceryList.insert {
          GroceryList(id: listID, title: "Legacy", sortOrder: 0, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: itemID,
            groceryListID: listID,
            title: "sugar",
            quantity: 99,
            quantityText: "99",
            unit: "cup",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Tea",
          lines: [
            IngredientLine(
              id: volumeSugarID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "1 cup sugar",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "sugar",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Cake",
          lines: [
            IngredientLine(
              id: weightSugarID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1 lb sugar",
              quantity: 1,
              quantityText: "1",
              unit: "lb",
              item: "sugar",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: thirdRecipeID,
          sectionID: thirdSectionID,
          title: "Sauce",
          lines: [
            IngredientLine(
              id: deletedSugarID,
              recipeID: thirdRecipeID,
              sectionID: thirdSectionID,
              originalText: "1 splash sugar",
              quantity: 1,
              quantityText: "1",
              unit: "splash",
              item: "sugar",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        for (sourceID, recipeID, lineID) in [
          (SampleUUIDSequence.uuid(48_401), firstRecipeID, volumeSugarID),
          (SampleUUIDSequence.uuid(48_402), secondRecipeID, weightSugarID),
          (deletedSourceID, thirdRecipeID, deletedSugarID),
        ] {
          try GroceryItemSource.insert {
            GroceryItemSource(
              id: sourceID,
              groceryItemID: itemID,
              origin: .recipe,
              recipeID: recipeID,
              ingredientLineID: lineID,
              sourceTitle: "Legacy",
              dateCreated: now
            )
          }
          .execute(db)
        }

        try GroceryRepository.deleteSource(sourceID: deletedSourceID, in: db, now: modifiedAt)

        let item = try #require(try GroceryItem.find(itemID).fetchOne(db))
        expectNoDifference(item.quantity, nil)
        expectNoDifference(item.quantityText, nil)
        expectNoDifference(item.unit, nil)
        expectNoDifference(item.dateModified, modifiedAt)
      }
    }
  }
}
