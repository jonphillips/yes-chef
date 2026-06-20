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
    func addsPlannedMealsWithCalendarAndMenuPlacementSources() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_300_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 805_400_000)
      let recipeID = SampleUUIDSequence.uuid(15_001)
      let sectionID = SampleUUIDSequence.uuid(15_002)
      let ingredientLineID = SampleUUIDSequence.uuid(15_003)
      var uuids = SampleUUIDSequence(start: 15_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Calendar Soup",
          lines: [
            IngredientLine(
              id: ingredientLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "3 carrots",
              quantity: 3,
              quantityText: "3",
              item: "carrots",
              shoppingCategory: "Produce",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )

        let mealPlanItemID = try MealCalendarRepository.addRecipeItem(
          recipeID: recipeID,
          on: scheduledDate,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let menuID = try MenuRepository.addMenu(
          title: "Soup Week",
          notes: nil,
          dayCount: 1,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let menuItemID = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .lunch,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let placementID = try MenuRepository.placeMenu(
          menuID: menuID,
          startDate: scheduledDate,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let mealRows = try MealCalendarRequest().fetch(db)
          .filter { $0.item.scheduledDate == scheduledDate }

        let itemIDs = try GroceryRepository.addMealPlanRows(
          mealRows,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let sources = try GroceryItemListRequest().fetch(db)
          .filter { itemIDs.contains($0.id) }
          .flatMap(\.sources)
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { itemIDs.contains($0.id) }

        expectNoDifference(rows.count, 1)
        expectNoDifference(rows.first?.item.quantity, 6)
        expectNoDifference(rows.first?.item.quantityText, "6")
        expectNoDifference(sources.map(\.origin), [.menuPlacement, .calendarItem])
        expectNoDifference(sources.map(\.recipeID), [recipeID, recipeID].map(Optional.some))
        expectNoDifference(sources.map(\.ingredientLineID), [ingredientLineID, ingredientLineID].map(Optional.some))
        expectNoDifference(sources.map(\.mealPlanItemID), [nil, mealPlanItemID])
        expectNoDifference(sources.map(\.menuID), [menuID, nil])
        expectNoDifference(sources.map(\.menuItemID), [menuItemID, nil])
        expectNoDifference(sources.map(\.menuPlacementID), [placementID, nil])
        expectNoDifference(sources.map(\.scheduledDate), [scheduledDate, scheduledDate].map(Optional.some))
        expectNoDifference(sources.map(\.mealSlot), [.lunch, .dinner].map(Optional.some))
        expectNoDifference(sources.map(\.sourceTitle), ["Soup Week", "Calendar Soup"])
        expectNoDifference(sources.map(\.sourceSubtitle), ["Calendar Soup", "Dinner"])
      }
    }

    @Test
    func addsMenusAndPlacedMenusWithDistinctOrigins() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_500_000)
      let startDate = Date(timeIntervalSinceReferenceDate: 805_600_000)
      let recipeID = SampleUUIDSequence.uuid(16_001)
      let sectionID = SampleUUIDSequence.uuid(16_002)
      let ingredientLineID = SampleUUIDSequence.uuid(16_003)
      var uuids = SampleUUIDSequence(start: 16_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Menu Beans",
          lines: [
            IngredientLine(
              id: ingredientLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "2 cans beans",
              quantity: 2,
              quantityText: "2",
              unit: "cans",
              item: "beans",
              shoppingCategory: "Pantry",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )
        let menuID = try MenuRepository.addMenu(
          title: "Game Day",
          notes: nil,
          dayCount: 1,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let menuItemID = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let placementID = try MenuRepository.placeMenu(
          menuID: menuID,
          startDate: startDate,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let menuItemIDs = try GroceryRepository.addMenu(
          menuID: menuID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let placedItemIDs = try GroceryRepository.addMenuPlacement(
          placementID: placementID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let sources = try GroceryItemListRequest().fetch(db)
          .filter { (menuItemIDs + placedItemIDs).contains($0.id) }
          .flatMap(\.sources)
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { (menuItemIDs + placedItemIDs).contains($0.id) }

        expectNoDifference(rows.count, 1)
        expectNoDifference(rows.first?.item.quantity, 4)
        expectNoDifference(rows.first?.item.quantityText, "4")
        expectNoDifference(sources.map(\.origin), [.menu, .menuPlacement])
        expectNoDifference(sources.map(\.menuID), [menuID, menuID].map(Optional.some))
        expectNoDifference(sources.map(\.menuItemID), [menuItemID, menuItemID].map(Optional.some))
        expectNoDifference(sources.map(\.menuPlacementID), [nil, placementID])
        expectNoDifference(sources.map(\.scheduledDate), [nil, startDate])
        expectNoDifference(sources.map(\.mealSlot), [.dinner, .dinner].map(Optional.some))
        expectNoDifference(sources.map(\.sourceTitle), ["Game Day", "Game Day"])
        expectNoDifference(sources.map(\.sourceSubtitle), ["Menu Beans", "Menu Beans"])
      }
    }

  }
}

private func insertRecipeFixture(
  recipeID: Recipe.ID,
  sectionID: IngredientSection.ID,
  title: String,
  lines: [IngredientLine],
  now: Date,
  in db: Database
) throws {
  try Recipe.insert {
    Recipe(
      id: recipeID,
      title: title,
      dateCreated: now,
      dateModified: now
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
