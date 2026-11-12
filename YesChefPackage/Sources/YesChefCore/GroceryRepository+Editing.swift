import Foundation
import SQLiteData

func formatGroceryQuantity(_ quantity: Double) -> String {
  if quantity.rounded() == quantity {
    return String(Int(quantity))
  }
  return String(format: "%g", quantity)
}

extension String {
  var nonEmptyGroceryText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension GroceryRepository {
  public static func sameAs(
    itemID: GroceryItem.ID,
    targetItemID: GroceryItem.ID,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try GroceryItem.find(itemID).fetchOne(db) else {
      throw GroceryRepositoryError.itemNotFound(itemID)
    }
    guard let target = try GroceryItem.find(targetItemID).fetchOne(db) else {
      throw GroceryRepositoryError.itemNotFound(targetItemID)
    }
    guard item.id != target.id, item.groceryListID == target.groceryListID else { return }

    let fixes = try IngredientNameFixes.load(in: db)
    let fromName = item.canonicalName ?? CanonicalIngredient.baseName(item.title)
    let toName = fixes.canonicalName(target.canonicalName ?? target.title)
    guard let fromName, let toName else { return }
    _ = try IngredientNameFixRepository.save(from: fromName, to: toName, in: db, now: now)

    let compatible = !item.isPurchased && !target.isPurchased
      && toName.nonEmptyGroceryText != nil
      && CanonicalIngredient.canonicalText(
        item.aisle ?? GroceryStoreArea.seed(for: toName)?.title
      ) == CanonicalIngredient.canonicalText(target.aisle)
      && CanonicalIngredient.canonicalText(item.notes) == CanonicalIngredient.canonicalText(target.notes)
      && sameAsMeasuresCanMerge(item, target)

    let sources = try GroceryItemSource.where { $0.groceryItemID.eq(item.id) }.fetchAll(db)
    if compatible {
      if let lhsQuantity = item.quantity,
         let rhsQuantity = target.quantity,
         let merged = Measure(quantity: lhsQuantity, unit: item.unit)
           .merged(with: Measure(quantity: rhsQuantity, unit: target.unit)) {
        var updatedTarget = target
        updatedTarget.quantity = merged.quantity
        updatedTarget.quantityText = formatGroceryQuantity(merged.quantity)
        updatedTarget.unit = merged.unit?.nonEmptyGroceryText
        updatedTarget.dateModified = now
        try GroceryItem.upsert { updatedTarget }.execute(db)
      }
      for var source in sources {
        source.groceryItemID = target.id
        try GroceryItemSource.upsert { source }.execute(db)
      }
      try GroceryItem.find(item.id).delete().execute(db)
    } else {
      item.title = target.title
      item.canonicalName = CanonicalIngredient.baseName(target.title)
      item.aisle = target.aisle
      item.dateModified = now
      try GroceryItem.upsert { item }.execute(db)
    }
  }

  public static func updateItem(
    itemID: GroceryItem.ID,
    title: String,
    quantityText: String? = nil,
    unit: String? = nil,
    aisle: String? = nil,
    notes: String? = nil,
    in db: Database,
    now: Date,
    uuid: () -> UUID
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
    let didChangeAisle = item.aisle != aisle
    let didChangeDisplayFields = item.title != title
      || item.quantityText != quantityText
      || item.unit != unit
      || item.aisle != aisle
      || item.notes != notes

    item.title = title
    item.canonicalName = CanonicalIngredient.baseName(title)
    item.quantityText = quantityText
    item.unit = unit
    item.aisle = aisle
    item.notes = notes
    if didChangeDisplayFields {
      item.quantity = nil
    }
    item.dateModified = now
    try GroceryItem.upsert { item }.execute(db)

    if didChangeAisle, let aisle {
      try GroceryStoreAreaCache.applyUserCorrection(
        canonicalName: item.canonicalName,
        area: aisle,
        in: db,
        now: now,
        uuid: uuid
      )
    }
  }
}

private func sameAsMeasuresCanMerge(_ lhs: GroceryItem, _ rhs: GroceryItem) -> Bool {
  switch (
    lhs.quantity.map { Measure(quantity: $0, unit: lhs.unit) },
    rhs.quantity.map { Measure(quantity: $0, unit: rhs.unit) }
  ) {
  case let (.some(lhsMeasure), .some(rhsMeasure)):
    return lhsMeasure.merged(with: rhsMeasure) != nil
  case (.none, .none):
    return lhs.quantityText == nil && rhs.quantityText == nil
  default:
    return false
  }
}
