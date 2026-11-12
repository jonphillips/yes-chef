import SQLiteData

public enum GroceryCanonicalNameCache {
  public static func backfill(in db: Database) throws {
    for var line in try IngredientLine.fetchAll(db) where line.canonicalName == nil {
      line.canonicalName = CanonicalIngredient.canonicalName(line.item ?? line.originalText)
      try IngredientLine.upsert { line }.execute(db)
    }

    for var item in try GroceryItem.fetchAll(db) where item.canonicalName == nil {
      item.canonicalName = CanonicalIngredient.canonicalName(item.title)
      try GroceryItem.upsert { item }.execute(db)
    }
  }

  /// Recomputes every cached key that the current `CanonicalIngredient` rules would compute differently.
  /// Runs as a post-engine data pass, so the corrected keys are ordinary synced writes. Idempotent.
  public static func refreshStale(in db: Database) throws -> Int {
    var updated = 0
    for var line in try IngredientLine.fetchAll(db) {
      let key = CanonicalIngredient.canonicalName(line.item ?? line.originalText)
      guard line.canonicalName != key else { continue }
      line.canonicalName = key
      try IngredientLine.upsert { line }.execute(db)
      updated += 1
    }

    for var item in try GroceryItem.fetchAll(db) {
      let key = CanonicalIngredient.canonicalName(item.title)
      guard item.canonicalName != key else { continue }
      item.canonicalName = key
      try GroceryItem.upsert { item }.execute(db)
      updated += 1
    }
    return updated
  }
}

