import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite
struct SyncTableListTests {
  @Test
  func failureChecksUseTheSameTablesAsTheSyncEngine() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncTableList-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try withDependencies {
      $0.context = .live
    } operation: {
      var dependencies = DependencyValues()
      try dependencies.bootstrapDatabase(path: directory.appendingPathComponent("SQLiteData.db").path)
      let database = dependencies.defaultDatabase
      _ = try YesChefCloudSync.makeSyncEngine(for: database, startImmediately: false)

      let triggerNames = try database.write { db in
        try String.fetchAll(db, sql: """
          SELECT "name" FROM "sqlite_temp_master"
          WHERE "type" = 'trigger' AND "name" LIKE 'sqlitedata_icloud_after_insert_on_%'
          """)
          .filter { !$0.hasPrefix("sqlitedata_icloud_after_insert_on_sqlitedata_icloud_") }
          .map { String($0.dropFirst("sqlitedata_icloud_after_insert_on_".count)) }
          .sorted()
      }
      #expect(triggerNames == YesChefCloudSync.syncedTables.recordTypes.sorted())
      #expect(Set(YesChefCloudSync.retiredRecordTypes).isDisjoint(
        with: Set(YesChefCloudSync.syncedTables.recordTypes)
      ))
    }
  }
}
