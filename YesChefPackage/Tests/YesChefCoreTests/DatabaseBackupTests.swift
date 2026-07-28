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
