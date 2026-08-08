import Dependencies
import Foundation
import IssueReporting
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized)
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
    // Assert the image *bytes*, not just that a photo row survived. Images are the one payload with
    // no textual fallback — a silently truncated BLOB restores a recipe with a broken photo and
    // nothing else would notice. (ADR-0030 D1: images ride along as in-row BLOBs.)
    let restoredPhoto = try await snapshotDatabase.read { db in
      try RecipePhoto.find(SampleUUIDSequence.uuid(2)).fetchOne(db)
    }
    let stampedSchemaVersion = try await snapshotDatabase.read { db in
      try Int.fetchOne(db, sql: "PRAGMA user_version")
    }

    #expect(snapshot.fileURL == snapshotURL)
    #expect(snapshot.schemaVersion > 0)
    #expect(recipeCount == 1)
    #expect(photoCount == 1)
    #expect(restoredPhoto?.displayData == Data([0x01, 0x02, 0x03]))
    #expect(restoredPhoto?.thumbnailData == Data([0x04, 0x05]))
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
  func restorePreparationPreservesAppRowsAndSnapshotsExcludeAttachedSyncMetadata() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let stagingURL = directoryURL.appendingPathComponent("staging.sqlite", isDirectory: false)
    let syncDatabase = try syncConfiguredDatabase(at: sourceURL)
    let database = syncDatabase.database
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
    let snapshotTableNames = try await backupDatabase.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
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
    try restoredDatabase.close()

    #expect(restoredRecipe?.title == "Restored Recipe")
    #expect(!snapshotTableNames.contains { $0.hasPrefix("sqlitedata_icloud_") })
    let metadataURL = try YesChefDatabaseStorage.attachedSyncMetadataURL(
      in: database,
      fallbackFor: sourceURL,
      containerIdentifier: YesChefCloudSync.containerIdentifier
    )
    let metadataTableNames = try await database.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlitedata_icloud.sqlite_master WHERE type = 'table'"
      )
    }
    #expect(metadataURL == YesChefDatabaseStorage.syncMetadataURL(
      for: sourceURL,
      containerIdentifier: YesChefCloudSync.containerIdentifier
    ))
    #expect(FileManager.default.fileExists(atPath: metadataURL.path))
    #expect(metadataTableNames.contains("sqlitedata_icloud_metadata"))
    // Keep the engine alive until the assertions finish; it owns the real attachment under test.
    _ = syncDatabase.syncEngine
  }

  @Test
  func restorePreparationRefusesInvalidAndNewerBackups() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let invalidMarkerURL = directoryURL.appendingPathComponent("invalid-marker.sqlite", isDirectory: false)
    let newerBackupURL = directoryURL.appendingPathComponent("newer.sqlite", isDirectory: false)
    let nonDatabaseURL = directoryURL.appendingPathComponent("not-a-database.sqlite", isDirectory: false)
    let database = try pathBackedDatabase(at: sourceURL)
    let backup = try await YesChefDatabaseBackup.snapshot(from: database, to: backupURL)

    try Data("not a SQLite database".utf8).write(to: nonDatabaseURL)
    do {
      _ = try YesChefDatabaseBackup.schemaVersion(in: nonDatabaseURL)
      #expect(Bool(false))
    } catch {
      let isNotYesChefBackup: Bool
      if case .notYesChefBackup = error as? YesChefDatabaseBackup.BackupError {
        isNotYesChefBackup = true
      } else {
        isNotYesChefBackup = false
      }
      #expect(isNotYesChefBackup)
    }

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
  func replaceLiveStoreDiscardsTheActualAttachedSyncMetadata() async throws {
    let directoryURL = try temporaryDirectory()
    let liveStoreURL = directoryURL.appendingPathComponent("live.sqlite", isDirectory: false)
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let stagingURL = directoryURL.appendingPathComponent("staging.sqlite", isDirectory: false)
    let syncDatabase = try syncConfiguredDatabase(at: liveStoreURL)
    let liveDatabase = syncDatabase.database
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
    let metadataURL = try YesChefDatabaseStorage.attachedSyncMetadataURL(
      in: liveDatabase,
      fallbackFor: liveStoreURL,
      containerIdentifier: YesChefCloudSync.containerIdentifier
    )
    let metadataTableNames = try await liveDatabase.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlitedata_icloud.sqlite_master WHERE type = 'table'"
      )
    }

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
    #expect(metadataTableNames.contains("sqlitedata_icloud_metadata"))
    #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
    // Keep the engine alive until replacement removes the real attachment under test.
    _ = syncDatabase.syncEngine
  }

  @Test
  func restorePreparationForwardMigratesAGenuineNMinusOneBackup() async throws {
    let directoryURL = try temporaryDirectory()
    let sourceURL = directoryURL.appendingPathComponent("source.sqlite", isDirectory: false)
    let backupURL = directoryURL.appendingPathComponent("backup.sqlite", isDirectory: false)
    let stagingURL = directoryURL.appendingPathComponent("staging.sqlite", isDirectory: false)
    let sourceDatabase = try pathBackedDatabase(at: sourceURL)
    let recipeID = SampleUUIDSequence.uuid(5)
    let serveWithID = SampleUUIDSequence.uuid(6)
    let malformedRecipeID = SampleUUIDSequence.uuid(7)
    let handoffID = SampleUUIDSequence.uuid(8)
    let migrationDate = Date(timeIntervalSinceReferenceDate: 811_000_000)
    let legacyServeWith = try ServeWithCoding.encode([
      ServeWithItem(id: serveWithID, title: "Warm flatbread", note: "For scooping")
    ])
    let malformedServeWith = Data("not json".utf8)

    try await sourceDatabase.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Forward Migrated Recipe",
          dateCreated: migrationDate,
          dateModified: migrationDate,
          serveWith: legacyServeWith
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .recipe,
          sourceID: recipeID,
          taskType: .adjustRecipe,
          createdAt: migrationDate,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )
      try Recipe.insert {
        Recipe(
          id: malformedRecipeID,
          title: "Malformed Serve With",
          dateCreated: migrationDate,
          dateModified: migrationDate,
          serveWith: malformedServeWith
        )
      }
      .execute(db)
    }
    let backup = try await YesChefDatabaseBackup.snapshot(from: sourceDatabase, to: backupURL)
    let backupDatabase = try DatabaseQueue(path: backupURL.path)
    let latestMigrationIdentifier = try await backupDatabase.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1"
      )
    }
    // Keep this fixture exactly the migrations listed here behind the current schema.
    // Update this tail when it changes.
    //
    // The four "workbench references" repairs are guarded no-ops against a clean
    // workbenchReferences table (each acts only when pragma_table_info shows a missing or
    // orphaned column), so downgrading past them needs no schema reversal below — they simply
    // re-run as no-ops during forward migration.
    let migrationsToReplay = [
      "Move recipe Serve With into editable rows",
      "Add regenerate intent to local AI handoffs",
      "Add color to categories",
      "Create synced category seed state",
      "Create synced category seed tombstones",
      "Promote category namespaces to facets",
      "Add variation scope to local AI handoffs",
      "Backfill captureKind column on workbench references",
      "Reconcile late-added workbench references columns",
      "Drop orphaned kind column from workbench references",
      "Drop all non-model columns from workbench references",
    ]
    #expect(latestMigrationIdentifier == migrationsToReplay.last)
    try await backupDatabase.write { db in
      try db.execute(sql: "DROP TABLE facets")
      try db.execute(sql: "ALTER TABLE categories DROP COLUMN facetID")
      try db.execute(sql: "ALTER TABLE categories DROP COLUMN hidden")
      try db.execute(sql: "ALTER TABLE aiHandoffs DROP COLUMN variationID")
      try db.execute(sql: "ALTER TABLE aiHandoffs DROP COLUMN regenerates")
      try db.execute(sql: "DROP TABLE recipeServeWith")
      try db.execute(sql: "ALTER TABLE categories DROP COLUMN color")
      for migration in migrationsToReplay {
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?", arguments: [migration])
      }
      try db.execute(sql: "PRAGMA user_version = \(backup.schemaVersion - migrationsToReplay.count)")
    }
    try backupDatabase.close()

    let issueReporters = IssueReporters.current
    defer { IssueReporters.current = issueReporters }
    IssueReporters.current = []
    let prepared = try await YesChefDatabaseBackup.prepareRestore(
      from: backupURL,
      to: stagingURL,
      currentSchemaVersion: backup.schemaVersion,
      migrate: DependencyValues.migrateRestoreCandidate(at:)
    )
    let restoredDatabase = try DatabaseQueue(path: prepared.fileURL.path)
    let restoredRecipe = try await restoredDatabase.read { db in
      try Recipe.find(recipeID).fetchOne(db)
    }
    let workbenchReferenceCount = try await restoredDatabase.read { db in
      try WorkbenchReference.fetchCount(db)
    }
    let restoredServeWith = try await restoredDatabase.read { db in
      try RecipeServeWithRepository.serveWith(for: recipeID, in: db)
    }
    let restoredMalformedRecipe = try await restoredDatabase.read { db in
      try Recipe.find(malformedRecipeID).fetchOne(db)
    }
    let restoredMalformedServeWith = try await restoredDatabase.read { db in
      try RecipeServeWithRepository.serveWith(for: malformedRecipeID, in: db)
    }
    let restoredMarker = try await restoredDatabase.read { db in
      try Int.fetchOne(db, sql: "PRAGMA user_version")
    }
    let restoredHandoff = try await restoredDatabase.read { db in
      try AIHandoffRepository.handoff(id: handoffID, in: db)
    }
    try restoredDatabase.close()

    #expect(restoredRecipe?.title == "Forward Migrated Recipe")
    #expect(restoredRecipe?.serveWith == legacyServeWith)
    #expect(restoredMalformedRecipe?.serveWith == malformedServeWith)
    #expect(workbenchReferenceCount == 0)
    #expect(
      restoredServeWith == [
        RecipeServeWith(
          id: serveWithID,
          recipeID: recipeID,
          title: "Warm flatbread",
          note: "For scooping",
          sortOrder: 0,
          provenance: .model,
          dateCreated: migrationDate,
          dateModified: migrationDate
        )
      ]
    )
    #expect(restoredMalformedServeWith.isEmpty)
    #expect(restoredHandoff?.prepPlanIntent == .refine)
    #expect(prepared.schemaVersion == backup.schemaVersion)
    #expect(restoredMarker == backup.schemaVersion)
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

private func syncConfiguredDatabase(
  at url: URL
) throws -> (database: any DatabaseWriter, syncEngine: SyncEngine) {
  let database = try pathBackedDatabase(at: url)
  let syncEngine = try YesChefCloudSync.makeSyncEngine(for: database, startImmediately: false)
  return (database, syncEngine)
}
