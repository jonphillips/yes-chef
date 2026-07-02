import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeArchiveTests {
    @Test
    func archiveRecipeMarksRecipeArchivedRemovesPlacementsAndPreservesChildren() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
      let archivedAt = now.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(201)
      let sectionID = SampleUUIDSequence.uuid(202)
      let lineID = SampleUUIDSequence.uuid(203)
      let mealPlanItemID = SampleUUIDSequence.uuid(204)
      let menuID = SampleUUIDSequence.uuid(205)
      let menuItemID = SampleUUIDSequence.uuid(206)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Archive Me",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lineID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 onion",
            quantity: 1,
            quantityText: "1",
            item: "onion",
            sortOrder: 0,
            confidence: .medium
          )
        }
        .execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: mealPlanItemID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Archive Me",
            scheduledDate: now,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Archive Menu",
            dayCount: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try MenuItem.insert {
          MenuItem(
            id: menuItemID,
            menuID: menuID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Archive Me",
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        try RecipeRepository.archive(recipeID: recipeID, in: db, now: archivedAt)

        let archivedRecipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(archivedRecipe.archived, true)
        expectNoDifference(archivedRecipe.dateModified, archivedAt)

        let visibleRecipeIDs = try Recipe.fetchAll(db)
          .filter { !$0.archived }
          .map(\.id)
        expectNoDifference(visibleRecipeIDs.contains(recipeID), false)
        expectNoDifference(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db), nil)
        expectNoDifference(try MealPlanItem.find(mealPlanItemID).fetchOne(db), nil)
        expectNoDifference(try MenuItem.find(menuItemID).fetchOne(db), nil)
        expectNoDifference(try IngredientSection.find(sectionID).fetchOne(db)?.id, sectionID)
        expectNoDifference(try IngredientLine.find(lineID).fetchOne(db)?.id, lineID)

        try RecipeRepository.restore(recipeID: recipeID, in: db, now: archivedAt.addingTimeInterval(60))
        let restoredRecipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(restoredRecipe.archived, false)
        expectNoDifference(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)?.recipe.id, recipeID)
        expectNoDifference(try MealPlanItem.find(mealPlanItemID).fetchOne(db), nil)
        expectNoDifference(try MenuItem.find(menuItemID).fetchOne(db), nil)

        try RecipeRepository.archive(recipeID: recipeID, in: db, now: archivedAt.addingTimeInterval(120))
        try RecipeRepository.permanentlyDelete(recipeID: recipeID, in: db)
        expectNoDifference(try Recipe.find(recipeID).fetchOne(db), nil)
        expectNoDifference(try IngredientSection.find(sectionID).fetchOne(db), nil)
        expectNoDifference(try IngredientLine.find(lineID).fetchOne(db), nil)
      }
    }

    @Test
    func archivedRecipeReferencesDoNotResolveIntoCalendarOrMenus() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 802_050_000)
      let recipeID = SampleUUIDSequence.uuid(221)
      let mealPlanItemID = SampleUUIDSequence.uuid(222)
      let menuID = SampleUUIDSequence.uuid(223)
      let menuItemID = SampleUUIDSequence.uuid(224)
      let placementID = SampleUUIDSequence.uuid(225)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Archived Stale Reference",
            archived: true,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: mealPlanItemID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Archived Stale Reference",
            scheduledDate: now,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Archived Menu",
            dayCount: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try MenuItem.insert {
          MenuItem(
            id: menuItemID,
            menuID: menuID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Archived Stale Reference",
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try MenuPlacement.insert {
          MenuPlacement(
            id: placementID,
            menuID: menuID,
            startDate: now,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let calendarRows = try MealCalendarRequest().fetch(db)
        expectNoDifference(calendarRows.contains { $0.item.id == mealPlanItemID }, false)
        expectNoDifference(calendarRows.contains { $0.menuItem?.id == menuItemID }, false)
        let detail = try #require(try MenuDetailRequest(menuID: menuID).fetch(db))
        expectNoDifference(detail.itemRows.map(\.id), [])
      }
    }
  }
}
