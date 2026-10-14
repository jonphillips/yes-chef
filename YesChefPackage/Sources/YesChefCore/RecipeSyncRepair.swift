import Foundation
import GRDB
import SQLiteData

/// A stable, testable projection of SQLiteData's CloudKit metadata identity.
public struct RecipeSyncRecordID: Hashable, Sendable {
  public var table: String
  public var primaryKey: String

  public init(table: String, primaryKey: String) {
    self.table = table
    self.primaryKey = primaryKey.lowercased()
  }
}

/// The small system-fields metadata used to decide whether CloudKit confirmed a save.
public struct RecipeSyncMetadataState: Hashable, Sendable {
  public var recordID: RecipeSyncRecordID
  public var hasServerChangeTag: Bool

  public init(recordID: RecipeSyncRecordID, hasServerChangeTag: Bool) {
    self.recordID = recordID
    self.hasServerChangeTag = hasServerChangeTag
  }
}

public struct RecipeSyncRepairAudit: Equatable, Sendable {
  public var deletedPhotoCount: Int
  public var requeuedRecipeCount: Int
  public var requeuedChildCount: Int
  public var linkedMealPlanCount: Int
  public var linkedMenuCount: Int
  public var unmatchedMealPlanCount: Int
  public var unmatchedMenuCount: Int
  public var ambiguousMealPlanCount: Int
  public var ambiguousMenuCount: Int
  public var skippedForUnsentParentCount: Int

  public var hasFindings: Bool {
    deletedPhotoCount > 0 || requeuedRecipeCount > 0 || requeuedChildCount > 0
      || linkedMealPlanCount > 0 || linkedMenuCount > 0 || unmatchedMealPlanCount > 0
      || unmatchedMenuCount > 0 || ambiguousMealPlanCount > 0 || ambiguousMenuCount > 0
  }

  public var logSummary: String {
    "recipe-sync-repair deletedPhotos=\(deletedPhotoCount) requeuedRecipes=\(requeuedRecipeCount) "
      + "requeuedChildren=\(requeuedChildCount) linkedMealPlan=\(linkedMealPlanCount) "
      + "linkedMenu=\(linkedMenuCount) unmatchedMealPlan=\(unmatchedMealPlanCount) "
      + "unmatchedMenu=\(unmatchedMenuCount) ambiguousMealPlan=\(ambiguousMealPlanCount) "
      + "ambiguousMenu=\(ambiguousMenuCount) skippedUnsentParentChildren=\(skippedForUnsentParentCount)"
  }
}

/// Repairs records that SQLiteData did not upload because an earlier row exceeded CloudKit's
/// record limit. The caller supplies metadata states whose change tags confirm server saves.
public enum RecipeSyncRepair {
  public static func run(
    recipeMetadata: [RecipeSyncMetadataState],
    syncedTableNames: Set<String>,
    childMetadataFor: (String, [String], Database) throws -> [RecipeSyncMetadataState],
    in db: Database
  ) throws -> RecipeSyncRepairAudit {
    var audit = RecipeSyncRepairAudit(
      deletedPhotoCount: 0,
      requeuedRecipeCount: 0,
      requeuedChildCount: 0,
      linkedMealPlanCount: 0,
      linkedMenuCount: 0,
      unmatchedMealPlanCount: 0,
      unmatchedMenuCount: 0,
      ambiguousMealPlanCount: 0,
      ambiguousMenuCount: 0,
      skippedForUnsentParentCount: 0
    )

    // Remove URL-only and failed-download rows before re-queueing children.
    try db.execute(sql: #"""
      UPDATE "recipes"
      SET "coverPhotoID" = NULL
      WHERE "coverPhotoID" IN (
        SELECT "id" FROM "recipePhotos"
        WHERE "displayData" IS NULL AND "thumbnailData" IS NULL
      )
      """#)
    audit.deletedPhotoCount = try Int.fetchOne(
      db,
      sql: #"SELECT COUNT(*) FROM "recipePhotos" WHERE "displayData" IS NULL AND "thumbnailData" IS NULL"#
    ) ?? 0
    try db.execute(sql: #"DELETE FROM "recipePhotos" WHERE "displayData" IS NULL AND "thumbnailData" IS NULL"#)

    let recipeIDs = try String.fetchAll(db, sql: #"SELECT "id" FROM "recipes""#)
    let recipeMetadataByID = Dictionary(
      uniqueKeysWithValues: recipeMetadata
        .filter { $0.recordID.table == Recipe.tableName }
        .map { ($0.recordID.primaryKey, $0) }
    )
    let confirmedRecipeIDs = Set(
      recipeMetadata.filter {
        $0.recordID.table == Recipe.tableName && $0.hasServerChangeTag
      }.map(\.recordID.primaryKey)
    )
    let unconfirmedRecipeIDs = recipeIDs.filter { !confirmedRecipeIDs.contains($0.lowercased()) }
    audit.requeuedRecipeCount = unconfirmedRecipeIDs.count
    try rememberRecipes(unconfirmedRecipeIDs, in: db)
    try clearMetadata(
      for: unconfirmedRecipeIDs.filter { recipeMetadataByID[$0.lowercased()] != nil },
      table: Recipe.tableName,
      in: db
    )
    try requeue(
      unconfirmedRecipeIDs.filter { recipeMetadataByID[$0.lowercased()] == nil },
      table: Recipe.tableName,
      in: db
    )

    let queuedRecipeIDs = Set(try String.fetchAll(db, sql: #"SELECT "recipeID" FROM "recipeSyncRepairQueue""#).map { $0.lowercased() })
    let readyParentIDs = queuedRecipeIDs.intersection(confirmedRecipeIDs).sorted()
    let tables = try recipeIDChildTables(in: db, syncedTableNames: syncedTableNames)
    for table in tables {
      let childParentIDs = try String.fetchAll(
        db,
        sql: "SELECT \"recipeID\" FROM \"\(quoted(table))\" WHERE \"recipeID\" IS NOT NULL"
      )
      audit.skippedForUnsentParentCount += childParentIDs.filter {
        !confirmedRecipeIDs.contains($0.lowercased())
      }.count
      var childIDs: Set<String> = []
      for parentChunk in chunks(readyParentIDs, size: 500) {
        childIDs.formUnion(try String.fetchAll(
          db,
          sql: "SELECT \"id\" FROM \"\(quoted(table))\" WHERE \"recipeID\" IN (\(placeholders(parentChunk.count)))",
          arguments: StatementArguments(parentChunk)
        ))
      }
      let childIDsToCheck = childIDs.sorted()
      guard !childIDsToCheck.isEmpty else { continue }
      let childMetadata = try childMetadataFor(table, childIDsToCheck, db)
      let childMetadataByID = Dictionary(
        uniqueKeysWithValues: childMetadata.map { ($0.recordID.primaryKey, $0) }
      )
      let unconfirmedChildIDs = childIDsToCheck.filter {
        childMetadataByID[$0.lowercased()]?.hasServerChangeTag != true
      }
      audit.requeuedChildCount += unconfirmedChildIDs.count
      try clearMetadata(
        for: unconfirmedChildIDs.filter { childMetadataByID[$0.lowercased()] != nil },
        table: table,
        in: db
      )
      try requeue(
        unconfirmedChildIDs.filter { childMetadataByID[$0.lowercased()] == nil },
        table: table,
        in: db
      )
    }

    try forgetRecipes(readyParentIDs, in: db)

    let recipes = try Recipe.fetchAll(db)
    let linkedMealPlan = try relinkMealPlanItems(recipes: recipes, serverRecipeIDs: confirmedRecipeIDs, in: db)
    let linkedMenu = try relinkMenuItems(recipes: recipes, serverRecipeIDs: confirmedRecipeIDs, in: db)
    audit.linkedMealPlanCount = linkedMealPlan.linked
    audit.unmatchedMealPlanCount = linkedMealPlan.unmatched
    audit.ambiguousMealPlanCount = linkedMealPlan.ambiguous
    audit.linkedMenuCount = linkedMenu.linked
    audit.unmatchedMenuCount = linkedMenu.unmatched
    audit.ambiguousMenuCount = linkedMenu.ambiguous
    return audit
  }

  private static func relinkMealPlanItems(
    recipes: [Recipe], serverRecipeIDs: Set<String>, in db: Database
  ) throws -> (linked: Int, unmatched: Int, ambiguous: Int) {
    let candidates = Dictionary(grouping: recipes.filter { !$0.archived }, by: \.title)
    var linked = 0, unmatched = 0, ambiguous = 0
    for var item in try MealPlanItem.fetchAll(db) where item.kind == .recipe && item.recipeID == nil {
      let matches = (candidates[item.title] ?? []).filter { serverRecipeIDs.contains($0.id.uuidString.lowercased()) }
      switch matches.count {
      case 0:
        unmatched += 1
      case 1:
        item.recipeID = matches[0].id
        try MealPlanItem.upsert { item }.execute(db)
        linked += 1
      default: ambiguous += 1
      }
    }
    return (linked, unmatched, ambiguous)
  }

  private static func relinkMenuItems(
    recipes: [Recipe], serverRecipeIDs: Set<String>, in db: Database
  ) throws -> (linked: Int, unmatched: Int, ambiguous: Int) {
    let candidates = Dictionary(grouping: recipes.filter { !$0.archived }, by: \.title)
    var linked = 0, unmatched = 0, ambiguous = 0
    for var item in try MenuItem.fetchAll(db) where item.kind == .recipe && item.recipeID == nil {
      let matches = (candidates[item.title] ?? []).filter { serverRecipeIDs.contains($0.id.uuidString.lowercased()) }
      switch matches.count {
      case 0:
        unmatched += 1
      case 1:
        item.recipeID = matches[0].id
        try MenuItem.upsert { item }.execute(db)
        linked += 1
      default: ambiguous += 1
      }
    }
    return (linked, unmatched, ambiguous)
  }

  private static func recipeIDChildTables(in db: Database, syncedTableNames: Set<String>) throws -> [String] {
    try String.fetchAll(
      db,
      sql: #"""
        SELECT DISTINCT tables.name
        FROM sqlite_master AS tables
        JOIN pragma_foreign_key_list(tables.name) AS foreign_keys
          ON foreign_keys."table" = 'recipes' AND foreign_keys."from" = 'recipeID'
        WHERE tables.type = 'table' AND tables.name NOT LIKE 'sqlite_%'
          AND tables.name != 'recipes'
        ORDER BY tables.name
        """#
    ).filter(syncedTableNames.contains)
  }

  private static func requeue(_ ids: [String], table: String, in db: Database) throws {
    guard !ids.isEmpty else { return }
    for idChunk in chunks(ids, size: 500) {
      try db.execute(
        sql: "UPDATE \"\(quoted(table))\" SET \"id\" = \"id\" WHERE \"id\" IN (\(placeholders(idChunk.count)))",
        arguments: StatementArguments(idChunk)
      )
    }
  }

  private static func clearMetadata(for ids: [String], table: String, in db: Database) throws {
    for idChunk in chunks(ids, size: 500) {
      try db.execute(
        sql: #"UPDATE "sqlitedata_icloud_metadata" SET "lastKnownServerRecord" = NULL, "_lastKnownServerRecordAllFields" = NULL WHERE "recordType" = ? AND "recordPrimaryKey" IN (\#(placeholders(idChunk.count)))"#,
        arguments: StatementArguments([table] + idChunk)
      )
    }
  }

  private static func rememberRecipes(_ ids: [String], in db: Database) throws {
    for idChunk in chunks(ids, size: 500) {
      let values = idChunk.map { _ in "(?)" }.joined(separator: ", ")
      try db.execute(
        sql: "INSERT OR IGNORE INTO \"recipeSyncRepairQueue\" (\"recipeID\") VALUES \(values)",
        arguments: StatementArguments(idChunk)
      )
    }
  }

  private static func forgetRecipes(_ ids: [String], in db: Database) throws {
    for idChunk in chunks(ids, size: 500) {
      try db.execute(
        sql: "DELETE FROM \"recipeSyncRepairQueue\" WHERE \"recipeID\" IN (\(placeholders(idChunk.count)))",
        arguments: StatementArguments(idChunk)
      )
    }
  }

  private static func chunks<Element>(_ values: [Element], size: Int) -> [[Element]] {
    stride(from: 0, to: values.count, by: size).map { start in
      Array(values[start..<min(start + size, values.count)])
    }
  }

  private static func placeholders(_ count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ", ")
  }

  private static func quoted(_ identifier: String) -> String {
    identifier.replacingOccurrences(of: "\"", with: "\"\"")
  }
}
