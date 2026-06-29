import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct DatabaseStorageTests {
    @Test
    func resolvesSharedAndLegacyDatabaseURLs() {
      let rootURL = URL(fileURLWithPath: "/tmp/yeschef-storage-test", isDirectory: true)
      let groupURL = rootURL.appendingPathComponent("group", isDirectory: true)
      let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)

      expectNoDifference(
        YesChefDatabaseStorage.sharedDatabaseURL(appGroupContainerURL: groupURL),
        groupURL.appendingPathComponent("SQLiteData.db", isDirectory: false)
      )
      expectNoDifference(
        YesChefDatabaseStorage.legacyDatabaseURL(applicationSupportDirectory: applicationSupportURL),
        applicationSupportURL.appendingPathComponent("SQLiteData.db", isDirectory: false)
      )
    }

    @Test
    func opensDatabaseFromSharedContainerPath() throws {
      let rootURL = try temporaryDirectory()
      let sharedDatabaseURL = YesChefDatabaseStorage.sharedDatabaseURL(
        appGroupContainerURL: rootURL.appendingPathComponent("Group", isDirectory: true)
      )

      let database = try pathBackedDatabase(at: sharedDatabaseURL)
      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: SampleUUIDSequence.uuid(1),
            title: "Shared Store Recipe",
            dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000),
            dateModified: Date(timeIntervalSinceReferenceDate: 811_000_000)
          )
        }
        .execute(db)
      }

      #expect(FileManager.default.fileExists(atPath: sharedDatabaseURL.path))
    }

    @Test
    func migratesPreExistingStoreWithoutLoss() throws {
      let rootURL = try temporaryDirectory()
      let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
      let groupURL = rootURL.appendingPathComponent("Group", isDirectory: true)
      let legacyDatabaseURL = YesChefDatabaseStorage.legacyDatabaseURL(
        applicationSupportDirectory: applicationSupportURL
      )
      let sharedDatabaseURL = YesChefDatabaseStorage.sharedDatabaseURL(appGroupContainerURL: groupURL)
      let recipeID = SampleUUIDSequence.uuid(10)

      try FileManager.default.createDirectory(
        at: applicationSupportURL,
        withIntermediateDirectories: true
      )

      do {
        let legacyDatabase = try pathBackedDatabase(at: legacyDatabaseURL)
        try legacyDatabase.write { db in
          try Recipe.insert {
            Recipe(
              id: recipeID,
              title: "Legacy Store Recipe",
              dateCreated: Date(timeIntervalSinceReferenceDate: 811_100_000),
              dateModified: Date(timeIntervalSinceReferenceDate: 811_100_000)
            )
          }
          .execute(db)
        }
      }

      try YesChefDatabaseStorage.migrateLegacyDatabaseIfNeeded(
        from: legacyDatabaseURL,
        to: sharedDatabaseURL
      )

      let sharedDatabase = try pathBackedDatabase(at: sharedDatabaseURL)
      try sharedDatabase.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.title, "Legacy Store Recipe")
      }

      #expect(!FileManager.default.fileExists(atPath: legacyDatabaseURL.path))
      #expect(FileManager.default.fileExists(atPath: sharedDatabaseURL.path))
    }
  }
}

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("YesChefDatabaseStorageTests-\(UUID().uuidString)", isDirectory: true)
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
