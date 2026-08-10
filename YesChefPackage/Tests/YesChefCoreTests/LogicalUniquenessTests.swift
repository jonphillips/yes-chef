import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct LogicalUniquenessTests {
  }

  @Suite
  struct ImportDuplicateConvergenceTests {
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
        return (
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
    func sourceBackedImportIdentityKeepsDivergentRecipeContentAndReportsCollision() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_010_000)
      let later = now.addingTimeInterval(60)
      let canonicalID = SampleUUIDSequence.uuid(31_101)
      let divergentID = SampleUUIDSequence.uuid(31_102)
      let incomingID = SampleUUIDSequence.uuid(31_103)
      let sourceURL = "https://example.com/recipes/edited-sync-race"

      let bundle = RecipeBundleCoding.RecipeBundle(
        recipe: Recipe(id: incomingID, title: "Sync Race Stew", dateCreated: later, dateModified: later),
        source: RecipeSource(id: SampleUUIDSequence.uuid(31_150), recipeID: incomingID, url: sourceURL)
      )

      try database.write { db in
        try Recipe.insert {
          Recipe(id: canonicalID, title: "Sync Race Stew", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: divergentID, title: "Sync Race Stew", dateCreated: later, dateModified: later)
        }
        .execute(db)
        try RecipeImportRef.insert {
          RecipeImportRef(
            id: SampleUUIDSequence.uuid(31_110),
            recipeID: canonicalID,
            normalizedSourceURL: sourceURL,
            normalizedTitle: "sync race stew",
            dateCreated: now
          )
        }
        .execute(db)
        try RecipeImportRef.insert {
          RecipeImportRef(
            id: SampleUUIDSequence.uuid(31_111),
            recipeID: divergentID,
            normalizedSourceURL: sourceURL,
            normalizedTitle: "sync race stew",
            dateCreated: later
          )
        }
        .execute(db)

        let instructionSectionID = SampleUUIDSequence.uuid(31_120)
        try InstructionSection.insert {
          InstructionSection(id: instructionSectionID, recipeID: divergentID, name: "Method", sortOrder: 0)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(
            id: SampleUUIDSequence.uuid(31_121),
            recipeID: divergentID,
            sectionID: instructionSectionID,
            text: "Toast the spices until fragrant.",
            sortOrder: 0
          )
        }
        .execute(db)
        try RecipeNote.insert {
          RecipeNote(
            id: SampleUUIDSequence.uuid(31_122),
            recipeID: divergentID,
            text: "Use the extra-hot smoked paprika.",
            dateCreated: later,
            dateModified: later
          )
        }
        .execute(db)
        try RecipePhoto.insert {
          RecipePhoto(
            id: SampleUUIDSequence.uuid(31_123),
            recipeID: divergentID,
            imageDataReference: "photos/sync-race.jpg",
            caption: "My finished stew",
            sortOrder: 0,
            dateCreated: later
          )
        }
        .execute(db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: SampleUUIDSequence.uuid(31_124),
            recipeID: divergentID,
            name: "Smoky",
            note: "Add chipotle.",
            sortIndex: 0,
            dateCreated: later,
            dateModified: later
          )
        }
        .execute(db)

        try MealPlanItem.insert {
          MealPlanItem(
            id: SampleUUIDSequence.uuid(31_130),
            kind: .recipe,
            recipeID: divergentID,
            title: "Dinner",
            scheduledDate: later,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: later,
            dateModified: later
          )
        }
        .execute(db)
      }

      let preview = try database.read { db in
        try RecipeRepository.previewImportBundles(
          [bundle],
          against: try RecipeImportRef.fetchAll(db),
          in: db
        )
      }
      let result = try database.write { db in
        try RecipeRepository.importBundle(bundle, in: db, now: later, uuid: { SampleUUIDSequence.uuid(31_160) })
      }
      let snapshot = try database.read { db in
        let recipeIDs = try Recipe.fetchAll(db).map(\.id).sorted { $0.uuidString < $1.uuidString }
        let importRefRecipeIDs = try RecipeImportRef.fetchAll(db).map(\.recipeID).sorted {
          $0.uuidString < $1.uuidString
        }
        let steps = try InstructionStep.where { $0.recipeID.eq(divergentID) }.fetchAll(db).map(\.text)
        let notes = try RecipeNote.where { $0.recipeID.eq(divergentID) }.fetchAll(db).map(\.text)
        let photos = try RecipePhoto.where { $0.recipeID.eq(divergentID) }.fetchAll(db).map(\.caption)
        let variations = try RecipeVariation.where { $0.recipeID.eq(divergentID) }.fetchAll(db).map(\.name)
        return (
          recipeIDs: recipeIDs,
          importRefRecipeIDs: importRefRecipeIDs,
          steps: steps,
          notes: notes,
          photos: photos,
          variations: variations,
          mealPlanRecipeIDs: try MealPlanItem.fetchAll(db).map(\.recipeID)
        )
      }

      let warning = RecipeImportWarning.Kind.ambiguousImportIdentity
      expectNoDifference(preview.results[0].recipeID, canonicalID)
      expectNoDifference(preview.results[0].status, .alreadyImported)
      expectNoDifference(preview.warnings.map(\.kind), [warning])
      expectNoDifference(result.recipeID, canonicalID)
      expectNoDifference(result.outcome, .alreadyImported)
      expectNoDifference(result.warnings.map(\.kind), [warning])
      expectNoDifference(snapshot.recipeIDs, [canonicalID, divergentID].sorted { $0.uuidString < $1.uuidString })
      expectNoDifference(snapshot.importRefRecipeIDs, [canonicalID, divergentID].sorted { $0.uuidString < $1.uuidString })
      expectNoDifference(snapshot.steps, ["Toast the spices until fragrant."])
      expectNoDifference(snapshot.notes, ["Use the extra-hot smoked paprika."])
      expectNoDifference(snapshot.photos, ["My finished stew"])
      expectNoDifference(snapshot.variations, ["Smoky"])
      expectNoDifference(snapshot.mealPlanRecipeIDs, [divergentID])
    }

    @Test
    func sourceBackedImportIdentityMergesOnlyEmptyHusksInAMixedCollision() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_020_000)
      let later = now.addingTimeInterval(60)
      let canonicalID = SampleUUIDSequence.uuid(31_201)
      let huskID = SampleUUIDSequence.uuid(31_202)
      let divergentID = SampleUUIDSequence.uuid(31_203)
      let incomingID = SampleUUIDSequence.uuid(31_204)
      let sourceURL = "https://example.com/recipes/mixed-sync-race"

      let result = try database.write { db in
        for (recipeID, date) in [(canonicalID, now), (huskID, later), (divergentID, later.addingTimeInterval(1))] {
          try Recipe.insert {
            Recipe(id: recipeID, title: "Mixed Sync Race", dateCreated: date, dateModified: date)
          }
          .execute(db)
        }
        for (id, recipeID, date) in [
          (SampleUUIDSequence.uuid(31_210), canonicalID, now),
          (SampleUUIDSequence.uuid(31_211), huskID, later),
          (SampleUUIDSequence.uuid(31_212), divergentID, later.addingTimeInterval(1)),
        ] {
          try RecipeImportRef.insert {
            RecipeImportRef(
              id: id,
              recipeID: recipeID,
              normalizedSourceURL: sourceURL,
              normalizedTitle: "mixed sync race",
              dateCreated: date
            )
          }
          .execute(db)
        }
        try RecipeNote.insert {
          RecipeNote(
            id: SampleUUIDSequence.uuid(31_213),
            recipeID: divergentID,
            text: "Keep this edited copy.",
            dateCreated: later,
            dateModified: later
          )
        }
        .execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: SampleUUIDSequence.uuid(31_214),
            kind: .recipe,
            recipeID: huskID,
            title: "Husk dinner",
            scheduledDate: later,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: later,
            dateModified: later
          )
        }
        .execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: SampleUUIDSequence.uuid(31_215),
            kind: .recipe,
            recipeID: divergentID,
            title: "Edited dinner",
            scheduledDate: later,
            mealSlot: .lunch,
            sortOrder: 0,
            dateCreated: later,
            dateModified: later
          )
        }
        .execute(db)

        return try RecipeRepository.importBundle(
          RecipeBundleCoding.RecipeBundle(
            recipe: Recipe(id: incomingID, title: "Mixed Sync Race", dateCreated: later, dateModified: later),
            source: RecipeSource(id: SampleUUIDSequence.uuid(31_216), recipeID: incomingID, url: sourceURL)
          ),
          in: db,
          now: later,
          uuid: { SampleUUIDSequence.uuid(31_217) }
        )
      }
      let snapshot = try database.read { db in
        let recipeIDs = try Recipe.fetchAll(db).map(\.id).sorted { $0.uuidString < $1.uuidString }
        let importRefRecipeIDs = try RecipeImportRef.fetchAll(db).map(\.recipeID).sorted {
          $0.uuidString < $1.uuidString
        }
        let notes = try RecipeNote.where { $0.recipeID.eq(divergentID) }.fetchAll(db).map(\.text)
        let mealPlanRecipeIDs = try MealPlanItem.fetchAll(db).map(\.recipeID).sorted {
          ($0?.uuidString ?? "") < ($1?.uuidString ?? "")
        }
        return (
          recipeIDs: recipeIDs,
          importRefRecipeIDs: importRefRecipeIDs,
          notes: notes,
          mealPlanRecipeIDs: mealPlanRecipeIDs
        )
      }

      expectNoDifference(result.recipeID, canonicalID)
      expectNoDifference(result.outcome, .alreadyImported)
      expectNoDifference(result.warnings.map(\.kind), [.ambiguousImportIdentity])
      expectNoDifference(snapshot.recipeIDs, [canonicalID, divergentID].sorted { $0.uuidString < $1.uuidString })
      expectNoDifference(snapshot.importRefRecipeIDs, [canonicalID, divergentID].sorted { $0.uuidString < $1.uuidString })
      expectNoDifference(snapshot.notes, ["Keep this edited copy."])
      expectNoDifference(snapshot.mealPlanRecipeIDs, [canonicalID, divergentID].sorted { $0.uuidString < $1.uuidString })
    }

    @Test
    func titleOnlyImportIdentityStillDoesNotConvergeRecipes() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 814_030_000)
      let firstID = SampleUUIDSequence.uuid(31_301)
      let secondID = SampleUUIDSequence.uuid(31_302)
      let incomingID = SampleUUIDSequence.uuid(31_303)

      let result = try database.write { db in
        for recipeID in [firstID, secondID] {
          try Recipe.insert {
            Recipe(id: recipeID, title: "Untitled Stew", dateCreated: now, dateModified: now)
          }
          .execute(db)
        }
        for (id, recipeID) in [(SampleUUIDSequence.uuid(31_310), firstID), (SampleUUIDSequence.uuid(31_311), secondID)] {
          try RecipeImportRef.insert {
            RecipeImportRef(id: id, recipeID: recipeID, normalizedTitle: "untitled stew", dateCreated: now)
          }
          .execute(db)
        }
        return try RecipeRepository.importBundle(
          RecipeBundleCoding.RecipeBundle(
            recipe: Recipe(id: incomingID, title: "Untitled Stew", dateCreated: now, dateModified: now)
          ),
          in: db,
          now: now,
          uuid: { SampleUUIDSequence.uuid(31_312) }
        )
      }
      let recipeIDs = try database.read { db in
        try Recipe.fetchAll(db).map(\.id).sorted { $0.uuidString < $1.uuidString }
      }

      expectNoDifference(result.recipeID, incomingID)
      expectNoDifference(result.outcome, .imported)
      expectNoDifference(result.warnings.map(\.kind), [.titleOnlyCollision])
      expectNoDifference(recipeIDs, [firstID, secondID, incomingID].sorted { $0.uuidString < $1.uuidString })
    }

  }

  @Suite
  struct RemainingLogicalUniquenessTests {
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
    func legacyTagDraftInputReconcilesIntoCategoriesWithoutTouchingDormantTagRows() throws {
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
      expectNoDifference(Set(snapshot.tags.map(\.id)), [tagID, duplicateTagID])
      expectNoDifference(Set(snapshot.recipeTagIDs), [duplicateTagID])
      expectNoDifference(Set(snapshot.categories.map(\.id)), [categoryID, SampleUUIDSequence.uuid(34_100)])
      expectNoDifference(Set(snapshot.recipeCategoryIDs), [categoryID, SampleUUIDSequence.uuid(34_100)])
    }
  }
}
