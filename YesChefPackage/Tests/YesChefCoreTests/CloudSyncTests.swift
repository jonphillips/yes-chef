import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CloudSyncTests {
    @Test
    func syncedTableListMatchesCurrentModelTables() {
      expectNoDifference(
        YesChefCloudSync.syncedTableNames,
        [
          "recipes",
          "recipeSources",
          "ingredientSections",
          "ingredientLines",
          "instructionSections",
          "instructionSteps",
          "recipeNotes",
          "recipePhotos",
          "tags",
          "categories",
          "equipment",
          "recipeTags",
          "recipeCategories",
          "recipeEquipment",
          "recipeImportRef",
          "mealPlanItems",
          "menus",
          "menuItems",
          "menuPlacements",
          "groceryLists",
          "groceryItems",
          "groceryItemSources",
          "pantryItems",
        ]
      )
    }

    @Test
    func manualSyncGateDefaultsOff() throws {
      let defaults = try #require(UserDefaults(suiteName: "YesChefCloudSyncTests-\(UUID().uuidString)"))

      #expect(
        !YesChefCloudSync.isManuallyEnabled(
          defaults: defaults,
          environment: [:],
          arguments: []
        )
      )
      defaults.set(true, forKey: YesChefCloudSync.enabledDefaultsKey)
      #expect(
        YesChefCloudSync.isManuallyEnabled(
          defaults: defaults,
          environment: [:],
          arguments: []
        )
      )
    }

    @Test
    func bootstrapAttachesMetadatabase() throws {
      @Dependency(\.defaultDatabase) var database

      try database.read { db in
        let names = try #sql("SELECT name FROM pragma_database_list", as: String.self)
          .fetchAll(db)
        #expect(names.contains("sqlitedata_icloud"))
      }
    }

    @Test
    func mainAppConnectionWritesRowsPickedUpBySyncTriggers() throws {
      let databaseURL = try temporaryCloudSyncDatabaseURL()
      let recipeID = SampleUUIDSequence.uuid(600)

      let mainDatabase = try cloudSyncTestDatabase(at: databaseURL)
      let syncEngine = try YesChefCloudSync.makeSyncEngine(
        for: mainDatabase,
        startImmediately: false
      )

      try mainDatabase.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Main App Capture",
            dateCreated: Date(timeIntervalSinceReferenceDate: 813_000_000),
            dateModified: Date(timeIntervalSinceReferenceDate: 813_000_000)
          )
        }
        .execute(db)
      }

      try mainDatabase.read { db in
        let metadata = try SyncMetadata.fetchAll(db)
        #expect(
          metadata.contains {
            $0.recordType == Recipe.tableName
              && $0.recordPrimaryKey.caseInsensitiveCompare(recipeID.uuidString) == .orderedSame
          }
        )
      }
      #expect(!syncEngine.isRunning)
    }
  }
}

private func temporaryCloudSyncDatabaseURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("YesChefCloudSyncTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("SQLiteData.db", isDirectory: false)
}

private func cloudSyncTestDatabase(at url: URL) throws -> any DatabaseWriter {
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
