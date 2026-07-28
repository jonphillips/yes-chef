import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite
struct DatabaseBackupTests {
  @Test
  func snapshotIsSelfContainedAndPreservesSeededRows() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let snapshotURL = directoryURL.appendingPathComponent("snapshot.sqlite", isDirectory: false)
    let database = try pathBackedDatabase(at: sourceURL)
    let recipeID = SampleUUIDSequence.uuid(1)

    try await database.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Backup Recipe",
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000),
          dateModified: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
      try RecipePhoto.insert {
        RecipePhoto(
          id: SampleUUIDSequence.uuid(2),
          recipeID: recipeID,
          imageDataReference: "backup-photo",
          displayData: Data([0x01, 0x02, 0x03]),
          thumbnailData: Data([0x04, 0x05]),
          sortOrder: 0,
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
    }

    let snapshot = try await YesChefDatabaseBackup.snapshot(from: database, to: snapshotURL)
    let snapshotDatabase = try DatabaseQueue(path: snapshotURL.path)
    let recipeCount = try await snapshotDatabase.read { db in try Recipe.fetchCount(db) }
    let photoCount = try await snapshotDatabase.read { db in try RecipePhoto.fetchCount(db) }
    let stampedSchemaVersion = try await snapshotDatabase.read { db in
      try Int.fetchOne(db, sql: "PRAGMA user_version")
    }

    #expect(snapshot.fileURL == snapshotURL)
    #expect(snapshot.schemaVersion > 0)
    #expect(recipeCount == 1)
    #expect(photoCount == 1)
    #expect(stampedSchemaVersion == snapshot.schemaVersion)
    #expect(!FileManager.default.fileExists(atPath: "\(snapshotURL.path)-wal"))
    #expect(!FileManager.default.fileExists(atPath: "\(snapshotURL.path)-shm"))
  }

  @Test
  func defaultFilenameUsesTheBackupDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28))!

    #expect(
      YesChefDatabaseBackup.defaultFilename(for: date, calendar: calendar)
        == "YesChef-Backup-2026-07-28.sqlite"
    )
  }

  @Test
  func restorePreparationStripsSyncMetadataAndPreservesAppRows() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let stagingURL = directoryURL.appendingPathComponent("staging.sqlite", isDirectory: false)
    let database = try pathBackedDatabase(at: sourceURL)
    let recipeID = SampleUUIDSequence.uuid(3)

    try await database.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Restored Recipe",
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000),
          dateModified: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
    }
    let backup = try await YesChefDatabaseBackup.snapshot(from: database, to: backupURL)
    let backupDatabase = try DatabaseQueue(path: backupURL.path)
    try await backupDatabase.write { db in
      try db.execute(sql: "CREATE TABLE sqlitedata_icloud_metadata (value TEXT)")
      try db.execute(sql: "CREATE TABLE sqlitedata_icloud_pendingRecordZoneChanges (value TEXT)")
    }
    try backupDatabase.close()

    let prepared = try await YesChefDatabaseBackup.prepareRestore(
      from: backupURL,
      to: stagingURL,
      currentSchemaVersion: backup.schemaVersion,
      migrate: { _ in }
    )
    let restoredDatabase = try DatabaseQueue(path: prepared.fileURL.path)
    let restoredRecipe = try await restoredDatabase.read { db in
      try Recipe.find(recipeID).fetchOne(db)
    }
    let syncMetadataTables = try await restoredDatabase.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'sqlitedata_icloud_%'"
      )
    }
    try restoredDatabase.close()

    #expect(restoredRecipe?.title == "Restored Recipe")
    #expect(syncMetadataTables.isEmpty)
  }

  @Test
  func restorePreparationRefusesInvalidAndNewerBackups() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let invalidMarkerURL = directoryURL.appendingPathComponent("invalid-marker.sqlite", isDirectory: false)
    let newerBackupURL = directoryURL.appendingPathComponent("newer.sqlite", isDirectory: false)
    let database = try pathBackedDatabase(at: sourceURL)
    let backup = try await YesChefDatabaseBackup.snapshot(from: database, to: backupURL)

    try FileManager.default.copyItem(at: backupURL, to: invalidMarkerURL)
    let invalidMarkerDatabase = try DatabaseQueue(path: invalidMarkerURL.path)
    try await invalidMarkerDatabase.write { db in
      try db.execute(sql: "PRAGMA user_version = 0")
    }
    try invalidMarkerDatabase.close()

    await #expect(throws: YesChefDatabaseBackup.BackupError.self) {
      try await YesChefDatabaseBackup.prepareRestore(
        from: invalidMarkerURL,
        to: directoryURL.appendingPathComponent("invalid-staging.sqlite", isDirectory: false),
        currentSchemaVersion: backup.schemaVersion,
        migrate: { _ in }
      )
    }

    try FileManager.default.copyItem(at: backupURL, to: newerBackupURL)
    let newerBackupDatabase = try DatabaseQueue(path: newerBackupURL.path)
    try await newerBackupDatabase.write { db in
      try db.execute(
        sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
        arguments: ["future-migration"]
      )
      try db.execute(sql: "PRAGMA user_version = \(backup.schemaVersion + 1)")
    }
    try newerBackupDatabase.close()

    await #expect(throws: YesChefDatabaseBackup.BackupError.self) {
      try await YesChefDatabaseBackup.prepareRestore(
        from: newerBackupURL,
        to: directoryURL.appendingPathComponent("newer-staging.sqlite", isDirectory: false),
        currentSchemaVersion: backup.schemaVersion,
        migrate: { _ in }
      )
    }
  }

  @Test
  func replaceLiveStoreDiscardsPreviousSyncMetadata() async throws {
    let directoryURL = try temporaryDirectory()
    let liveStoreURL = directoryURL.appendingPathComponent("live.sqlite", isDirectory: false)
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let stagingURL = directoryURL.appendingPathComponent("staging.sqlite", isDirectory: false)
    let liveDatabase = try pathBackedDatabase(at: liveStoreURL)
    let sourceDatabase = try pathBackedDatabase(at: sourceURL)
    let recipeID = SampleUUIDSequence.uuid(4)

    try await sourceDatabase.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Replacement Recipe",
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000),
          dateModified: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
    }
    let backup = try await YesChefDatabaseBackup.snapshot(from: sourceDatabase, to: backupURL)
    let prepared = try await YesChefDatabaseBackup.prepareRestore(
      from: backupURL,
      to: stagingURL,
      currentSchemaVersion: backup.schemaVersion,
      migrate: { _ in }
    )
    let metadataURL = YesChefDatabaseStorage.syncMetadataURL(
      for: liveStoreURL,
      containerIdentifier: YesChefCloudSync.containerIdentifier
    )
    FileManager.default.createFile(atPath: metadataURL.path, contents: Data())

    try liveDatabase.close()
    try YesChefDatabaseBackup.replaceLiveStore(
      at: liveStoreURL,
      with: prepared,
      syncMetadataURL: metadataURL
    )
    let restoredDatabase = try DatabaseQueue(path: liveStoreURL.path)
    let restoredRecipe = try await restoredDatabase.read { db in
      try Recipe.find(recipeID).fetchOne(db)
    }
    try restoredDatabase.close()

    #expect(restoredRecipe?.title == "Replacement Recipe")
    #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
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
