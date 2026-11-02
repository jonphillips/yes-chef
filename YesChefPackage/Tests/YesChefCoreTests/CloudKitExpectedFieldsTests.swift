import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized)
struct CloudKitExpectedFieldsTests {
  @Test
  func committedFieldsMatchTheMigratedSyncedSchema() throws {
    let databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefCloudKitExpectedFields-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("library.sqlite")
    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let database = try withDependencies {
      $0.context = .live
    } operation: {
      var dependencies = DependencyValues()
      try dependencies.bootstrapDatabase(path: databaseURL.path)
      return dependencies.defaultDatabase
    }
    defer { try? database.close() }

    let expectedFields = try database.read { db in
      try YesChefCloudSync.syncedTables.recordTypes.flatMap { recordType -> [String] in
        let columns = try String.fetchAll(
          db,
          sql: "SELECT name || '|' || type FROM pragma_table_info(?)",
          arguments: [recordType]
        )
        var fields = [
          "\(recordType) sqlitedata_icloud_userModificationTime",
        ]
        for column in columns {
          let components = column.split(separator: "|", maxSplits: 1)
          guard components.count == 2 else { continue }
          let name = String(components[0])
          let type = String(components[1])
          fields.append("\(recordType) \(name)")
          fields.append("\(recordType) sqlitedata_icloud_userModificationTime_\(name)")
          if type.uppercased() == "BLOB" {
            fields.append("\(recordType) \(name)_hash")
          }
        }
        return fields
      }.sorted()
    }

    let expectedFieldsURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("cloudkit-expected-fields.txt")

    if ProcessInfo.processInfo.environment["YESCHEF_RECORD_CLOUDKIT_FIELDS"] == "1" {
      try (expectedFields.joined(separator: "\n") + "\n").write(
        to: expectedFieldsURL,
        atomically: true,
        encoding: .utf8
      )
      #expect(Bool(false), "Regenerated cloudkit-expected-fields.txt; rerun the test without YESCHEF_RECORD_CLOUDKIT_FIELDS=1.")
      return
    }

    let committedFields = try String(contentsOf: expectedFieldsURL, encoding: .utf8)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
    let added = Set(expectedFields).subtracting(committedFields).sorted()
    let removed = Set(committedFields).subtracting(expectedFields).sorted()
    #expect(
      committedFields == expectedFields,
      "CloudKit expected fields are stale. Added:\n\(added.joined(separator: "\n"))\nRemoved:\n\(removed.joined(separator: "\n"))\nRegenerate with YESCHEF_RECORD_CLOUDKIT_FIELDS=1 swift test --package-path YesChefPackage --filter CloudKitExpectedFieldsTests."
    )
  }
}
