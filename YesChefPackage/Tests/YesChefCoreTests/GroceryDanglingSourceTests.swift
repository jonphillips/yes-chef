import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryDanglingSourceTests {
    @Test
    func deletedRecipeOriginStillReadsAndCanBeRemoved() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_262_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_263_000)
      let recipeID = SampleUUIDSequence.uuid(20_001)
      let sectionID = SampleUUIDSequence.uuid(20_002)
      let milkLineID = SampleUUIDSequence.uuid(20_003)
      var uuids = SampleUUIDSequence(start: 20_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertDanglingSourceRecipeFixture(
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
        try Recipe.find(recipeID).delete().execute(db)

        let row = try #require(try GroceryItemListRequest().fetch(db).first { $0.item.title == "milk" })
        let source = try #require(row.sources.first)
        expectNoDifference(try Recipe.find(recipeID).fetchOne(db), nil)
        expectNoDifference(try IngredientLine.find(milkLineID).fetchOne(db), nil)
        expectNoDifference(row.item.quantity, 2)
        expectNoDifference(row.item.quantityText, "2")
        expectNoDifference(row.sources.map(\.origin), [.recipe])
        expectNoDifference(row.sources.map(\.recipeID), [recipeID].map(Optional.some))
        expectNoDifference(row.sources.map(\.ingredientLineID), [milkLineID].map(Optional.some))
        expectNoDifference(row.sources.map(\.sourceTitle), ["Pancakes"])
        expectNoDifference(row.sources.map(\.ingredientText), ["2 cups milk"])
        expectNoDifference(row.sourceContributions.map(\.removalTitle), ["Remove Recipe Items"])

        try GroceryRepository.deleteContribution(
          containingSourceID: source.id,
          in: db,
          now: modifiedAt
        )

        expectNoDifference(try GroceryItem.find(row.id).fetchOne(db), nil)
        expectNoDifference(try GroceryItemSource.find(source.id).fetchOne(db), nil)
      }
    }

    @Test
    func deletedMenuAndPlacementOriginsStillReadAndCanBeRemoved() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_264_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_265_000)
      let startDate = Date(timeIntervalSinceReferenceDate: 805_266_000)
      let recipeID = SampleUUIDSequence.uuid(20_201)
      let sectionID = SampleUUIDSequence.uuid(20_202)
      let beanLineID = SampleUUIDSequence.uuid(20_203)
      var uuids = SampleUUIDSequence(start: 20_300)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertDanglingSourceRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Menu Beans",
          lines: [
            IngredientLine(
              id: beanLineID,
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

        _ = try GroceryRepository.addMenu(
          menuID: menuID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addMenuPlacement(
          placementID: placementID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try Menu.find(menuID).delete().execute(db)

        let row = try #require(try GroceryItemListRequest().fetch(db).first { $0.item.title == "beans" })
        expectNoDifference(try Menu.find(menuID).fetchOne(db), nil)
        expectNoDifference(try MenuItem.find(menuItemID).fetchOne(db), nil)
        expectNoDifference(try MenuPlacement.find(placementID).fetchOne(db), nil)
        expectNoDifference(row.item.quantity, 4)
        expectNoDifference(row.item.quantityText, "4")
        expectNoDifference(row.sources.map(\.origin), [.menu, .menuPlacement])
        expectNoDifference(row.sources.map(\.menuID), [menuID, menuID].map(Optional.some))
        expectNoDifference(row.sources.map(\.menuItemID), [menuItemID, menuItemID].map(Optional.some))
        expectNoDifference(row.sources.map(\.menuPlacementID), [nil, placementID])
        expectNoDifference(row.sources.map(\.sourceTitle), ["Game Day", "Game Day"])
        expectNoDifference(row.sources.map(\.sourceSubtitle), ["Menu Beans", "Menu Beans"])
        expectNoDifference(
          row.sourceContributions.map(\.removalTitle),
          ["Remove Menu Dish Items", "Remove Placed Dish Items"]
        )

        let menuSource = try #require(row.sources.first { $0.origin == .menu })
        try GroceryRepository.deleteContribution(
          containingSourceID: menuSource.id,
          in: db,
          now: modifiedAt
        )

        let remainingRow = try #require(try GroceryItemListRequest().fetch(db).first { $0.id == row.id })
        expectNoDifference(remainingRow.item.quantity, 2)
        expectNoDifference(remainingRow.item.quantityText, "2")
        expectNoDifference(remainingRow.item.dateModified, modifiedAt)
        expectNoDifference(remainingRow.sources.map(\.origin), [.menuPlacement])

        let placementSource = try #require(remainingRow.sources.first)
        try GroceryRepository.deleteContribution(
          containingSourceID: placementSource.id,
          in: db,
          now: modifiedAt
        )

        expectNoDifference(try GroceryItem.find(row.id).fetchOne(db), nil)
        expectNoDifference(try GroceryItemSource.find(menuSource.id).fetchOne(db), nil)
        expectNoDifference(try GroceryItemSource.find(placementSource.id).fetchOne(db), nil)
      }
    }
  }
}

private func insertDanglingSourceRecipeFixture(
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
