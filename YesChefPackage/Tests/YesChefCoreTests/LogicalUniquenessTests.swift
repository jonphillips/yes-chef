import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct LogicalUniquenessTests {
    @Test
    func sourceBackedImportIdentityConvergesDuplicateRefsAndRecipeReferences() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_000_000)
      let later = now.addingTimeInterval(60)
      let winnerID = SampleUUIDSequence.uuid(31_001)
      let loserID = SampleUUIDSequence.uuid(31_002)
      let incomingID = SampleUUIDSequence.uuid(31_003)
      let sourceURL = "https://example.com/recipes/sync-race"

      let result = try database.write { db in
        try Recipe.insert {
          Recipe(id: winnerID, title: "Sync Race Stew", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: loserID, title: "Sync Race Stew", dateCreated: later, dateModified: later)
        }
        .execute(db)
        try RecipeImportRef.insert {
          RecipeImportRef(
            id: SampleUUIDSequence.uuid(31_010),
            recipeID: winnerID,
            normalizedSourceURL: sourceURL,
            normalizedTitle: "sync race stew",
            dateCreated: now
          )
        }
        .execute(db)
        try RecipeImportRef.insert {
          RecipeImportRef(
            id: SampleUUIDSequence.uuid(31_011),
            recipeID: loserID,
            normalizedSourceURL: sourceURL,
            normalizedTitle: "sync race stew",
            dateCreated: later
          )
        }
        .execute(db)

        try MealPlanItem.insert {
          MealPlanItem(
            id: SampleUUIDSequence.uuid(31_020),
            kind: .recipe,
            recipeID: loserID,
            title: "Dinner",
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
            id: SampleUUIDSequence.uuid(31_030),
            title: "Weekend",
            dayCount: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try MenuItem.insert {
          MenuItem(
            id: SampleUUIDSequence.uuid(31_031),
            menuID: SampleUUIDSequence.uuid(31_030),
            kind: .recipe,
            recipeID: loserID,
            title: "Sync Race Stew",
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryList.insert {
          GroceryList(
            id: SampleUUIDSequence.uuid(31_040),
            title: "Groceries",
            sortOrder: 0,
            isDefault: true,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: SampleUUIDSequence.uuid(31_041),
            groceryListID: SampleUUIDSequence.uuid(31_040),
            title: "Carrots",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItemSource.insert {
          GroceryItemSource(
            id: SampleUUIDSequence.uuid(31_042),
            groceryItemID: SampleUUIDSequence.uuid(31_041),
            origin: .recipe,
            recipeID: loserID,
            sourceTitle: "Sync Race Stew",
            dateCreated: now
          )
        }
        .execute(db)

        return try RecipeRepository.importBundle(
          RecipeBundleCoding.RecipeBundle(
            recipe: Recipe(id: incomingID, title: "Sync Race Stew", dateCreated: later, dateModified: later),
            source: RecipeSource(
              id: SampleUUIDSequence.uuid(31_050),
              recipeID: incomingID,
              url: sourceURL
            )
          ),
          in: db,
          now: later,
          uuid: { SampleUUIDSequence.uuid(31_060) }
        )
      }

      let snapshot = try database.read { db in
        (
          recipes: try Recipe.fetchAll(db).map(\.id).sorted { $0.uuidString < $1.uuidString },
          refs: try RecipeImportRef.fetchAll(db).map(\.recipeID),
          mealPlanRecipeIDs: try MealPlanItem.fetchAll(db).map(\.recipeID),
          menuItemRecipeIDs: try MenuItem.fetchAll(db).map(\.recipeID),
          grocerySourceRecipeIDs: try GroceryItemSource.fetchAll(db).map(\.recipeID)
        )
      }

      expectNoDifference(result.outcome, .alreadyImported)
      expectNoDifference(result.recipeID, winnerID)
      expectNoDifference(snapshot.recipes, [winnerID])
      expectNoDifference(snapshot.refs, [winnerID])
      expectNoDifference(snapshot.mealPlanRecipeIDs, [winnerID])
      expectNoDifference(snapshot.menuItemRecipeIDs, [winnerID])
      expectNoDifference(snapshot.grocerySourceRecipeIDs, [winnerID])
    }

    @Test
    func defaultGroceryListReadConvergesToOneDefaultWithoutDeletingLists() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_100_000)
      let firstID = SampleUUIDSequence.uuid(32_001)
      let secondID = SampleUUIDSequence.uuid(32_002)

      let defaultID = try database.write { db in
        try GroceryList.delete().execute(db)
        try GroceryList.insert {
          GroceryList(id: firstID, title: "Primary", sortOrder: 0, isDefault: true, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try GroceryList.insert {
          GroceryList(id: secondID, title: "Secondary", sortOrder: 1, isDefault: true, dateCreated: now, dateModified: now)
        }
        .execute(db)

        return try GroceryRepository.ensureDefaultList(
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { SampleUUIDSequence.uuid(32_010) }
        )
      }

      let lists = try database.read { db in
        try GroceryList.fetchAll(db).sorted { $0.sortOrder < $1.sortOrder }
      }
      expectNoDifference(defaultID, firstID)
      expectNoDifference(lists.map(\.id), [firstID, secondID])
      expectNoDifference(lists.map(\.isDefault), [true, false])
    }

    @Test
    func pantryLookupConvergesDuplicateTitles() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_200_000)
      let canonicalID = SampleUUIDSequence.uuid(33_001)
      let duplicateID = SampleUUIDSequence.uuid(33_002)

      let itemID = try database.write { db in
        try PantryItem.insert {
          PantryItem(id: canonicalID, title: "Sugar", sortOrder: 0, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try PantryItem.insert {
          PantryItem(
            id: duplicateID,
            title: "sugar",
            notes: "Baking",
            sortOrder: 1,
            dateCreated: now.addingTimeInterval(60),
            dateModified: now.addingTimeInterval(60)
          )
        }
        .execute(db)

        return try PantryRepository.addItem(
          title: "SUGAR",
          in: db,
          now: now.addingTimeInterval(120),
          uuid: { SampleUUIDSequence.uuid(33_010) }
        )
      }

      let items = try database.read { db in
        try PantryItem.fetchAll(db)
      }
      expectNoDifference(itemID, canonicalID)
      expectNoDifference(items.map(\.id), [canonicalID])
      expectNoDifference(items.first?.notes, "Baking")
    }

    @Test
    func tagAndCategoryReconciliationConvergesDuplicateNamesAndReferences() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_300_000)
      let recipeID = SampleUUIDSequence.uuid(34_001)
      let tagID = SampleUUIDSequence.uuid(34_010)
      let duplicateTagID = SampleUUIDSequence.uuid(34_011)
      let categoryID = SampleUUIDSequence.uuid(34_020)
      let duplicateCategoryID = SampleUUIDSequence.uuid(34_021)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Tagged Dinner", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Tag.insert {
          Tag(id: tagID, name: "Weeknight", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Tag.insert {
          Tag(id: duplicateTagID, name: "weeknight", sortOrder: 1, dateCreated: now.addingTimeInterval(60))
        }
        .execute(db)
        try RecipeTag.insert {
          RecipeTag(id: SampleUUIDSequence.uuid(34_012), recipeID: recipeID, tagID: duplicateTagID, sortOrder: 0)
        }
        .execute(db)
        try Category.insert {
          Category(id: categoryID, name: "Dinner", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Category.insert {
          Category(id: duplicateCategoryID, name: "dinner", sortOrder: 1, dateCreated: now.addingTimeInterval(60))
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(id: SampleUUIDSequence.uuid(34_022), recipeID: recipeID, categoryID: duplicateCategoryID)
        }
        .execute(db)

        _ = try RecipeRepository.save(
          draft: RecipeEditorDraft(
            title: "New Dinner",
            ingredientText: "1 carrot",
            instructionText: "Cook.",
            tagNames: "Weeknight",
            categoryNames: "Dinner"
          ),
          in: db,
          now: now.addingTimeInterval(120),
          uuid: { SampleUUIDSequence.uuid(34_100) }
        )
      }

      let snapshot = try database.read { db in
        (
          tags: try Tag.fetchAll(db),
          recipeTagIDs: try RecipeTag.fetchAll(db).map(\.tagID),
          categories: try Category.fetchAll(db),
          recipeCategoryIDs: try RecipeCategory.fetchAll(db).map(\.categoryID)
        )
      }
      expectNoDifference(snapshot.tags.map(\.id), [tagID])
      expectNoDifference(Set(snapshot.recipeTagIDs), [tagID])
      expectNoDifference(snapshot.categories.map(\.id), [categoryID])
      expectNoDifference(Set(snapshot.recipeCategoryIDs), [categoryID])
    }
  }
}
