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
}

