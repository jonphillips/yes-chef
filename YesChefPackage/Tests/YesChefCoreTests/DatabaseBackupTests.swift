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
#if DEBUG
    #expect(YesChefCloudSync.databaseBackupConfiguration.displayName == "Yes Chef Dev")
    #expect(YesChefCloudSync.databaseBackupConfiguration.backupFilenamePrefix == "YesChef-Dev-Backup-")
    #expect(YesChefCloudSync.databaseBackupConfiguration.variant == .development)
    #expect(YesChefCloudSync.automaticBackupConfiguration == nil)
#else
    #expect(YesChefCloudSync.databaseBackupConfiguration.displayName == "Yes Chef")
    #expect(YesChefCloudSync.databaseBackupConfiguration.backupFilenamePrefix == "YesChef-Backup-")
    #expect(YesChefCloudSync.databaseBackupConfiguration.variant == .production)
    #expect(YesChefCloudSync.automaticBackupConfiguration?.filenamePrefix == "YesChef-Auto-")
    #expect(YesChefCloudSync.automaticBackupConfiguration?.libraryCountTableName == "recipes")
    #expect(YesChefCloudSync.automaticBackupConfiguration?.retention == .init(daily: 14, monthly: 6))
    #expect(YesChefCloudSync.automaticBackupConfiguration?.installIDDefaultsKey == "YesChefAutomaticBackupInstallID")
    #expect(YesChefCloudSync.automaticBackupConfiguration?.enabledDefaultsKey == "YesChefAutomaticBackupEnabled")
#endif
    try database.close()
  }

  @Test
  func aNonYesChefSQLiteFileIsRejected() throws {
    let databaseURL = try temporaryDirectory().appendingPathComponent("other.sqlite")
    let database = try DatabaseQueue(path: databaseURL.path)
    try database.write { db in try db.execute(sql: "CREATE TABLE unrelated (id TEXT PRIMARY KEY)") }
    #expect(throws: DatabaseBackup.BackupError.self) {
      try DatabaseBackup.validateAppSchema(in: databaseURL, configuration: YesChefCloudSync.databaseBackupConfiguration)
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

  @Test
  @MainActor
  func automaticSnapshotRestoresThroughTheExistingImporter() async throws {
    let directoryURL = try temporaryDirectory()
    let liveURL = directoryURL.appendingPathComponent("live.sqlite")
    let database = try pathBackedDatabase(at: liveURL)
    let recipeID = SampleUUIDSequence.uuid(73)
    try await database.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Automatic Backup Round Trip",
          dateCreated: Date(timeIntervalSinceReferenceDate: 811_000_000),
          dateModified: Date(timeIntervalSinceReferenceDate: 811_000_000)
        )
      }
      .execute(db)
    }

    let containerURL = directoryURL.appendingPathComponent("iCloud", isDirectory: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let automaticConfiguration = AutomaticBackupConfiguration(
      filenamePrefix: "YesChef-Auto-",
      libraryCountTableName: "recipes",
      installIDDefaultsKey: "YesChefAutomaticBackupInstallID",
      enabledDefaultsKey: "YesChefAutomaticBackupEnabled"
    )
    let client = AutomaticBackupClient(
      containerURL: { _ in containerURL },
      listFiles: { folder, prefix in
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let files = try urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "sqlite" }
          .map { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return AutomaticBackupFile(
              url: url,
              date: attributes[.modificationDate] as? Date ?? .distantPast,
              bytes: attributes[.size] as? Int ?? 0,
              isDownloaded: true
            )
          }
        return AutomaticBackupListing(files: files, isComplete: true)
      },
      readManifest: { url in
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
      },
      writeManifest: { data, url in
        try data.write(to: url, options: .atomic)
      },
      moveCoordinated: { source, destination in
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
      },
      removeCoordinated: { url in
        try FileManager.default.removeItem(at: url)
      }
    )
    let suiteName = "AutomaticBackupTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let status = await withDependencies {
      $0.defaultDatabase = database
      $0.automaticBackupClient = client
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      let model = AutomaticBackupModel(
        backup: YesChefCloudSync.databaseBackupConfiguration,
        configuration: automaticConfiguration,
        defaults: defaults
      )
      await model.backUpNow()
      return model.status
    }

    guard case let .lastBackup(_, bytes) = status else {
      Issue.record("Expected the automatic backup to complete, got \(status).")
      return
    }
    #expect(bytes > 0)
    let backupFolder = containerURL.appendingPathComponent("Documents/Backups", isDirectory: true)
    let automaticFile = try #require(
      FileManager.default.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: nil)
        .first { $0.lastPathComponent.hasPrefix("YesChef-Auto-") && $0.pathExtension == "sqlite" }
    )
    let prepared = try await DatabaseBackup.prepareRestore(
      from: automaticFile,
      to: directoryURL.appendingPathComponent("prepared.sqlite"),
      currentSchemaVersion: YesChefCloudSync.databaseBackupConfiguration.declaredSchemaVersion,
      configuration: YesChefCloudSync.databaseBackupConfiguration,
      migrate: YesChefCloudSync.databaseBackupConfiguration.migrate
    )
    let restored = try DatabaseQueue(path: prepared.fileURL.path)
    let title = try await restored.read { db in try Recipe.find(recipeID).fetchOne(db)?.title }
    #expect(title == "Automatic Backup Round Trip")
    try restored.close()
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
