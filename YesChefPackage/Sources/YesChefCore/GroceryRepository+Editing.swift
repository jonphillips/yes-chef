import Foundation
import SQLiteData

extension GroceryRepository {
  public static func updateItem(
    itemID: GroceryItem.ID,
    title: String,
    quantityText: String? = nil,
    unit: String? = nil,
    aisle: String? = nil,
    notes: String? = nil,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try GroceryItem.find(itemID).fetchOne(db) else {
      throw GroceryRepositoryError.itemNotFound(itemID)
    }
    guard let title = title.nonEmptyGroceryText else {
      throw GroceryRepositoryError.emptyItemTitle
    }

    let quantityText = quantityText?.nonEmptyGroceryText
    let unit = unit?.nonEmptyGroceryText
    let aisle = aisle?.nonEmptyGroceryText
    let notes = notes?.nonEmptyGroceryText
    let didChangeDisplayFields = item.title != title
      || item.quantityText != quantityText
      || item.unit != unit
      || item.aisle != aisle
      || item.notes != notes

    item.title = title
    item.canonicalName = CanonicalIngredient.canonicalName(title)
    item.quantityText = quantityText
    item.unit = unit
    item.aisle = aisle
    item.notes = notes
    if didChangeDisplayFields {
      item.quantity = nil
    }
    item.dateModified = now
    try GroceryItem.upsert { item }.execute(db)
  }
}
