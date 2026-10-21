import CloudSyncKit
import CustomDump
import Foundation
import GRDB
import Testing
@testable import YesChef

@Suite
struct SyncFailureDisplayRowsTests {
  @Test
  func recipeRowsUseTheirTitles() throws {
    let database = try makeDatabase()
    let firstID = uuid(1)
    let secondID = uuid(2)
    try seedRecipe(firstID, title: "Tomato Soup", in: database)
    try seedRecipe(secondID, title: "Roast Chicken", in: database)

    let report = SyncFailureReport(notUploaded: [NotUploadedRecordGroup(
      recordType: "recipes",
      count: 2,
      primaryKeys: [firstID.uuidString, secondID.uuidString]
    )], notAppliedCount: 0)
    let rows = try database.read { try SyncHealthModel.makeNotUploadedRows(from: report, in: $0) }

    expectNoDifference(rows, [
      NotUploadedDisplayRow(
        recordType: "recipes", primaryKeys: [firstID.uuidString], title: "Tomato Soup", detail: "Recipe"
      ),
      NotUploadedDisplayRow(
        recordType: "recipes", primaryKeys: [secondID.uuidString], title: "Roast Chicken", detail: "Recipe"
      ),
    ])
  }

  @Test
  func recipeChildrenGroupUnderTheirRecipe() throws {
    let database = try makeDatabase()
    let recipeID = uuid(10)
    let firstLineID = uuid(11)
    let secondLineID = uuid(12)
    try seedRecipe(recipeID, title: "Tomato Soup", in: database)
    try database.write { db in
      try db.execute(
        sql: "INSERT INTO ingredientLines (id, recipeID) VALUES (?, ?), (?, ?)",
        arguments: [firstLineID.uuidString, recipeID.uuidString, secondLineID.uuidString, recipeID.uuidString]
      )
    }

    let report = SyncFailureReport(notUploaded: [NotUploadedRecordGroup(
      recordType: "ingredientLines",
      count: 2,
      primaryKeys: [firstLineID.uuidString, secondLineID.uuidString]
    )], notAppliedCount: 0)
    let rows = try database.read { try SyncHealthModel.makeNotUploadedRows(from: report, in: $0) }

    expectNoDifference(rows, [NotUploadedDisplayRow(
      recordType: "ingredientLines",
      primaryKeys: [firstLineID.uuidString, secondLineID.uuidString],
      title: "Tomato Soup",
      detail: "2 ingredient lines"
    )])
  }

  @Test
  func childWithoutARecipeFallsBackToItsTable() throws {
    let database = try makeDatabase()
    let missingRecipeID = uuid(20)
    let stepID = uuid(21)
    try database.write { db in
      try db.execute(
        sql: "INSERT INTO instructionSteps (id, recipeID) VALUES (?, ?)",
        arguments: [stepID.uuidString, missingRecipeID.uuidString]
      )
    }

    let report = SyncFailureReport(notUploaded: [NotUploadedRecordGroup(
      recordType: "instructionSteps", count: 1, primaryKeys: [stepID.uuidString]
    )], notAppliedCount: 0)
    let rows = try database.read { try SyncHealthModel.makeNotUploadedRows(from: report, in: $0) }

    expectNoDifference(rows, [NotUploadedDisplayRow(
      recordType: "instructionSteps",
      primaryKeys: [stepID.uuidString],
      title: "1 row",
      detail: "Instruction Steps"
    )])
  }

  @Test
  func rowsPastTheReportKeyLimitAreShownWithoutRetryKeys() throws {
    let database = try makeDatabase()
    let recipeIDs = (1...50).map(uuid)
    try database.write { db in
      for (index, id) in recipeIDs.enumerated() {
        try db.execute(
          sql: "INSERT INTO recipes (id, title) VALUES (?, ?)",
          arguments: [id.uuidString, "Recipe \(index + 1)"]
        )
      }
    }

    let report = SyncFailureReport(notUploaded: [NotUploadedRecordGroup(
      recordType: "recipes",
      count: 60,
      primaryKeys: recipeIDs.map(\.uuidString)
    )], notAppliedCount: 0)
    let rows = try database.read { try SyncHealthModel.makeNotUploadedRows(from: report, in: $0) }

    expectNoDifference(rows.count, 51)
    expectNoDifference(rows.last, NotUploadedDisplayRow(
      recordType: "recipes",
      primaryKeys: [],
      title: "10 more recipes not listed",
      detail: "Retry the listed rows and reopen Sync to see the rest."
    ))
  }

  private func makeDatabase() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try db.execute(sql: "CREATE TABLE recipes (id TEXT PRIMARY KEY, title TEXT NOT NULL)")
      try db.execute(sql: "CREATE TABLE ingredientLines (id TEXT PRIMARY KEY, recipeID TEXT NOT NULL)")
      try db.execute(sql: "CREATE TABLE instructionSteps (id TEXT PRIMARY KEY, recipeID TEXT NOT NULL)")
    }
    return database
  }

  private func seedRecipe(_ id: UUID, title: String, in database: DatabaseQueue) throws {
    try database.write { db in
      try db.execute(
        sql: "INSERT INTO recipes (id, title) VALUES (?, ?)",
        arguments: [id.uuidString, title]
      )
    }
  }

  private func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}
