import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized)
struct SchemaColumnTests {
  @Test
  func everyPersistedTableMatchesItsModelColumns() throws {
    let databaseURL = try temporaryDirectory().appendingPathComponent("library.sqlite")
    let database = try pathBackedDatabase(at: databaseURL)
    let models = persistedTableModels
    let modelNames = Set(models.map(\.name))

    try database.read { db in
      let actualTables = Set(try String.fetchAll(
        db,
        sql: #"SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"#
      ))
      // GRDB owns this local migration ledger; it has no @Table model by design.
      let localBookkeepingTables: Set<String> = ["grdb_migrations"]
      #expect(actualTables.subtracting(modelNames).subtracting(localBookkeepingTables).isEmpty)
      #expect(modelNames.isSubset(of: actualTables))

      for model in models {
        let actualColumns = Set(try String.fetchAll(
          db,
          sql: "SELECT name FROM pragma_table_info(?)",
          arguments: [model.name]
        ))
        #expect(actualColumns == model.columns, "Unexpected columns for \(model.name)")
      }
    }

    try database.close()
  }

  @Test
  func droppingLegacyRecipeCookingColumnsPreservesExistingRecipeValues() async throws {
    let databaseURL = try temporaryDirectory().appendingPathComponent("legacy-library.sqlite")
    let recipeID = UUID()
    let createdAt = Date(timeIntervalSinceReferenceDate: 811_000_000)
    let changedAt = createdAt.addingTimeInterval(300)
    let expectedRecipe = Recipe(
      id: recipeID,
      title: "Preserved Recipe",
      summary: "Still here",
      dateCreated: createdAt,
      dateModified: changedAt,
      originalImportText: "source text"
    )
    let database = try pathBackedDatabase(at: databaseURL)

    try await database.write { db in
      try Recipe.insert {
        expectedRecipe
      }
      .execute(db)
      try db.execute(sql: #"ALTER TABLE "recipes" ADD COLUMN "lastCookedAt" TEXT"#)
      try db.execute(sql: #"ALTER TABLE "recipes" ADD COLUMN "timesCooked" INTEGER NOT NULL DEFAULT 0"#)
      try db.execute(
        sql: #"UPDATE "recipes" SET "lastCookedAt" = ?, "timesCooked" = ? WHERE "id" = ?"#,
        arguments: ["2026-10-01T12:00:00Z", 42, recipeID]
      )
      try db.execute(
        sql: #"DELETE FROM "grdb_migrations" WHERE "identifier" = 'Drop legacy recipe cooking columns'"#
      )
    }
    try database.close()

    let migratedDatabase = try pathBackedDatabase(at: databaseURL)
    try await migratedDatabase.read { db in
      let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
      #expect(recipe == expectedRecipe)

      let columns = Set(try String.fetchAll(
        db,
        sql: #"SELECT name FROM pragma_table_info('recipes')"#
      ))
      #expect(!columns.contains("lastCookedAt"))
      #expect(!columns.contains("timesCooked"))
    }
    try migratedDatabase.close()
  }
}

private struct PersistedTableModel {
  let name: String
  let columns: Set<String>
}

private func persistedTableModel<T: Table>(_ type: T.Type) -> PersistedTableModel {
  PersistedTableModel(name: T.tableName, columns: Set(T.TableColumns.allColumns.map(\.name)))
}

private let persistedTableModels = [
  persistedTableModel(Recipe.self),
  persistedTableModel(AISettingsRecord.self),
  persistedTableModel(ChatMessageRecord.self),
  persistedTableModel(MealPlanItem.self),
  persistedTableModel(Menu.self),
  persistedTableModel(MenuItem.self),
  persistedTableModel(MenuPlacement.self),
  persistedTableModel(GroceryList.self),
  persistedTableModel(GroceryItem.self),
  persistedTableModel(GroceryItemSource.self),
  persistedTableModel(PantryItem.self),
  persistedTableModel(RecipeSource.self),
  persistedTableModel(RecipeImportRef.self),
  persistedTableModel(IngredientSection.self),
  persistedTableModel(IngredientLine.self),
  persistedTableModel(InstructionSection.self),
  persistedTableModel(InstructionStep.self),
  persistedTableModel(RecipeNote.self),
  persistedTableModel(RecipePhoto.self),
  persistedTableModel(Tag.self),
  persistedTableModel(Equipment.self),
  persistedTableModel(RecipeTag.self),
  persistedTableModel(RecipeCategory.self),
  persistedTableModel(RecipeEquipment.self),
  persistedTableModel(AIHandoff.self),
  persistedTableModel(Learning.self),
  persistedTableModel(Category.self),
  persistedTableModel(Facet.self),
  persistedTableModel(GroceryAreaAssignment.self),
  persistedTableModel(PrepPlanStepRecord.self),
  persistedTableModel(ChatThreadRecord.self),
  persistedTableModel(RecipeDeliberationLogEntry.self),
  persistedTableModel(RecipeRelatedRecipe.self),
  persistedTableModel(RecipeServeWith.self),
  persistedTableModel(RecipeVariation.self),
  persistedTableModel(RecipeActiveVariation.self),
  persistedTableModel(Workbench.self),
  persistedTableModel(WorkbenchCandidate.self),
  persistedTableModel(WorkbenchLogEntry.self),
  persistedTableModel(WorkbenchReference.self),
]

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("YesChefSchemaColumnTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func pathBackedDatabase(at url: URL) throws -> any DatabaseWriter {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  return try withDependencies {
    $0.context = .live
  } operation: {
    var dependencies = DependencyValues()
    try dependencies.bootstrapDatabase(path: url.path)
    return dependencies.defaultDatabase
  }
}
