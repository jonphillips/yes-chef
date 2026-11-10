import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeScaleTests {
    @Test
    func recipeRowNoteRequestReturnsOnlyTheCurrentPlacementNote() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 812_300_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 812_400_000)
      let recipeID = SampleUUIDSequence.uuid(35_301)
      let otherRecipeID = SampleUUIDSequence.uuid(35_302)
      let menuID = SampleUUIDSequence.uuid(35_303)
      let menuItemIDs = (35_310...35_315).map(SampleUUIDSequence.uuid)
      let mealPlanItemID = SampleUUIDSequence.uuid(35_320)
      let missingID = SampleUUIDSequence.uuid(35_399)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Chicken", dateCreated: now, dateModified: now)
          Recipe(id: otherRecipeID, title: "Beans", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Menu.insert {
          Menu(id: menuID, title: "Thanksgiving Week", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try MenuItem.insert {
          MenuItem(
            id: menuItemIDs[0], menuID: menuID, kind: .recipe, recipeID: recipeID,
            title: "Chicken", dayOffset: 0, mealSlot: .dinner, notes: "  Serve sauce on the side.  ",
            sortOrder: 0, dateCreated: now, dateModified: now
          )
          MenuItem(
            id: menuItemIDs[1], menuID: menuID, kind: .recipe, recipeID: recipeID,
            title: "Chicken", dayOffset: 0, mealSlot: .dinner, notes: "Second placement.",
            sortOrder: 1, dateCreated: now, dateModified: now
          )
          MenuItem(
            id: menuItemIDs[2], menuID: menuID, kind: .recipe, recipeID: recipeID,
            title: "Chicken", dayOffset: 0, mealSlot: .dinner, notes: nil,
            sortOrder: 2, dateCreated: now, dateModified: now
          )
          MenuItem(
            id: menuItemIDs[3], menuID: menuID, kind: .recipe, recipeID: recipeID,
            title: "Chicken", dayOffset: 0, mealSlot: .dinner, notes: "",
            sortOrder: 3, dateCreated: now, dateModified: now
          )
          MenuItem(
            id: menuItemIDs[4], menuID: menuID, kind: .recipe, recipeID: recipeID,
            title: "Chicken", dayOffset: 0, mealSlot: .dinner, notes: " \n ",
            sortOrder: 4, dateCreated: now, dateModified: now
          )
          MenuItem(
            id: menuItemIDs[5], menuID: menuID, kind: .recipe, recipeID: otherRecipeID,
            title: "Beans", dayOffset: 0, mealSlot: .dinner, notes: "Wrong recipe.",
            sortOrder: 5, dateCreated: now, dateModified: now
          )
        }
        .execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: mealPlanItemID, kind: .recipe, recipeID: recipeID, title: "Chicken",
            scheduledDate: scheduledDate, mealSlot: .lunch, notes: " Calendar note ",
            sortOrder: 0, dateCreated: now, dateModified: now
          )
        }
        .execute(db)

        expectNoDifference(
          try RecipeRowNoteRequest(context: .menuItem(menuItemIDs[0]), recipeID: recipeID).fetch(db),
          RecipeRowNote(text: "Serve sauce on the side.", origin: .menu(title: "Thanksgiving Week"))
        )
        expectNoDifference(
          try RecipeRowNoteRequest(context: .menuItem(menuItemIDs[1]), recipeID: recipeID).fetch(db),
          RecipeRowNote(text: "Second placement.", origin: .menu(title: "Thanksgiving Week"))
        )
        for itemID in menuItemIDs[2...4] {
          #expect(try RecipeRowNoteRequest(context: .menuItem(itemID), recipeID: recipeID).fetch(db) == nil)
        }
        #expect(try RecipeRowNoteRequest(context: .recipe(recipeID), recipeID: recipeID).fetch(db) == nil)
        #expect(try RecipeRowNoteRequest(context: .menuItem(menuItemIDs[5]), recipeID: recipeID).fetch(db) == nil)
        #expect(try RecipeRowNoteRequest(context: .menuItem(missingID), recipeID: recipeID).fetch(db) == nil)
        expectNoDifference(
          try RecipeRowNoteRequest(context: .mealPlanItem(mealPlanItemID), recipeID: recipeID).fetch(db),
          RecipeRowNote(text: "Calendar note", origin: .day(date: scheduledDate, slot: .lunch))
        )
      }
    }

    @Test
    func persistsScaleIndependentlyPerPlacement() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 812_100_000)
      let recipeID = SampleUUIDSequence.uuid(35_001)
      var uuids = SampleUUIDSequence(start: 35_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Scaled Chicken",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let menuID = try MenuRepository.addMenu(
          title: "Scale Menu",
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
        let mealPlanItemID = try MealCalendarRepository.addRecipeItem(
          recipeID: recipeID,
          on: scheduledDate,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        expectNoDifference(try RecipeScaleRepository.scale(for: .recipe(recipeID), in: db), 1.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .menuItem(menuItemID), in: db), 1.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .mealPlanItem(mealPlanItemID), in: db), 1.0)

        try RecipeScaleRepository.setScale(2.0, for: .recipe(recipeID), in: db)
        try RecipeScaleRepository.setScale(3.0, for: .menuItem(menuItemID), in: db)
        try RecipeScaleRepository.setScale(0.5, for: .mealPlanItem(mealPlanItemID), in: db)

        expectNoDifference(try RecipeScaleRepository.scale(for: .recipe(recipeID), in: db), 2.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .menuItem(menuItemID), in: db), 3.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .mealPlanItem(mealPlanItemID), in: db), 0.5)
      }
    }

    @Test
    func recipeScaleRequestReadsTheContextScale() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 812_200_000)
      let recipeID = SampleUUIDSequence.uuid(35_201)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Request Chicken",
            dateCreated: now,
            dateModified: now,
            viewScale: 1.5
          )
        }
        .execute(db)

        expectNoDifference(try RecipeScaleRequest(context: .recipe(recipeID)).fetch(db), 1.5)
      }
    }
  }
}
