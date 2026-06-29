import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryPlanningTests {
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
