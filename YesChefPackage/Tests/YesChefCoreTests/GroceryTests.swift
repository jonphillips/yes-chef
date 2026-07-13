import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryTests {
    @Test
    func createsDefaultListAndCustomItemsWithCustomSource() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 805_000_000)
      let purchasedAt = Date(timeIntervalSinceReferenceDate: 805_100_000)
      var uuids = SampleUUIDSequence(start: 13_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )
        let itemID = try GroceryRepository.addCustomItem(
          title: "  Sparkling water  ",
          quantityText: "  12 cans ",
          aisle: " Drinks ",
          notes: " Lime if they have it ",
          groceryListID: listID,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )

        let row = try #require(try GroceryItemListRequest().fetch(db).first { $0.item.id == itemID })
        expectNoDifference(row.item.title, "Sparkling water")
        expectNoDifference(row.item.quantityText, "12 cans")
        expectNoDifference(row.item.aisle, "Drinks")
        expectNoDifference(row.item.notes, "Lime if they have it")
        expectNoDifference(row.sources.map(\.origin), [.custom])
        expectNoDifference(row.sources.map(\.sourceTitle), ["Custom"])
        expectNoDifference(row.sources.map(\.ingredientText), ["Sparkling water"])

        try GroceryRepository.updatePurchasedState(
          itemID: itemID,
          isPurchased: true,
          in: db,
          now: purchasedAt
        )

        let purchasedRow = try #require(try GroceryItemListRequest().fetch(db).first { $0.item.id == itemID })
        expectNoDifference(purchasedRow.item.isPurchased, true)
        expectNoDifference(purchasedRow.item.purchasedAt, purchasedAt)

        let listRow = try #require(try GroceryListRequest().fetch(db).first { $0.id == listID })
        expectNoDifference(listRow.itemCount, 1)
        expectNoDifference(listRow.remainingItemCount, 0)
      }
    }

    @Test
    func sortsPantryItemsAlphabetically() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_150_000)
      var uuids = SampleUUIDSequence(start: 13_200)

      try database.write { db in
        try PantryRepository.replaceItems(
          titles: ["vanilla", "Brown sugar", "all-purpose flour"],
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let items = try PantryItemListRequest().fetch(db)
        expectNoDifference(items.map(\.title), ["all-purpose flour", "Brown sugar", "vanilla"])
      }
    }

    @Test
    func addsRecipeIngredientsWithRecipeSource() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_200_000)
      let recipeID = SampleUUIDSequence.uuid(14_001)
      let sectionID = SampleUUIDSequence.uuid(14_002)
      let eggLineID = SampleUUIDSequence.uuid(14_003)
      let milkLineID = SampleUUIDSequence.uuid(14_004)
      let saltLineID = SampleUUIDSequence.uuid(14_005)
      var uuids = SampleUUIDSequence(start: 14_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Breakfast Bake",
          lines: [
            IngredientLine(
              id: eggLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "2 eggs",
              quantity: 2,
              quantityText: "2",
              item: "eggs",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            ),
            IngredientLine(
              id: milkLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "1 cup milk",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 1,
              confidence: .medium
            ),
            IngredientLine(
              id: saltLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "Kosher salt",
              item: "Kosher salt",
              doNotShop: true,
              sortOrder: 2,
              confidence: .low
            ),
          ],
          now: now,
          in: db
        )

        let itemIDs = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { itemIDs.contains($0.id) }

        expectNoDifference(rows.map(\.item.title), ["eggs", "milk"])
        expectNoDifference(rows.map(\.item.quantityText), ["2", "1"])
        expectNoDifference(rows.map(\.item.unit), [nil, "cup"])
        expectNoDifference(rows.map(\.item.aisle), ["Dairy", "Dairy"])
        expectNoDifference(rows.flatMap(\.sources).map(\.origin), [.recipe, .recipe])
        expectNoDifference(rows.flatMap(\.sources).map(\.recipeID), [recipeID, recipeID].map(Optional.some))
        expectNoDifference(
          rows.flatMap(\.sources).map(\.ingredientLineID),
          [eggLineID, milkLineID].map(Optional.some)
        )
        expectNoDifference(rows.flatMap(\.sources).map(\.sourceTitle), ["Breakfast Bake", "Breakfast Bake"])
        expectNoDifference(rows.flatMap(\.sources).map(\.ingredientText), ["2 eggs", "1 cup milk"])
      }
    }

    @Test
    func consolidatesCompatibleGeneratedIngredientsAndPreservesSources() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_250_000)
      let firstRecipeID = SampleUUIDSequence.uuid(17_001)
      let firstSectionID = SampleUUIDSequence.uuid(17_002)
      let firstMilkLineID = SampleUUIDSequence.uuid(17_003)
      let secondRecipeID = SampleUUIDSequence.uuid(17_004)
      let secondSectionID = SampleUUIDSequence.uuid(17_005)
      let secondMilkLineID = SampleUUIDSequence.uuid(17_006)
      var uuids = SampleUUIDSequence(start: 17_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Pancakes",
          lines: [
            IngredientLine(
              id: firstMilkLineID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "2 cups milk",
              quantity: 2,
              quantityText: "2",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Waffles",
          lines: [
            IngredientLine(
              id: secondMilkLineID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1.5 cups Milk",
              quantity: 1.5,
              quantityText: "1.5",
              unit: "cups",
              item: "Milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: firstRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: secondRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let milkRows = try GroceryItemListRequest().fetch(db)
          .filter { $0.item.title.localizedCaseInsensitiveCompare("milk") == .orderedSame }

        let row = try #require(milkRows.first)
        expectNoDifference(milkRows.count, 1)
        expectNoDifference(row.item.quantity, 3.5)
        expectNoDifference(row.item.quantityText, "3.5")
        expectNoDifference(row.item.unit, "cups")
        expectNoDifference(row.item.aisle, "Dairy")
        expectNoDifference(row.sources.map(\.origin), [.recipe, .recipe])
        expectNoDifference(row.sources.map(\.recipeID), [firstRecipeID, secondRecipeID].map(Optional.some))
        expectNoDifference(
          row.sources.map(\.ingredientLineID),
          [firstMilkLineID, secondMilkLineID].map(Optional.some)
        )
        expectNoDifference(row.sources.map(\.sourceTitle), ["Pancakes", "Waffles"])
      }
    }

    @Test
    func keepsPurchasedAndPrepSensitiveItemsSeparateWhenGeneratingGroceries() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_275_000)
      let purchasedAt = Date(timeIntervalSinceReferenceDate: 805_276_000)
      let firstRecipeID = SampleUUIDSequence.uuid(18_001)
      let firstSectionID = SampleUUIDSequence.uuid(18_002)
      let firstMilkLineID = SampleUUIDSequence.uuid(18_003)
      let secondRecipeID = SampleUUIDSequence.uuid(18_004)
      let secondSectionID = SampleUUIDSequence.uuid(18_005)
      let secondMilkLineID = SampleUUIDSequence.uuid(18_006)
      let thirdRecipeID = SampleUUIDSequence.uuid(18_007)
      let thirdSectionID = SampleUUIDSequence.uuid(18_008)
      let warmedMilkLineID = SampleUUIDSequence.uuid(18_009)
      var uuids = SampleUUIDSequence(start: 18_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "First Cake",
          lines: [
            IngredientLine(
              id: firstMilkLineID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "1 cup milk",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Second Cake",
          lines: [
            IngredientLine(
              id: secondMilkLineID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1 cup milk",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: thirdRecipeID,
          sectionID: thirdSectionID,
          title: "Custard",
          lines: [
            IngredientLine(
              id: warmedMilkLineID,
              recipeID: thirdRecipeID,
              sectionID: thirdSectionID,
              originalText: "1 cup milk, warmed",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "milk",
              preparation: "warmed",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )

        let purchasedItemID = try #require(
          try GroceryRepository.addRecipe(
            recipeID: firstRecipeID,
            groceryListID: listID,
            in: db,
            now: now,
            uuid: { uuids.next() }
          )
          .first
        )
        try GroceryRepository.updatePurchasedState(
          itemID: purchasedItemID,
          isPurchased: true,
          in: db,
          now: purchasedAt
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: secondRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: thirdRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let milkRows = try GroceryItemListRequest().fetch(db)
          .filter { $0.item.title == "milk" }

        expectNoDifference(milkRows.count, 3)
        expectNoDifference(milkRows.filter(\.item.isPurchased).map(\.item.id), [purchasedItemID])
        expectNoDifference(milkRows.filter { !$0.item.isPurchased }.map(\.item.notes), [nil, "warmed"])
        expectNoDifference(
          milkRows.flatMap(\.sources).map(\.ingredientLineID),
          [secondMilkLineID, warmedMilkLineID, firstMilkLineID].map(Optional.some)
        )
      }
    }

    @Test
    func clearsPurchasedAndAllItems() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_700_000)
      let purchasedAt = Date(timeIntervalSinceReferenceDate: 805_701_000)
      var uuids = SampleUUIDSequence(start: 19_100)

      try database.write { db in
        let listID = try GroceryRepository.addList(
          title: "Clear Test",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let purchasedItemID = try GroceryRepository.addCustomItem(
          title: "Milk",
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addCustomItem(
          title: "Eggs",
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try GroceryRepository.updatePurchasedState(
          itemID: purchasedItemID,
          isPurchased: true,
          in: db,
          now: purchasedAt
        )

        expectNoDifference(
          try GroceryRepository.clearPurchasedItems(groceryListID: listID, in: db),
          1
        )
        expectNoDifference(
          try GroceryItemListRequest().fetch(db)
            .filter { $0.item.groceryListID == listID }
            .map(\.item.title),
          ["Eggs"]
        )

        expectNoDifference(
          try GroceryRepository.clearAllItems(groceryListID: listID, in: db),
          1
        )
        expectNoDifference(
          try GroceryItemListRequest().fetch(db)
            .filter { $0.item.groceryListID == listID },
          []
        )
      }
    }

    @Test
    func managesPrimaryAndSecondaryLists() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_710_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_711_000)
      var uuids = SampleUUIDSequence(start: 19_300)

      try database.write { db in
        try GroceryList.delete().execute(db)

        let primaryListID = try GroceryRepository.addList(
          title: "Primary",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let secondaryListID = try GroceryRepository.addList(
          title: "Secondary",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        try GroceryRepository.setDefaultList(
          listID: secondaryListID,
          in: db,
          now: modifiedAt
        )
        var rows = try GroceryListRequest().fetch(db)
          .filter { [primaryListID, secondaryListID].contains($0.id) }

        expectNoDifference(rows.first { $0.id == primaryListID }?.list.isDefault, false)
        expectNoDifference(rows.first { $0.id == secondaryListID }?.list.isDefault, true)

        try GroceryRepository.updateList(
          listID: secondaryListID,
          title: "Hardware Store",
          remindersListName: "Hardware",
          in: db,
          now: modifiedAt
        )

        let updatedList = try #require(try GroceryList.find(secondaryListID).fetchOne(db))
        expectNoDifference(updatedList.title, "Hardware Store")
        expectNoDifference(updatedList.remindersListName, "Hardware")

        _ = try GroceryRepository.deleteList(
          listID: secondaryListID,
          in: db,
          now: modifiedAt
        )
        rows = try GroceryListRequest().fetch(db)
          .filter { [primaryListID, secondaryListID].contains($0.id) }

        expectNoDifference(rows.map(\.id), [primaryListID])
        expectNoDifference(rows.first?.list.isDefault, true)
      }
    }

    @Test
    func managesPantryRows() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_720_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_721_000)
      var uuids = SampleUUIDSequence(start: 19_500)

      try database.write { db in
        let sugarID = try PantryRepository.addItem(
          title: "  Sugar  ",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let duplicateSugarID = try PantryRepository.addItem(
          title: "sugar",
          notes: "Baking",
          in: db,
          now: modifiedAt,
          uuid: { uuids.next() }
        )

        expectNoDifference(duplicateSugarID, sugarID)
        var row = try #require(try PantryItem.find(sugarID).fetchOne(db))
        expectNoDifference(row.title, "Sugar")
        expectNoDifference(row.notes, "Baking")

        expectNoDifference(
          try PantryRepository.addItem(
            title: "SUGAR",
            in: db,
            now: modifiedAt,
            uuid: { uuids.next() }
          ),
          sugarID
        )
        row = try #require(try PantryItem.find(sugarID).fetchOne(db))
        expectNoDifference(row.notes, "Baking")

        try PantryRepository.updateItem(
          itemID: sugarID,
          title: "Brown sugar",
          notes: "Light or dark",
          policy: .unlimited,
          in: db,
          now: modifiedAt
        )
        row = try #require(try PantryItem.find(sugarID).fetchOne(db))
        expectNoDifference(row.title, "Brown sugar")
        expectNoDifference(row.notes, "Light or dark")

        try PantryRepository.deleteItem(itemID: sugarID, in: db)
        expectNoDifference(try PantryItem.find(sugarID).fetchOne(db), nil)
      }
    }

  }
}

extension RecipeCoreTests {
  @Suite
  struct GroceryIngredientSelectionTests {
    @Test
    func addsOnlySelectedRecipeIngredients() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_225_000)
      let recipeID = SampleUUIDSequence.uuid(14_201)
      let sectionID = SampleUUIDSequence.uuid(14_202)
      let flourLineID = SampleUUIDSequence.uuid(14_203)
      let sugarLineID = SampleUUIDSequence.uuid(14_204)
      let butterLineID = SampleUUIDSequence.uuid(14_205)
      var uuids = SampleUUIDSequence(start: 14_300)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Snack Cake",
          lines: [
            IngredientLine(
              id: flourLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "2 cups flour",
              quantity: 2,
              quantityText: "2",
              unit: "cups",
              item: "flour",
              shoppingCategory: "Baking",
              sortOrder: 0,
              confidence: .medium
            ),
            IngredientLine(
              id: sugarLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "1 cup sugar",
              quantity: 1,
              quantityText: "1",
              unit: "cup",
              item: "sugar",
              shoppingCategory: "Baking",
              sortOrder: 1,
              confidence: .medium
            ),
            IngredientLine(
              id: butterLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "4 tablespoons butter",
              quantity: 4,
              quantityText: "4",
              unit: "tablespoons",
              item: "butter",
              shoppingCategory: "Dairy",
              sortOrder: 2,
              confidence: .medium
            ),
          ],
          now: now,
          in: db
        )

        let itemIDs = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() },
          includedIngredientLineIDs: [flourLineID, butterLineID]
        )
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { itemIDs.contains($0.id) }

        expectNoDifference(rows.map(\.item.title), ["flour", "butter"])
        expectNoDifference(
          rows.flatMap(\.sources).map(\.ingredientLineID),
          [flourLineID, butterLineID].map(Optional.some)
        )
        expectNoDifference(rows.flatMap(\.sources).contains { $0.ingredientLineID == sugarLineID }, false)
      }
    }
  }
}

extension RecipeCoreTests {
  @Suite
  struct GrocerySourceRemovalTests {
    @Test
    func deletingSourceFromConsolidatedItemRecalculatesQuantity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_255_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_256_000)
      let firstRecipeID = SampleUUIDSequence.uuid(17_201)
      let firstSectionID = SampleUUIDSequence.uuid(17_202)
      let firstMilkLineID = SampleUUIDSequence.uuid(17_203)
      let secondRecipeID = SampleUUIDSequence.uuid(17_204)
      let secondSectionID = SampleUUIDSequence.uuid(17_205)
      let secondMilkLineID = SampleUUIDSequence.uuid(17_206)
      var uuids = SampleUUIDSequence(start: 17_300)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Pancakes",
          lines: [
            IngredientLine(
              id: firstMilkLineID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "2 cups milk",
              quantity: 2,
              quantityText: "2",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db,
          viewScale: 2
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Waffles",
          lines: [
            IngredientLine(
              id: secondMilkLineID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1.5 cups milk",
              quantity: 1.5,
              quantityText: "1.5",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db,
          viewScale: 3
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: firstRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: secondRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let consolidatedRow = try #require(
          try GroceryItemListRequest().fetch(db).first { $0.item.title == "milk" }
        )
        expectNoDifference(consolidatedRow.item.quantity, 8.5)
        expectNoDifference(consolidatedRow.item.quantityText, "8.5")
        let wafflesSource = try #require(consolidatedRow.sources.first { $0.recipeID == secondRecipeID })
        try GroceryRepository.deleteSource(sourceID: wafflesSource.id, in: db, now: modifiedAt)

        let updatedRow = try #require(
          try GroceryItemListRequest().fetch(db).first { $0.id == consolidatedRow.id }
        )
        expectNoDifference(updatedRow.item.quantity, 4)
        expectNoDifference(updatedRow.item.quantityText, "4")
        expectNoDifference(updatedRow.item.dateModified, modifiedAt)
        expectNoDifference(updatedRow.sources.map(\.recipeID), [firstRecipeID].map(Optional.some))
        expectNoDifference(updatedRow.sources.map(\.ingredientLineID), [firstMilkLineID].map(Optional.some))
        expectNoDifference(try GroceryItemSource.find(wafflesSource.id).fetchOne(db), nil)
      }
    }

    @Test
    func deletingRecipeContributionRemovesAllMatchingSourcesInList() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_258_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_259_000)
      let firstRecipeID = SampleUUIDSequence.uuid(17_501)
      let firstSectionID = SampleUUIDSequence.uuid(17_502)
      let firstMilkLineID = SampleUUIDSequence.uuid(17_503)
      let firstEggLineID = SampleUUIDSequence.uuid(17_504)
      let secondRecipeID = SampleUUIDSequence.uuid(17_505)
      let secondSectionID = SampleUUIDSequence.uuid(17_506)
      let secondMilkLineID = SampleUUIDSequence.uuid(17_507)
      var uuids = SampleUUIDSequence(start: 17_600)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Pancakes",
          lines: [
            IngredientLine(
              id: firstMilkLineID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "2 cups milk",
              quantity: 2,
              quantityText: "2",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            ),
            IngredientLine(
              id: firstEggLineID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "2 eggs",
              quantity: 2,
              quantityText: "2",
              item: "eggs",
              shoppingCategory: "Dairy",
              sortOrder: 1,
              confidence: .medium
            ),
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Waffles",
          lines: [
            IngredientLine(
              id: secondMilkLineID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1.5 cups milk",
              quantity: 1.5,
              quantityText: "1.5",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: firstRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: secondRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let consolidatedRow = try #require(
          try GroceryItemListRequest().fetch(db).first { $0.item.title == "milk" }
        )
        let pancakesSource = try #require(consolidatedRow.sources.first { $0.recipeID == firstRecipeID })
        try GroceryRepository.deleteContribution(
          containingSourceID: pancakesSource.id,
          in: db,
          now: modifiedAt
        )

        let rows = try GroceryItemListRequest().fetch(db)
        let milkRow = try #require(rows.first { $0.item.title == "milk" })
        expectNoDifference(milkRow.item.quantity, 1.5)
        expectNoDifference(milkRow.item.quantityText, "1.5")
        expectNoDifference(milkRow.item.dateModified, modifiedAt)
        expectNoDifference(milkRow.sources.map(\.recipeID), [secondRecipeID].map(Optional.some))
        expectNoDifference(rows.contains { $0.item.title == "eggs" }, false)
        expectNoDifference(rows.flatMap(\.sources).contains { $0.recipeID == firstRecipeID }, false)
      }
    }

    @Test
    func deletingRecipeContributionDoesNotRemoveSameRecipeFromOtherLists() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_260_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_261_000)
      let recipeID = SampleUUIDSequence.uuid(17_701)
      let sectionID = SampleUUIDSequence.uuid(17_702)
      let milkLineID = SampleUUIDSequence.uuid(17_703)
      let eggLineID = SampleUUIDSequence.uuid(17_704)
      var uuids = SampleUUIDSequence(start: 17_800)

      try database.write { db in
        let firstListID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let secondListID = try GroceryRepository.addList(
          title: "Party Prep",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Pancakes",
          lines: [
            IngredientLine(
              id: milkLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "2 cups milk",
              quantity: 2,
              quantityText: "2",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            ),
            IngredientLine(
              id: eggLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "2 eggs",
              quantity: 2,
              quantityText: "2",
              item: "eggs",
              shoppingCategory: "Dairy",
              sortOrder: 1,
              confidence: .medium
            ),
          ],
          now: now,
          in: db
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: firstListID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: secondListID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let firstListRow = try #require(
          try GroceryItemListRequest().fetch(db)
            .first { $0.item.groceryListID == firstListID && $0.item.title == "milk" }
        )
        let source = try #require(firstListRow.sources.first { $0.recipeID == recipeID })
        try GroceryRepository.deleteContribution(
          containingSourceID: source.id,
          in: db,
          now: modifiedAt
        )

        let rows = try GroceryItemListRequest().fetch(db)
        expectNoDifference(rows.filter { $0.item.groceryListID == firstListID }, [])
        let remainingRows = rows.filter { $0.item.groceryListID == secondListID }
        expectNoDifference(remainingRows.map(\.item.title), ["milk", "eggs"])
        expectNoDifference(
          remainingRows.map { $0.sources.map(\.recipeID) },
          [[recipeID].map(Optional.some), [recipeID].map(Optional.some)]
        )
      }
    }

    @Test
    func deletingLastSourceDeletesItem() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_257_000)
      var uuids = SampleUUIDSequence(start: 17_400)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let itemID = try GroceryRepository.addCustomItem(
          title: "Sparkling water",
          quantityText: "12 cans",
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let row = try #require(try GroceryItemListRequest().fetch(db).first { $0.id == itemID })
        let source = try #require(row.sources.first)
        try GroceryRepository.deleteSource(sourceID: source.id, in: db, now: now)

        expectNoDifference(try GroceryItem.find(itemID).fetchOne(db), nil)
        expectNoDifference(try GroceryItemSource.find(source.id).fetchOne(db), nil)
        expectNoDifference(try GroceryListRequest().fetch(db).first { $0.id == listID }?.itemCount, 0)
      }
    }

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

func insertRecipeFixture(
  recipeID: Recipe.ID,
  sectionID: IngredientSection.ID,
  title: String,
  lines: [IngredientLine],
  now: Date,
  in db: Database,
  viewScale: Double = 1
) throws {
  try Recipe.insert {
    Recipe(
      id: recipeID,
      title: title,
      dateCreated: now,
      dateModified: now,
      viewScale: viewScale
    )
  }
  .execute(db)
  try IngredientSection.insert {
    IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
  }
  .execute(db)
  for line in lines {
    try IngredientLine.insert { line }.execute(db)
  }
}
