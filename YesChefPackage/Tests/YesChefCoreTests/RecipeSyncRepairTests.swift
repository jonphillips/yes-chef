import Dependencies
import Foundation
import GRDB
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
        try createRepairMetadataFixture(in: db)
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

      let recipeMetadata = [
        RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, serverRecipeID), hasServerChangeTag: true),
        RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, duplicateRecipeID), hasServerChangeTag: true),
        RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, secondDuplicateRecipeID), hasServerChangeTag: true),
      ]
      try await database.write { db in
        try rememberForRepair([serverRecipeID], in: db)
      }
      let audit = try await database.write { db in
        try RecipeSyncRepair.run(
          recipeMetadata: recipeMetadata,
          syncedTableNames: ["recipes", "ingredientSections", "recipePhotos", "mealPlanItems", "menus", "menuItems"],
          childMetadataFor: { _, _, _ in [] },
          in: db
        )
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
        try createRepairMetadataFixture(in: db)
        return try RecipeSyncRepair.run(
          recipeMetadata: [],
          syncedTableNames: [],
          childMetadataFor: { _, _, _ in [] },
          in: db
        )
      }
      #expect(audit.deletedPhotoCount == 1)
      #expect(audit.requeuedRecipeCount == 1)
      try await database.read { db in
        let photos = try RecipePhoto.fetchAll(db)
        let recipe = try Recipe.find(recipeID).fetchOne(db)
        #expect(!photos.contains(where: { $0.id == emptyPhotoID }))
        #expect(recipe?.coverPhotoID == nil)
      }
    }

    @Test
    func repairChunksParentAndRequeueIDsBeyondOneSQLiteParameterBatch() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_200_000)
      let recipes = (0..<1_100).map { offset in
        Recipe(id: SampleUUIDSequence.uuid(72_000 + offset), title: "Recipe \(offset)", dateCreated: now, dateModified: now)
      }
      let sections = recipes.enumerated().map { offset, recipe in
        IngredientSection(id: SampleUUIDSequence.uuid(74_000 + offset), recipeID: recipe.id, sortOrder: 0)
      }
      try await database.write { db in
        try createRepairMetadataFixture(in: db)
        try Recipe.insert { recipes }.execute(db)
        try IngredientSection.insert { sections }.execute(db)
        try rememberForRepair(recipes.map(\.id), in: db)
      }

      let recipeMetadata = recipes.map {
        RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, $0.id), hasServerChangeTag: true)
      }
      let audit = try await database.write { db in
        try RecipeSyncRepair.run(
          recipeMetadata: recipeMetadata,
          syncedTableNames: ["recipes", "ingredientSections"],
          childMetadataFor: { _, _, _ in [] },
          in: db
        )
      }

      #expect(audit.requeuedRecipeCount == 0)
      #expect(audit.requeuedChildCount == sections.count)
    }

    @Test
    func repairLeavesLocalRecipeChildrenAlone() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_300_000)
      let recipeID = SampleUUIDSequence.uuid(75_000)
      let variationID = SampleUUIDSequence.uuid(75_001)
      let activeVariationID = SampleUUIDSequence.uuid(75_002)
      try await database.write { db in
        try createRepairMetadataFixture(in: db)
        try Recipe.insert {
          Recipe(id: recipeID, title: "Local child", dateCreated: now, dateModified: now)
        }.execute(db)
        try RecipeVariation.insert {
          RecipeVariation(id: variationID, recipeID: recipeID, name: "Variation", sortIndex: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try RecipeActiveVariation.insert {
          RecipeActiveVariation(id: activeVariationID, recipeID: recipeID, variationID: variationID, dateModified: now)
        }.execute(db)
        try rememberForRepair([recipeID], in: db)
      }

      let audit = try await database.write { db in
        try RecipeSyncRepair.run(
          recipeMetadata: [
            RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, recipeID), hasServerChangeTag: true),
            RecipeSyncMetadataState(recordID: recordID(RecipeVariation.tableName, variationID), hasServerChangeTag: true),
          ],
          syncedTableNames: ["recipes", "recipeVariations"],
          childMetadataFor: { table, ids, _ in
            table == "recipeVariations"
              ? ids.map { RecipeSyncMetadataState(recordID: RecipeSyncRecordID(table: table, primaryKey: $0), hasServerChangeTag: true) }
              : []
          },
          in: db
        )
      }

      #expect(audit.requeuedChildCount == 0)
      #expect(audit.hasFindings == false)
      let activeVariation = try await database.read { db in
        try RecipeActiveVariation.find(activeVariationID).fetchOne(db)
      }
      #expect(activeVariation?.id == activeVariationID)
    }

    @Test
    func unconfirmedRecipeIsClearedThenItsChildrenAreProcessedAfterConfirmation() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_400_000)
      let recipeID = SampleUUIDSequence.uuid(76_000)
      let sectionID = SampleUUIDSequence.uuid(76_001)
      try await database.write { db in
        try createRepairMetadataFixture(in: db)
        try Recipe.insert {
          Recipe(id: recipeID, title: "Needs a fresh record", dateCreated: now, dateModified: now)
        }.execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }.execute(db)
        try insertRepairMetadata(recordID(Recipe.tableName, recipeID), cachedRecord: Data([1]), allFieldsRecord: Data([2]), in: db)
        try insertRepairMetadata(recordID("ingredientSections", sectionID), cachedRecord: Data([3]), allFieldsRecord: Data([4]), in: db)
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "recipeSyncRepairTestUpdates" ("recordID" TEXT NOT NULL)"#)
        try db.execute(sql: #"CREATE TRIGGER IF NOT EXISTS "recipeSyncRepairCaptureIDUpdate" AFTER UPDATE OF "id" ON "recipes" WHEN OLD."id" = NEW."id" BEGIN INSERT INTO "recipeSyncRepairTestUpdates" ("recordID") VALUES (NEW."id"); END"#)
        try db.execute(sql: #"DELETE FROM "recipeSyncRepairTestUpdates""#)
      }

      let syncedTables: Set<String> = ["recipes", "ingredientSections"]
      let firstPass = try await database.write { db in
        try RecipeSyncRepair.run(
          recipeMetadata: [RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, recipeID), hasServerChangeTag: false)],
          syncedTableNames: syncedTables,
          childMetadataFor: { _, _, _ in
            #expect(Bool(false), "Children must wait for a confirmed parent")
            return []
          },
          in: db
        )
      }
      #expect(firstPass.requeuedRecipeCount == 1)
      #expect(firstPass.requeuedChildCount == 0)
      let afterFirstPass = try await database.read { db in
        let metadata = (
          try Data.fetchOne(db, sql: #"SELECT "lastKnownServerRecord" FROM "sqlitedata_icloud_metadata" WHERE "recordType" = ? AND "recordPrimaryKey" = ?"#, arguments: [Recipe.tableName, recipeID.uuidString.lowercased()]),
          try Data.fetchOne(db, sql: #"SELECT "_lastKnownServerRecordAllFields" FROM "sqlitedata_icloud_metadata" WHERE "recordType" = ? AND "recordPrimaryKey" = ?"#, arguments: [Recipe.tableName, recipeID.uuidString.lowercased()])
        )
        let queue = try String.fetchAll(db, sql: #"SELECT "recipeID" FROM "recipeSyncRepairQueue""#)
        let sectionRecord = try Data.fetchOne(db, sql: #"SELECT "lastKnownServerRecord" FROM "sqlitedata_icloud_metadata" WHERE "recordType" = ? AND "recordPrimaryKey" = ?"#, arguments: ["ingredientSections", sectionID.uuidString.lowercased()])
        let idUpdates = try String.fetchAll(db, sql: #"SELECT "recordID" FROM "recipeSyncRepairTestUpdates""#)
        return (metadata, queue, sectionRecord, idUpdates)
      }
      #expect(afterFirstPass.0.0 == nil)
      #expect(afterFirstPass.0.1 == nil)
      #expect(afterFirstPass.1.contains(recipeID.uuidString.lowercased()))
      #expect(afterFirstPass.2 == Data([3]))
      #expect(afterFirstPass.3.isEmpty)

      let secondPass = try await database.write { db in
        try RecipeSyncRepair.run(
          recipeMetadata: [RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, recipeID), hasServerChangeTag: true)],
          syncedTableNames: syncedTables,
          childMetadataFor: { table, ids, _ in
            ids.map { RecipeSyncMetadataState(recordID: RecipeSyncRecordID(table: table, primaryKey: $0), hasServerChangeTag: false) }
          },
          in: db
        )
      }
      #expect(secondPass.requeuedChildCount == 1)
      let afterSecondPass = try await database.read { db in
        let childRecord = try Data.fetchOne(db, sql: #"SELECT "lastKnownServerRecord" FROM "sqlitedata_icloud_metadata" WHERE "recordType" = ? AND "recordPrimaryKey" = ?"#, arguments: ["ingredientSections", sectionID.uuidString.lowercased()])
        let queue = try String.fetchAll(db, sql: #"SELECT "recipeID" FROM "recipeSyncRepairQueue""#)
        return (childRecord, queue)
      }
      #expect(afterSecondPass.0 == nil)
      #expect(!afterSecondPass.1.contains(recipeID.uuidString.lowercased()))

      let thirdPass = try await database.write { db in
        let audit = try RecipeSyncRepair.run(
          recipeMetadata: [RecipeSyncMetadataState(recordID: recordID(Recipe.tableName, recipeID), hasServerChangeTag: true)],
          syncedTableNames: syncedTables,
          childMetadataFor: { _, _, _ in
            #expect(Bool(false), "A drained parent must not be inspected again")
            return []
          },
          in: db
        )
        return audit
      }
      #expect(thirdPass.requeuedChildCount == 0)
      #expect(thirdPass.hasFindings == false)
    }
  }
}

private func recordID(_ table: String, _ id: UUID) -> RecipeSyncRecordID {
  RecipeSyncRecordID(table: table, primaryKey: id.uuidString)
}

private func createRepairMetadataFixture(in db: Database) throws {
  try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_metadata" ("recordPrimaryKey" TEXT NOT NULL, "recordType" TEXT NOT NULL, "lastKnownServerRecord" BLOB, "_lastKnownServerRecordAllFields" BLOB, PRIMARY KEY ("recordPrimaryKey", "recordType"))"#)
}

private func insertRepairMetadata(
  _ recordID: RecipeSyncRecordID,
  cachedRecord: Data,
  allFieldsRecord: Data,
  in db: Database
) throws {
  try db.execute(
    sql: #"INSERT INTO "sqlitedata_icloud_metadata" ("recordPrimaryKey", "recordType", "lastKnownServerRecord", "_lastKnownServerRecordAllFields") VALUES (?, ?, ?, ?)"#,
    arguments: [recordID.primaryKey, recordID.table, cachedRecord, allFieldsRecord]
  )
}

private func rememberForRepair(_ ids: [UUID], in db: Database) throws {
  for start in stride(from: 0, to: ids.count, by: 500) {
    let chunk = ids[start..<min(start + 500, ids.count)]
    let values = chunk.map { _ in "(?)" }.joined(separator: ", ")
    try db.execute(
      sql: "INSERT INTO \"recipeSyncRepairQueue\" (\"recipeID\") VALUES \(values)",
      arguments: StatementArguments(chunk.map { $0.uuidString.lowercased() })
    )
  }
}
