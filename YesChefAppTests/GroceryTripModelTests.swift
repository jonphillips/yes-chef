import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct GroceryTripModelTests {
  @Test
  func splitMenuAddWritesBothListsAndOnlySwitchedNames() throws {
    let now = Date(timeIntervalSinceReferenceDate: 900_700_000)
    let menuID = SampleUUIDSequence.uuid(90_701)
    let onionRecipeID = SampleUUIDSequence.uuid(90_702)
    let otherRecipeID = SampleUUIDSequence.uuid(90_703)
    let onionLineID = SampleUUIDSequence.uuid(90_704)
    let cilantroLineID = SampleUUIDSequence.uuid(90_705)
    let turkeyLineID = SampleUUIDSequence.uuid(90_706)
    let secondOnionLineID = SampleUUIDSequence.uuid(90_711)
    let onionSectionID = SampleUUIDSequence.uuid(90_707)
    let otherSectionID = SampleUUIDSequence.uuid(90_708)

    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.continuousClock = ContinuousClock()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Thanksgiving", dayCount: 1, dateCreated: now, dateModified: now) }.execute(db)
        try Recipe.insert { Recipe(id: onionRecipeID, title: "Onion side", dateCreated: now, dateModified: now) }.execute(db)
        try Recipe.insert { Recipe(id: otherRecipeID, title: "Turkey dinner", dateCreated: now, dateModified: now) }.execute(db)
        try IngredientSection.insert { IngredientSection(id: onionSectionID, recipeID: onionRecipeID, sortOrder: 0) }.execute(db)
        try IngredientSection.insert { IngredientSection(id: otherSectionID, recipeID: otherRecipeID, sortOrder: 0) }.execute(db)
        try IngredientLine.insert {
          IngredientLine(id: onionLineID, recipeID: onionRecipeID, sectionID: onionSectionID,
            originalText: "2 onions", quantity: 2, quantityText: "2", item: "onions", sortOrder: 0)
        }.execute(db)
        for (id, text, item, order) in [
          (cilantroLineID, "1 bunch cilantro", "cilantro", 0),
          (turkeyLineID, "1 turkey", "turkey", 1),
        ] {
          try IngredientLine.insert {
            IngredientLine(id: id, recipeID: otherRecipeID, sectionID: otherSectionID,
              originalText: text, item: item, sortOrder: order)
          }.execute(db)
        }
        try IngredientLine.insert {
          IngredientLine(id: secondOnionLineID, recipeID: otherRecipeID, sectionID: otherSectionID,
            originalText: "3 onions", quantity: 3, quantityText: "3", item: "onions", sortOrder: -1)
        }.execute(db)
        try MenuItem.insert {
          MenuItem(id: SampleUUIDSequence.uuid(90_709), menuID: menuID, kind: .recipe, recipeID: onionRecipeID,
            title: "Onion side", dayOffset: 0, mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try MenuItem.insert {
          MenuItem(id: SampleUUIDSequence.uuid(90_710), menuID: menuID, kind: .recipe, recipeID: otherRecipeID,
            title: "Turkey dinner", dayOffset: 0, mealSlot: .dinner, sortOrder: 1, dateCreated: now, dateModified: now)
        }.execute(db)
      }

      let choices = try database.read { db in
        try GroceryIngredientChoiceRequest(recipeIDs: [onionRecipeID, otherRecipeID]).fetch(db)
      }
      let model = GroceryLibraryModel()
      #expect(model.confirmIngredientSelectionButtonTapped(
        context: GroceryIngredientSelectionContext(source: .menu(menuID), title: "Thanksgiving", subtitle: "Menu"),
        selectedIngredientLineIDs: Set(choices.map(\.line.id)),
        mealRows: [],
        choices: choices,
        tripByCanonicalName: ["onion": .advance, "cilantro": .advance, "turkey": .fresh],
        switchedCanonicalNames: ["cilantro"]
      ))

      let lists = try database.read { db in try GroceryList.fetchAll(db) }
      #expect(lists.map(\.title).sorted() == ["Thanksgiving — Advance", "Thanksgiving — Fresh"])
      #expect(model.selectedListID == lists.first(where: { $0.title.hasSuffix("Advance") })?.id)
      let items = try database.read { db in try GroceryItem.fetchAll(db) }
      let advanceItems = items.filter { $0.groceryListID == model.selectedListID }
      #expect(advanceItems.map(\.title).sorted() == ["cilantro", "onions"])
      #expect(advanceItems.filter { $0.title == "onions" }.count == 1)
      let assignments = try database.read { db in try GroceryTripAssignment.fetchAll(db) }
      #expect(assignments.count == 1)
      #expect(assignments.first?.canonicalName == "cilantro")
      #expect(assignments.first?.trip == .advance)

      #expect(model.confirmIngredientSelectionButtonTapped(
        context: GroceryIngredientSelectionContext(source: .menu(menuID), title: "Thanksgiving", subtitle: "Menu"),
        selectedIngredientLineIDs: Set(choices.map(\.line.id)),
        mealRows: [],
        choices: choices
      ))
      let listsAfterUnsplitAdd = try database.read { db in try GroceryList.fetchAll(db) }
      #expect(listsAfterUnsplitAdd.map(\.title).sorted() == ["Thanksgiving — Advance", "Thanksgiving — Fresh"])
      #expect(model.selectedListID == lists.first(where: { $0.title.hasSuffix("Advance") })?.id)
    }
  }

  @Test
  func pantryStapleNamesExcludesRemindMeItems() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 900_800_000)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try PantryItem.insert {
          PantryItem(id: SampleUUIDSequence.uuid(90_801), title: "Olive oil", isUnlimited: true,
            sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try PantryItem.insert {
          PantryItem(id: SampleUUIDSequence.uuid(90_802), title: "Butter", isUnlimited: false,
            thresholdQuantity: 1, thresholdUnit: "cup", sortOrder: 1, dateCreated: now, dateModified: now)
        }.execute(db)
      }
      let model = GroceryLibraryModel()
      try await model.$pantryItems.load()
      #expect(model.pantryStapleNames == ["Olive oil"])
    }
  }
}
