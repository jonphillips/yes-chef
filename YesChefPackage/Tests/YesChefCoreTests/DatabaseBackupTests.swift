import CloudSyncKit
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized)
struct DatabaseBackupTests {
  @Test
  func yesChefConfigurationIdentifiesItsStoreAndUsesTheRegisteredMigrationCount() throws {
    let databaseURL = try temporaryDirectory().appendingPathComponent("library.sqlite")
    let database = try pathBackedDatabase(at: databaseURL)
    let registeredCount = try database.read { db in
      try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "grdb_migrations""#) ?? 0
    }
    #expect(YesChefCloudSync.databaseBackupConfiguration.identifyingTableNames == ["recipes"])
    #expect(YesChefCloudSync.databaseBackupConfiguration.declaredSchemaVersion == registeredCount)
    try database.close()
  }

  @Test
  func aNonYesChefSQLiteFileIsRejected() throws {
    let databaseURL = try temporaryDirectory().appendingPathComponent("other.sqlite")
    let database = try DatabaseQueue(path: databaseURL.path)
    try database.write { db in try db.execute(sql: "CREATE TABLE unrelated (id TEXT PRIMARY KEY)") }
    #expect(throws: DatabaseBackup.BackupError.self) {
      try DatabaseBackup.schemaVersion(in: databaseURL, configuration: YesChefCloudSync.databaseBackupConfiguration)
    }
    try database.close()
  }

  @Test
  func snapshotPrepareAndRestorePreserveRecipePhotosAsBlobs() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite")
    let snapshotURL = directoryURL.appendingPathComponent("snapshot.sqlite")
    let stagingURL = directoryURL.appendingPathComponent("staging.sqlite")
    let database = try pathBackedDatabase(at: sourceURL)
    let recipeID = SampleUUIDSequence.uuid(71)
    let photoID = SampleUUIDSequence.uuid(72)
    let imageBytes = Data([0x01, 0x02, 0x03, 0xFE])

    try await database.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Photo Backup",
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000),
          dateModified: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
      try RecipePhoto.insert {
        RecipePhoto(
          id: photoID,
          recipeID: recipeID,
          imageDataReference: "backup-photo",
          displayData: imageBytes,
          thumbnailData: Data([0xAA, 0xBB]),
          sortOrder: 0,
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
    }

    let configuration = YesChefCloudSync.databaseBackupConfiguration
    _ = try await DatabaseBackup.snapshot(from: database, to: snapshotURL, configuration: configuration)
    let prepared = try await DatabaseBackup.prepareRestore(
      from: snapshotURL,
      to: stagingURL,
      currentSchemaVersion: configuration.declaredSchemaVersion,
      configuration: configuration,
      migrate: configuration.migrate
    )
    let restoredDatabase = try DatabaseQueue(path: prepared.fileURL.path)
    let restoredPhoto = try await restoredDatabase.read { db in
      try RecipePhoto.find(photoID).fetchOne(db)
    }
    #expect(restoredPhoto?.displayData == imageBytes)
    #expect(restoredPhoto?.thumbnailData == Data([0xAA, 0xBB]))
    try restoredDatabase.close()
    try database.close()
  }
}

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("YesChefDatabaseBackupTests-\(UUID().uuidString)", isDirectory: true)
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
