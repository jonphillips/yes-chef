import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct StoredValuesCompatibilityTests {
  @Dependency(\.defaultDatabase) var database

  @Test func legacyDateUUIDAndStringSurviveReadAndWrite() throws {
    let legacyDate = "2026-02-08 12:13:14.061"
    let legacyUUID = "00112233-4455-6677-8899-aabbccddeeff"
    let legacyString = "Crème brûlée"

    let original = try database.write { db in
      try #sql(
        """
        INSERT INTO records (id, title, date, uuid)
        VALUES (1, 'Crème brûlée', '2026-02-08 12:13:14.061',
          '00112233-4455-6677-8899-aabbccddeeff')
        """
      )
      .execute(db)
      return try Record.find(1).fetchOne(db)!
    }

    try database.write { db in
      try Record.update(original).execute(db)
    }

    try database.read { db in
      let restored = try Record.find(1).fetchOne(db)!
      #expect(restored == original)
      #expect(restored.title == legacyString)
      #expect(
        try #sql("SELECT date FROM records WHERE id = 1", as: String.self).fetchOne(db)
          == legacyDate
      )
      #expect(
        try #sql("SELECT uuid FROM records WHERE id = 1", as: String.self).fetchOne(db)
          == legacyUUID
      )
    }
  }
}

@Table
private struct Record: Equatable {
  let id: Int
  var title: String
  var date: Date
  var uuid: UUID
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY,
          "title" TEXT NOT NULL,
          "date" TEXT NOT NULL,
          "uuid" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    return database
  }
}
