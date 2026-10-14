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
      || skippedForUnsentParentCount > 0
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
/// record limit. The caller supplies the on-server identity set read from SyncMetadata.
public enum RecipeSyncRepair {
  public static func run(
    onServerRecords: Set<RecipeSyncRecordID>,
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

    let serverRecipeIDs = Set(onServerRecords.filter { $0.table == Recipe.tableName }.map(\.primaryKey))
    guard !serverRecipeIDs.isEmpty else { return audit }

    let recipeIDs = try String.fetchAll(db, sql: #"SELECT "id" FROM "recipes""#)
    let unsentRecipeIDs = recipeIDs.filter { !onServerRecords.contains(recordID(Recipe.tableName, $0)) }
    audit.requeuedRecipeCount = unsentRecipeIDs.count
    try requeue(unsentRecipeIDs, table: Recipe.tableName, in: db)

    let serverParentIDs = Array(serverRecipeIDs)
    let tables = try recipeIDChildTables(in: db)
    for table in tables {
      let serverChildIDs = onServerRecords.filter { $0.table == table }.map(\.primaryKey)
      audit.skippedForUnsentParentCount += try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM \"\(quoted(table))\" WHERE \"recipeID\" IS NOT NULL AND \"recipeID\" NOT IN (\(placeholders(serverParentIDs.count)))",
        arguments: StatementArguments(serverParentIDs)
      ) ?? 0
      let childIDs = try String.fetchAll(
        db,
        sql: "SELECT \"id\" FROM \"\(quoted(table))\" WHERE \"recipeID\" IN (\(placeholders(serverParentIDs.count)))",
        arguments: StatementArguments(serverParentIDs)
      )
      let unsentChildIDs = childIDs.filter { !serverChildIDs.contains($0.lowercased()) }
      audit.requeuedChildCount += unsentChildIDs.count
      try requeue(unsentChildIDs, table: table, in: db)
    }

    let recipes = try Recipe.fetchAll(db)
    let linkedMealPlan = try relinkMealPlanItems(recipes: recipes, serverRecipeIDs: serverRecipeIDs, in: db)
    let linkedMenu = try relinkMenuItems(recipes: recipes, serverRecipeIDs: serverRecipeIDs, in: db)
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

  private static func recipeIDChildTables(in db: Database) throws -> [String] {
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
    )
  }

  private static func requeue(_ ids: [String], table: String, in db: Database) throws {
    guard !ids.isEmpty else { return }
    try db.execute(
      sql: "UPDATE \"\(quoted(table))\" SET \"id\" = \"id\" WHERE \"id\" IN (\(placeholders(ids.count)))",
      arguments: StatementArguments(ids)
    )
  }

  private static func recordID(_ table: String, _ primaryKey: String) -> RecipeSyncRecordID {
    RecipeSyncRecordID(table: table, primaryKey: primaryKey)
  }

  private static func placeholders(_ count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ", ")
  }

  private static func quoted(_ identifier: String) -> String {
    identifier.replacingOccurrences(of: "\"", with: "\"\"")
  }
}
