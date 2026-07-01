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
    func syncedTableListMatchesCurrentModelTables() throws {
      let databaseURL = try temporaryCloudSyncDatabaseURL()
      let mainDatabase = try cloudSyncTestDatabase(at: databaseURL)
      _ = try YesChefCloudSync.makeSyncEngine(
        for: mainDatabase,
        startImmediately: false
      )

      let actualTableNames = try mainDatabase.write { db in
        try syncTriggerTableNames(in: db)
      }

      expectNoDifference(
        actualTableNames,
        currentModelTableNames.sorted()
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

    @Test
    func shareExtensionConnectionInstallsStoppedEngineTriggers() throws {
      let databaseURL = try temporaryCloudSyncDatabaseURL()
      let recipeID = SampleUUIDSequence.uuid(601)

      let extensionBootstrap = try cloudSyncTestShareExtensionBootstrap(at: databaseURL)

      try extensionBootstrap.database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Share Extension Capture",
            dateCreated: Date(timeIntervalSinceReferenceDate: 813_100_000),
            dateModified: Date(timeIntervalSinceReferenceDate: 813_100_000)
          )
        }
        .execute(db)
      }

      try extensionBootstrap.database.read { db in
        let metadata = try SyncMetadata.fetchAll(db)
        #expect(
          metadata.contains {
            $0.recordType == Recipe.tableName
              && $0.recordPrimaryKey.caseInsensitiveCompare(recipeID.uuidString) == .orderedSame
          }
        )
      }
      #expect(!extensionBootstrap.syncEngine.isRunning)
    }
  }
}

private let currentModelTableNames = [
  Recipe.tableName,
  RecipeSource.tableName,
  IngredientSection.tableName,
  IngredientLine.tableName,
  InstructionSection.tableName,
  InstructionStep.tableName,
  RecipeNote.tableName,
  RecipePhoto.tableName,
  Tag.tableName,
  Category.tableName,
  Equipment.tableName,
  RecipeTag.tableName,
  RecipeCategory.tableName,
  RecipeEquipment.tableName,
  RecipeImportRef.tableName,
  MealPlanItem.tableName,
  Menu.tableName,
  MenuItem.tableName,
  MenuPlacement.tableName,
  GroceryList.tableName,
  GroceryItem.tableName,
  GroceryItemSource.tableName,
  PantryItem.tableName,
]

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

private func cloudSyncTestShareExtensionBootstrap(
  at url: URL
) throws -> (database: any DatabaseWriter, syncEngine: SyncEngine) {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  return try withDependencies {
    $0.context = .test
  } operation: {
    var dependencies = DependencyValues()
    try dependencies.bootstrapDatabaseForShareExtension(path: url.path)
    return (dependencies.defaultDatabase, dependencies.defaultSyncEngine)
  }
}

private func syncTriggerTableNames(in db: Database) throws -> [String] {
  let prefix = "sqlitedata_icloud_after_insert_on_"
  return try #sql(
    """
    SELECT "name" FROM "sqlite_temp_master"
    WHERE "type" = 'trigger' AND "name" LIKE 'sqlitedata_icloud_after_insert_on_%'
    """,
    as: String.self
  )
  .fetchAll(db)
  .compactMap { name in
    guard name.hasPrefix(prefix) else { return nil }
    return String(name.dropFirst(prefix.count))
  }
  .filter { !$0.hasPrefix("sqlitedata_icloud_") }
  .sorted()
}
