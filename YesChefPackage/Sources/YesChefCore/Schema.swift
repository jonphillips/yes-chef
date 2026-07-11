import Dependencies
import Foundation
import SQLiteData

extension DependencyValues {
  public mutating func bootstrapDatabase() throws {
    @Dependency(\.context) var context
    let databasePath: String?
    let syncMode: YesChefCloudSync.BootstrapMode
    switch context {
    case .live:
      databasePath = try YesChefDatabaseStorage.prepareLiveSharedStore().path
      syncMode = .configured(startImmediately: false)
    case .preview, .test:
      databasePath = nil
      syncMode = .disabled
    }
    try bootstrapDatabase(path: databasePath, syncMode: syncMode)
  }

  public mutating func bootstrapDatabaseForShareExtension() throws {
    @Dependency(\.context) var context
    let databasePath: String?
    let syncMode: YesChefCloudSync.BootstrapMode
    switch context {
    case .live:
      databasePath = try YesChefDatabaseStorage.prepareLiveSharedStoreForExtension().path
      syncMode = .configured(startImmediately: false)
    case .preview, .test:
      databasePath = nil
      syncMode = .disabled
    }
    try bootstrapDatabase(path: databasePath, syncMode: syncMode)
  }

  public mutating func bootstrapDatabaseForShareExtension(path: String?) throws {
    try bootstrapDatabase(path: path, syncMode: .configured(startImmediately: false))
  }

  public mutating func bootstrapDatabase(path: String?) throws {
    try bootstrapDatabase(path: path, syncMode: .disabled)
  }

  public mutating func bootstrapDatabase(
    path: String?,
    syncMode: YesChefCloudSync.BootstrapMode
  ) throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.attachMetadatabase(containerIdentifier: YesChefCloudSync.containerIdentifier)
      #if DEBUG
        db.trace(options: .profile) { event in
          guard case let .profile(statement, duration) = event,
            statement.sql == "COMMIT TRANSACTION"
          else { return }

          AppLog.performance.log(
            "sqlite-commit duration=\(duration, privacy: .public)s synchronizing=\(SyncEngine.isSynchronizing, privacy: .public)"
          )
        }
      #endif
    }

    let database = try SQLiteData.defaultDatabase(path: path, configuration: configuration)
    var migrator = DatabaseMigrator()
    #if DEBUG
      // Opt-in only. eraseDatabaseOnSchemaChange wipes the entire store whenever GRDB
      // decides the on-disk schema differs from the migration-defined one — and
      // SQLiteData's SyncEngine installs triggers on the synced tables at runtime, so
      // that comparison drifts on an ordinary rebuild and nukes the dogfood library
      // ("my database is gone"). Gate it behind an explicit launch argument: add
      // -YesChefEraseDatabaseOnSchemaChange to the scheme only when you actually want a
      // clean-slate dev DB, instead of firing on every DEBUG launch.
      migrator.eraseDatabaseOnSchemaChange =
        ProcessInfo.processInfo.arguments.contains("-YesChefEraseDatabaseOnSchemaChange")
    #endif

    migrator.registerMigration("Create MVP recipe library schema") { db in
      try #sql("""
        CREATE TABLE "recipes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL,
          "subtitle" TEXT,
          "summary" TEXT,
          "servings" REAL,
          "servingsText" TEXT,
          "yieldText" TEXT,
          "prepTimeMinutes" INTEGER,
          "cookTimeMinutes" INTEGER,
          "totalTimeMinutes" INTEGER,
          "activeTimeMinutes" INTEGER,
          "restTimeMinutes" INTEGER,
          "cuisine" TEXT,
          "course" TEXT,
          "difficulty" TEXT,
          "rating" INTEGER,
          "favorite" INTEGER NOT NULL DEFAULT 0,
          "archived" INTEGER NOT NULL DEFAULT 0,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL,
          "lastCookedAt" TEXT,
          "timesCooked" INTEGER NOT NULL DEFAULT 0,
          "originalImportText" TEXT,
          "originalSnapshot" BLOB
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipeSources" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "name" TEXT,
          "url" TEXT,
          "author" TEXT,
          "publicationName" TEXT,
          "bookTitle" TEXT,
          "pageNumber" TEXT,
          "importedFrom" TEXT,
          "dateImported" TEXT,
          "sourceNotes" TEXT
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "ingredientSections" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "name" TEXT,
          "sortOrder" INTEGER NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "ingredientLines" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "sectionID" TEXT NOT NULL REFERENCES "ingredientSections"("id") ON DELETE CASCADE,
          "originalText" TEXT NOT NULL,
          "quantity" REAL,
          "quantityText" TEXT,
          "unit" TEXT,
          "item" TEXT,
          "preparation" TEXT,
          "comment" TEXT,
          "isOptional" INTEGER NOT NULL DEFAULT 0,
          "shoppingCategory" TEXT,
          "doNotShop" INTEGER NOT NULL DEFAULT 0,
          "isHeader" INTEGER NOT NULL DEFAULT 0,
          "sortOrder" INTEGER NOT NULL,
          "confidence" TEXT
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "instructionSections" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "name" TEXT,
          "sortOrder" INTEGER NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "instructionSteps" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "sectionID" TEXT NOT NULL REFERENCES "instructionSections"("id") ON DELETE CASCADE,
          "text" TEXT NOT NULL,
          "sortOrder" INTEGER NOT NULL,
          "isOptional" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipeNotes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "text" TEXT NOT NULL,
          "noteType" TEXT NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL,
          "cookingSessionID" TEXT,
          "pinned" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipePhotos" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "imageDataReference" TEXT NOT NULL,
          "displayData" BLOB,
          "thumbnailData" BLOB,
          "mediaType" TEXT,
          "pixelWidth" INTEGER,
          "pixelHeight" INTEGER,
          "originalSourcePath" TEXT,
          "sourceURL" TEXT,
          "checksum" TEXT,
          "kind" TEXT NOT NULL DEFAULT 'gallery',
          "caption" TEXT,
          "source" TEXT NOT NULL,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "tags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL,
          "color" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "categories" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "equipment" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL,
          "equipmentType" TEXT,
          "notes" TEXT
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipeTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE,
          "sortOrder" INTEGER NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipeCategories" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "categoryID" TEXT NOT NULL REFERENCES "categories"("id") ON DELETE CASCADE
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipeEquipment" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "equipmentID" TEXT NOT NULL REFERENCES "equipment"("id") ON DELETE CASCADE,
          "notes" TEXT
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_recipeSources_on_recipeID" ON "recipeSources"("recipeID")"#,
        #"CREATE INDEX "index_ingredientSections_on_recipeID" ON "ingredientSections"("recipeID")"#,
        #"CREATE INDEX "index_ingredientLines_on_recipeID" ON "ingredientLines"("recipeID")"#,
        #"CREATE INDEX "index_ingredientLines_on_sectionID" ON "ingredientLines"("sectionID")"#,
        #"CREATE INDEX "index_instructionSections_on_recipeID" ON "instructionSections"("recipeID")"#,
        #"CREATE INDEX "index_instructionSteps_on_recipeID" ON "instructionSteps"("recipeID")"#,
        #"CREATE INDEX "index_instructionSteps_on_sectionID" ON "instructionSteps"("sectionID")"#,
        #"CREATE INDEX "index_recipeNotes_on_recipeID" ON "recipeNotes"("recipeID")"#,
        #"CREATE INDEX "index_recipeTags_on_recipeID" ON "recipeTags"("recipeID")"#,
        #"CREATE INDEX "index_recipeCategories_on_recipeID" ON "recipeCategories"("recipeID")"#,
        #"CREATE INDEX "index_recipeEquipment_on_recipeID" ON "recipeEquipment"("recipeID")"#,
      ] {
        try db.execute(sql: statement)
    }
	    }

    migrator.registerMigration("Add library placement and category hierarchy") { db in
      try #sql("""
        ALTER TABLE "recipes"
        ADD COLUMN "libraryPlacement" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'main'
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "categories"
        ADD COLUMN "parentCategoryID" TEXT
        """)
        .execute(db)
      // Fresh installs use the loose CloudKit-compatible parent ID; existing DBs converge below.

      try #sql("""
        CREATE INDEX "index_categories_on_parentCategoryID" ON "categories"("parentCategoryID")
        """)
        .execute(db)
    }

    migrator.registerMigration("Loosen category parent reference for CloudKit sync") { db in
      try #sql("""
        DROP INDEX IF EXISTS "index_categories_on_parentCategoryID"
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "categories"
        RENAME COLUMN "parentCategoryID" TO "legacyParentCategoryID"
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "categories"
        ADD COLUMN "parentCategoryID" TEXT
        """)
        .execute(db)

      try #sql("""
        UPDATE "categories"
        SET "parentCategoryID" = "legacyParentCategoryID"
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "categories"
        DROP COLUMN "legacyParentCategoryID"
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_categories_on_parentCategoryID" ON "categories"("parentCategoryID")
        """)
        .execute(db)
    }

    migrator.registerMigration("Create meal calendar schema") { db in
      try #sql("""
        CREATE TABLE "mealPlanItems" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "kind" TEXT NOT NULL,
          "recipeID" TEXT REFERENCES "recipes"("id") ON DELETE SET NULL,
          "title" TEXT NOT NULL,
          "scheduledDate" TEXT NOT NULL,
          "mealSlot" TEXT NOT NULL,
          "notes" TEXT,
          "startTime" TEXT,
          "endTime" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_mealPlanItems_on_recipeID" ON "mealPlanItems"("recipeID")"#,
        #"CREATE INDEX "index_mealPlanItems_on_scheduledDate" ON "mealPlanItems"("scheduledDate")"#,
        #"CREATE INDEX "index_mealPlanItems_on_scheduledDate_mealSlot" ON "mealPlanItems"("scheduledDate", "mealSlot")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Create menu schema") { db in
      try #sql("""
        CREATE TABLE "menus" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL,
          "notes" TEXT,
          "dayCount" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "menuItems" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "menuID" TEXT NOT NULL REFERENCES "menus"("id") ON DELETE CASCADE,
          "kind" TEXT NOT NULL,
          "recipeID" TEXT REFERENCES "recipes"("id") ON DELETE SET NULL,
          "title" TEXT NOT NULL,
          "dayOffset" INTEGER NOT NULL,
          "mealSlot" TEXT NOT NULL,
          "notes" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "menuPlacements" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "menuID" TEXT NOT NULL REFERENCES "menus"("id") ON DELETE CASCADE,
          "startDate" TEXT NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_menuItems_on_menuID" ON "menuItems"("menuID")"#,
        #"CREATE INDEX "index_menuItems_on_recipeID" ON "menuItems"("recipeID")"#,
        #"CREATE INDEX "index_menuItems_on_menuID_dayOffset_mealSlot" ON "menuItems"("menuID", "dayOffset", "mealSlot")"#,
        #"CREATE INDEX "index_menuPlacements_on_menuID" ON "menuPlacements"("menuID")"#,
        #"CREATE INDEX "index_menuPlacements_on_startDate" ON "menuPlacements"("startDate")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Create grocery schema") { db in
      try #sql("""
        CREATE TABLE "groceryLists" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL,
          "sortOrder" INTEGER NOT NULL,
          "isDefault" INTEGER NOT NULL DEFAULT 0,
          "remindersListName" TEXT,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "groceryItems" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "groceryListID" TEXT NOT NULL REFERENCES "groceryLists"("id") ON DELETE CASCADE,
          "title" TEXT NOT NULL,
          "quantity" REAL,
          "quantityText" TEXT,
          "unit" TEXT,
          "aisle" TEXT,
          "notes" TEXT,
          "isPurchased" INTEGER NOT NULL DEFAULT 0,
          "purchasedAt" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "groceryItemSources" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "groceryItemID" TEXT NOT NULL REFERENCES "groceryItems"("id") ON DELETE CASCADE,
          "origin" TEXT NOT NULL,
          "recipeID" TEXT,
          "ingredientLineID" TEXT,
          "mealPlanItemID" TEXT,
          "menuID" TEXT,
          "menuItemID" TEXT,
          "menuPlacementID" TEXT,
          "scheduledDate" TEXT,
          "mealSlot" TEXT,
          "sourceTitle" TEXT,
          "sourceSubtitle" TEXT,
          "ingredientText" TEXT,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_groceryLists_on_sortOrder" ON "groceryLists"("sortOrder")"#,
        #"CREATE INDEX "index_groceryItems_on_groceryListID" ON "groceryItems"("groceryListID")"#,
        #"CREATE INDEX "index_groceryItems_on_groceryListID_isPurchased" ON "groceryItems"("groceryListID", "isPurchased")"#,
        #"CREATE INDEX "index_groceryItemSources_on_groceryItemID" ON "groceryItemSources"("groceryItemID")"#,
        #"CREATE INDEX "index_groceryItemSources_on_recipeID" ON "groceryItemSources"("recipeID")"#,
        #"CREATE INDEX "index_groceryItemSources_on_mealPlanItemID" ON "groceryItemSources"("mealPlanItemID")"#,
        #"CREATE INDEX "index_groceryItemSources_on_menuID" ON "groceryItemSources"("menuID")"#,
        #"CREATE INDEX "index_groceryItemSources_on_menuPlacementID" ON "groceryItemSources"("menuPlacementID")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Create pantry schema") { db in
      try #sql("""
        CREATE TABLE "pantryItems" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL,
          "notes" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_pantryItems_on_sortOrder" ON "pantryItems"("sortOrder")"#,
        #"CREATE INDEX "index_pantryItems_on_title" ON "pantryItems"("title")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Create recipe import ref schema") { db in
      try #sql("""
        CREATE TABLE "recipeImportRef" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "normalizedSourceURL" TEXT,
          "normalizedTitle" TEXT NOT NULL,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_recipeImportRef_on_recipeID" ON "recipeImportRef"("recipeID")"#,
        #"CREATE INDEX "index_recipeImportRef_on_normalizedSourceURL_normalizedTitle" ON "recipeImportRef"("normalizedSourceURL", "normalizedTitle")"#,
        #"CREATE INDEX "index_recipeImportRef_on_normalizedTitle" ON "recipeImportRef"("normalizedTitle")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Add recipe make-ahead field") { db in
      try #sql("""
        ALTER TABLE "recipes"
        ADD COLUMN "makeAhead" TEXT
        """)
        .execute(db)
    }

    migrator.registerMigration("Add per-placement recipe scale") { db in
      try #sql("""
        ALTER TABLE "recipes"
        ADD COLUMN "viewScale" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 1.0
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "menuItems"
        ADD COLUMN "scale" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 1.0
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "mealPlanItems"
        ADD COLUMN "scale" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 1.0
        """)
        .execute(db)
    }

    migrator.registerMigration("Add recipe enrichment and ingredient substitutions") { db in
      try #sql("""
        ALTER TABLE "recipes"
        ADD COLUMN "chefItUp" TEXT
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "recipes"
        ADD COLUMN "serveWith" BLOB
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "ingredientLines"
        ADD COLUMN "substitution" TEXT
        """)
        .execute(db)
    }

    migrator.registerMigration("Add pantry policy and cached canonical names") { db in
      try #sql("""
        ALTER TABLE "pantryItems"
        ADD COLUMN "isUnlimited" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "pantryItems"
        ADD COLUMN "thresholdQuantity" REAL
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "pantryItems"
        ADD COLUMN "thresholdUnit" TEXT
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "ingredientLines"
        ADD COLUMN "canonicalName" TEXT
        """)
        .execute(db)

      try #sql("""
        ALTER TABLE "groceryItems"
        ADD COLUMN "canonicalName" TEXT
        """)
        .execute(db)

      try GroceryCanonicalNameCache.backfill(in: db)
    }

    migrator.registerMigration("Add menu prep plan") { db in
      try #sql("""
        ALTER TABLE "menus"
        ADD COLUMN "prepPlan" BLOB
        """)
        .execute(db)
    }

    migrator.registerMigration("Add recipe cover photo pointer") { db in
      // Loose pointer: a real FK creates a recipes <-> recipePhotos cycle that SQLiteData sync rejects.
      try #sql("""
        ALTER TABLE "recipes"
        ADD COLUMN "coverPhotoID" TEXT
        """)
        .execute(db)
    }

    migrator.registerMigration("Create local chat persistence") { db in
      try #sql("""
        CREATE TABLE "chatMessages" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "subjectKind" TEXT NOT NULL,
          "subjectID" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "text" TEXT NOT NULL,
          "createdAt" TEXT NOT NULL,
          "sortOrder" INTEGER NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_chatMessages_on_subjectKind_subjectID_sortOrder" ON "chatMessages"("subjectKind", "subjectID", "sortOrder")"#,
        #"CREATE INDEX "index_chatMessages_on_createdAt" ON "chatMessages"("createdAt")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Remove ingredient substitutions") { db in
      try #sql("""
        ALTER TABLE "ingredientLines"
        DROP COLUMN "substitution"
        """)
        .execute(db)

      try #sql("""
        UPDATE "recipeNotes"
        SET "noteType" = 'adaptation'
        WHERE "noteType" = 'substitution'
        """)
        .execute(db)
    }

    migrator.registerMigration("Create synced AI settings") { db in
      try #sql("""
        CREATE TABLE "aiSettings" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "tasteProfile" TEXT NOT NULL DEFAULT '',
          "chefItUpPreference" TEXT NOT NULL DEFAULT '',
          "serveWithPreference" TEXT NOT NULL DEFAULT '',
          "makeAheadPrepPlanPreference" TEXT NOT NULL DEFAULT '',
          "complementsPreference" TEXT NOT NULL DEFAULT '',
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)
    }

    migrator.registerMigration("Create workbench schema") { db in
      try #sql("""
        CREATE TABLE "workbenches" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL,
          "notes" TEXT,
          "draftRecipeID" TEXT REFERENCES "recipes"("id") ON DELETE SET NULL,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "workbenchCandidates" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "workbenchID" TEXT NOT NULL REFERENCES "workbenches"("id") ON DELETE CASCADE,
          "recipeID" TEXT REFERENCES "recipes"("id") ON DELETE SET NULL,
          "recipeTitleSnapshot" TEXT NOT NULL,
          "annotation" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_workbenches_on_sortOrder" ON "workbenches"("sortOrder")"#,
        #"CREATE INDEX "index_workbenches_on_draftRecipeID" ON "workbenches"("draftRecipeID")"#,
        #"CREATE INDEX "index_workbenchCandidates_on_workbenchID" ON "workbenchCandidates"("workbenchID")"#,
        #"CREATE INDEX "index_workbenchCandidates_on_recipeID" ON "workbenchCandidates"("recipeID")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Create workbench log") { db in
      try #sql("""
        CREATE TABLE "workbenchLog" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "workbenchID" TEXT NOT NULL REFERENCES "workbenches"("id") ON DELETE CASCADE,
          "kind" TEXT NOT NULL,
          "body" TEXT NOT NULL,
          "outcome" TEXT,
          "relatedRecipeID" TEXT,
          "sortOrder" INTEGER NOT NULL,
          "dateCreated" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_workbenchLog_on_workbenchID" ON "workbenchLog"("workbenchID")"#,
        #"CREATE INDEX "index_workbenchLog_on_relatedRecipeID" ON "workbenchLog"("relatedRecipeID")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Create recipe variations") { db in
      try #sql("""
        CREATE TABLE "recipeVariations" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL,
          "note" TEXT,
          "sortIndex" INTEGER NOT NULL,
          "deltas" BLOB,
          "origin" TEXT,
          "dateCreated" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "recipeActiveVariations" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "recipeID" TEXT NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE,
          "variationID" TEXT NOT NULL,
          "dateModified" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)

      for statement in [
        #"CREATE INDEX "index_recipeVariations_on_recipeID" ON "recipeVariations"("recipeID")"#,
        #"CREATE INDEX "index_recipeVariations_on_recipeID_sortIndex" ON "recipeVariations"("recipeID", "sortIndex")"#,
        #"CREATE INDEX "index_recipeActiveVariations_on_recipeID" ON "recipeActiveVariations"("recipeID")"#,
      ] {
        try db.execute(sql: statement)
      }
    }

    migrator.registerMigration("Add reader feedback curation preference") { db in
      try #sql("""
        ALTER TABLE "aiSettings"
        ADD COLUMN "readerFeedbackPreference" TEXT NOT NULL DEFAULT ''
        """)
        .execute(db)
    }

    migrator.registerMigration("Add capture to note preference") { db in
      try #sql("""
        ALTER TABLE "aiSettings"
        ADD COLUMN "captureToNotePreference" TEXT NOT NULL DEFAULT 'Format each captured note like a compact recipe: use a clear dish title, an Ingredients section when ingredients are stated, and numbered Method steps when method details are present. Preserve the source''s quantities and wording where possible; do not add unstated ingredients or steps.'
        """)
        .execute(db)
    }

    try migrator.migrate(database)
    try database.write { db in
      try RecipeChatStore.pruneMessages(olderThan: RecipeChatStore.cutoff(now: Date()), in: db)
    }
    defaultDatabase = database
    switch syncMode {
    case .disabled:
      break
    case let .configured(startImmediately):
      defaultSyncEngine = try YesChefCloudSync.makeSyncEngine(
        for: database,
        startImmediately: startImmediately
      )
    }
  }

  public mutating func migrateLegacyAISettingsIfNeeded(tasteProfile: String?) throws {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    try database.write { db in
      try AISettingsRepository.migrateLegacyTasteProfileIfNeeded(tasteProfile, in: db, now: now)
    }
  }
}
