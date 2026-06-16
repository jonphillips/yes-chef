import Dependencies
import Foundation
import SQLiteData

extension DependencyValues {
  public mutating func bootstrapDatabase() throws {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
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

    try migrator.migrate(database)
    defaultDatabase = database
  }
}

