import CloudKit
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct DataPassesTests {
    @Test
    func runsForMissingAndOlderVersionAndSkipsCurrentVersion() async throws {
      @Dependency(\.defaultDatabase) var database
      let recipeID = SampleUUIDSequence.uuid(91_001)
      let sectionID = SampleUUIDSequence.uuid(91_002)
      let lineID = SampleUUIDSequence.uuid(91_003)
      try await database.write { db in
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_metadata" ("recordPrimaryKey" TEXT NOT NULL, "recordType" TEXT NOT NULL, "lastKnownServerRecord" BLOB, "hasLastKnownServerRecord" INTEGER NOT NULL DEFAULT 0, "_lastKnownServerRecordAllFields" BLOB, PRIMARY KEY ("recordPrimaryKey", "recordType"))"#)
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_recordTypes" ("tableName" TEXT NOT NULL)"#)
        try Recipe.insert { Recipe(id: recipeID, title: "Range", dateCreated: .distantPast, dateModified: .distantPast) }.execute(db)
        try IngredientSection.insert { IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0) }.execute(db)
        try IngredientLine.insert { IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "8-10 ounces kale", sortOrder: 0, confidence: .low) }.execute(db)
      }
      await YesChefDataPasses.runIfNeeded(in: database)
      try await database.write { db in
        #expect(try Int.fetchOne(db, sql: "SELECT version FROM localDataPassState") == YesChefDataPasses.currentVersion)
        #expect(try IngredientLine.find(lineID).fetchOne(db)?.quantity == 10)
        try db.execute(sql: "UPDATE ingredientLines SET quantity = NULL")
      }
      await YesChefDataPasses.runIfNeeded(in: database)
      try await database.write { db in
        #expect(try IngredientLine.find(lineID).fetchOne(db)?.quantity == nil)
        try db.execute(sql: "UPDATE localDataPassState SET version = 0")
      }
      await YesChefDataPasses.runIfNeeded(in: database)
      try await database.read { db throws in
        #expect(try IngredientLine.find(lineID).fetchOne(db)?.quantity == 10)
        #expect(try Int.fetchOne(db, sql: "SELECT version FROM localDataPassState") == YesChefDataPasses.currentVersion)
      }
      #expect(!YesChefCloudSync.syncedTables.recordTypes.contains("localDataPassState"))
    }

    @Test
    func currentVersionDrainsConfirmedRepairQueueThenSkips() async throws {
      @Dependency(\.defaultDatabase) var database
      let recipeID = SampleUUIDSequence.uuid(93_001)
      let sectionID = SampleUUIDSequence.uuid(93_002)
      let lineID = SampleUUIDSequence.uuid(93_003)
      let recipeKey = recipeID.uuidString.lowercased()
      let sectionKey = sectionID.uuidString.lowercased()
      let record = CKRecord(recordType: "recipes", recordID: CKRecord.ID(recordName: "\(recipeKey):recipes"))
      let archiver = NSKeyedArchiver(requiringSecureCoding: true)
      record.encodeSystemFields(with: archiver)
      archiver.encode("confirmed" as NSString, forKey: "ETag")
      let confirmedRecord = archiver.encodedData
      try await database.write { db in
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_metadata" ("recordPrimaryKey" TEXT NOT NULL, "recordType" TEXT NOT NULL, "lastKnownServerRecord" BLOB, "hasLastKnownServerRecord" INTEGER NOT NULL DEFAULT 0, "_lastKnownServerRecordAllFields" BLOB, PRIMARY KEY ("recordPrimaryKey", "recordType"))"#)
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_recordTypes" ("tableName" TEXT NOT NULL)"#)
        try db.execute(sql: "INSERT INTO localDataPassState (id, version) VALUES (1, ?)", arguments: [YesChefDataPasses.currentVersion])
        try Recipe.insert { Recipe(id: recipeID, title: "Queued", dateCreated: .distantPast, dateModified: .distantPast) }.execute(db)
        try IngredientSection.insert { IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0) }.execute(db)
        try IngredientLine.insert { IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "8-10 ounces kale", sortOrder: 0, confidence: .low) }.execute(db)
        try db.execute(sql: #"INSERT INTO "recipeSyncRepairQueue" ("recipeID") VALUES (?)"#, arguments: [recipeKey])
        try db.execute(sql: #"INSERT INTO "sqlitedata_icloud_recordTypes" ("tableName") VALUES ('recipes'), ('ingredientSections')"#)
        try db.execute(sql: #"INSERT INTO "sqlitedata_icloud_metadata" ("recordPrimaryKey", "recordType", "lastKnownServerRecord", "hasLastKnownServerRecord") VALUES (?, 'recipes', ?, 1), (?, 'ingredientSections', X'01', 0)"#, arguments: [recipeKey, confirmedRecord, sectionKey])
      }
      await YesChefDataPasses.runIfNeeded(in: database)
      try await database.read { db throws in
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM recipeSyncRepairQueue") == 0)
        #expect(try Data.fetchOne(db, sql: #"SELECT "lastKnownServerRecord" FROM "sqlitedata_icloud_metadata" WHERE "recordType" = 'ingredientSections'"#) == nil)
        #expect(try Int.fetchOne(db, sql: "SELECT version FROM localDataPassState") == YesChefDataPasses.currentVersion)
        #expect(try IngredientLine.find(lineID).fetchOne(db)?.quantity == nil)
      }
      await YesChefDataPasses.runIfNeeded(in: database)
      try await database.read { db throws in
        #expect(try IngredientLine.find(lineID).fetchOne(db)?.quantity == nil)
        #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM recipeSyncRepairQueue") == 0)
      }
    }

    @Test
    func failureLeavesVersionUnchangedAndLaterPassesRun() async throws {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_metadata" ("recordPrimaryKey" TEXT NOT NULL, "recordType" TEXT NOT NULL, "lastKnownServerRecord" BLOB, "hasLastKnownServerRecord" INTEGER NOT NULL DEFAULT 0, "_lastKnownServerRecordAllFields" BLOB, PRIMARY KEY ("recordPrimaryKey", "recordType"))"#)
        try db.execute(sql: #"CREATE TABLE IF NOT EXISTS "sqlitedata_icloud_recordTypes" ("tableName" TEXT NOT NULL)"#)
        try db.execute(sql: "INSERT INTO localDataPassState (id, version) VALUES (1, 0)")
        let recipeID = SampleUUIDSequence.uuid(92_001)
        let sectionID = SampleUUIDSequence.uuid(92_002)
        try Recipe.insert { Recipe(id: recipeID, title: "Range", dateCreated: .distantPast, dateModified: .distantPast) }.execute(db)
        try IngredientSection.insert { IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0) }.execute(db)
        try IngredientLine.insert { IngredientLine(id: SampleUUIDSequence.uuid(92_003), recipeID: recipeID, sectionID: sectionID, originalText: "8-10 ounces kale", sortOrder: 0, confidence: .low) }.execute(db)
      }
      await withKnownIssue {
        await YesChefDataPasses.runIfNeeded(in: database) { index in
          if index == 1 { throw Failure.injected }
        }
      }
      try await database.read { db throws in
        #expect(try Int.fetchOne(db, sql: "SELECT version FROM localDataPassState") == 0)
        #expect(try IngredientLine.find(SampleUUIDSequence.uuid(92_003)).fetchOne(db)?.quantity == 10)
      }
    }

    enum Failure: Error { case injected }
  }
}
