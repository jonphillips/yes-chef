import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeSyncRepairTests {
    @Test
    func repairRequeuesOnlyChildrenOfServerRecipesAndRelinksUniqueTitles() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
      let serverRecipeID = SampleUUIDSequence.uuid(70_000)
      let unsentRecipeID = SampleUUIDSequence.uuid(70_001)
      let duplicateRecipeID = SampleUUIDSequence.uuid(70_002)
      let secondDuplicateRecipeID = SampleUUIDSequence.uuid(70_003)
      let emptyPhotoID = SampleUUIDSequence.uuid(70_004)
      let keptPhotoID = SampleUUIDSequence.uuid(70_005)
      let menuID = SampleUUIDSequence.uuid(70_006)
      let rows = [
        MealPlanItem(id: SampleUUIDSequence.uuid(70_010), kind: .recipe, title: "Unique", scheduledDate: now, mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now),
        MealPlanItem(id: SampleUUIDSequence.uuid(70_011), kind: .recipe, title: "Missing", scheduledDate: now, mealSlot: .dinner, sortOrder: 1, dateCreated: now, dateModified: now),
        MealPlanItem(id: SampleUUIDSequence.uuid(70_012), kind: .recipe, title: "Duplicate", scheduledDate: now, mealSlot: .dinner, sortOrder: 2, dateCreated: now, dateModified: now),
        MealPlanItem(id: SampleUUIDSequence.uuid(70_013), kind: .recipe, title: "Unsent", scheduledDate: now, mealSlot: .dinner, sortOrder: 3, dateCreated: now, dateModified: now),
      ]
      let menuItems = [
        MenuItem(id: SampleUUIDSequence.uuid(70_020), menuID: menuID, kind: .recipe, title: "Unique", dayOffset: 0, mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now),
        MenuItem(id: SampleUUIDSequence.uuid(70_021), menuID: menuID, kind: .recipe, title: "Missing", dayOffset: 0, mealSlot: .dinner, sortOrder: 1, dateCreated: now, dateModified: now),
      ]

      try await database.write { db in
        try Recipe.insert {
          Recipe(id: serverRecipeID, title: "Unique", dateCreated: now, dateModified: now, coverPhotoID: emptyPhotoID)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: unsentRecipeID, title: "Unsent", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: duplicateRecipeID, title: "Duplicate", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: secondDuplicateRecipeID, title: "Duplicate", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: SampleUUIDSequence.uuid(70_030), recipeID: serverRecipeID, sortOrder: 0)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: SampleUUIDSequence.uuid(70_031), recipeID: unsentRecipeID, sortOrder: 0)
        }
        .execute(db)
        try RecipePhoto.insert {
          RecipePhoto(id: emptyPhotoID, recipeID: serverRecipeID, imageDataReference: "empty", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try RecipePhoto.insert {
          RecipePhoto(
            id: keptPhotoID,
            recipeID: serverRecipeID,
            imageDataReference: "reference",
            displayData: Data([1]),
            kind: .referenceDocument,
            source: .extracted,
            sortOrder: 1,
            dateCreated: now
          )
        }
        .execute(db)
        try MealPlanItem.insert { rows }.execute(db)
        try Menu.insert {
          Menu(id: menuID, title: "Menu", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try MenuItem.insert { menuItems }.execute(db)
      }

      let onServer: Set<RecipeSyncRecordID> = [
        RecipeSyncRecordID(table: Recipe.tableName, primaryKey: serverRecipeID.uuidString),
        RecipeSyncRecordID(table: Recipe.tableName, primaryKey: duplicateRecipeID.uuidString),
        RecipeSyncRecordID(table: Recipe.tableName, primaryKey: secondDuplicateRecipeID.uuidString),
      ]
      let audit = try await database.write { db in
        try RecipeSyncRepair.run(onServerRecords: onServer, in: db)
      }

      #expect(audit.deletedPhotoCount == 1)
      #expect(audit.requeuedRecipeCount == 1)
      #expect(audit.requeuedChildCount >= 1)
      #expect(audit.skippedForUnsentParentCount >= 1)
      #expect(audit.linkedMealPlanCount == 1)
      #expect(audit.unmatchedMealPlanCount == 2)
      #expect(audit.ambiguousMealPlanCount == 1)
      #expect(audit.linkedMenuCount == 1)
      #expect(audit.unmatchedMenuCount == 1)

      try await database.read { db in
        let serverRecipe = try Recipe.find(serverRecipeID).fetchOne(db)
        let emptyPhoto = try RecipePhoto.find(emptyPhotoID).fetchOne(db)
        let keptPhoto = try RecipePhoto.find(keptPhotoID).fetchOne(db)
        let linkedMealPlan = try MealPlanItem.find(rows[0].id).fetchOne(db)
        let ambiguousMealPlan = try MealPlanItem.find(rows[2].id).fetchOne(db)
        let unsentMealPlan = try MealPlanItem.find(rows[3].id).fetchOne(db)
        let linkedMenu = try MenuItem.find(menuItems[0].id).fetchOne(db)
        #expect(serverRecipe?.coverPhotoID == nil)
        #expect(emptyPhoto == nil)
        #expect(keptPhoto?.displayData == Data([1]))
        #expect(linkedMealPlan?.recipeID == serverRecipeID)
        #expect(ambiguousMealPlan?.recipeID == nil)
        #expect(unsentMealPlan?.recipeID == nil)
        #expect(linkedMenu?.recipeID == serverRecipeID)
      }
    }

    @Test
    func repairWithNoServerRecipeOnlyDeletesByteLessPhotos() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_100_000)
      let recipeID = SampleUUIDSequence.uuid(71_000)
      let emptyPhotoID = SampleUUIDSequence.uuid(71_001)
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Local", dateCreated: now, dateModified: now, coverPhotoID: emptyPhotoID)
        }
        .execute(db)
        try RecipePhoto.insert {
          RecipePhoto(id: emptyPhotoID, recipeID: recipeID, imageDataReference: "empty", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
      }

      let audit = try await database.write { db in
        try RecipeSyncRepair.run(onServerRecords: [], in: db)
      }
      #expect(audit.deletedPhotoCount == 1)
      #expect(audit.requeuedRecipeCount == 0)
      try await database.read { db in
        let photos = try RecipePhoto.fetchAll(db)
        let recipe = try Recipe.find(recipeID).fetchOne(db)
        #expect(!photos.contains(where: { $0.id == emptyPhotoID }))
        #expect(recipe?.coverPhotoID == nil)
      }
    }
  }
}
