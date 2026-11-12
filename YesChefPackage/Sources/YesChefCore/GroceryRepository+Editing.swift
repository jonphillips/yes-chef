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
  static func canConsolidate(
    _ lhs: GroceryItem,
    _ rhs: GroceryItem,
    fixes: IngredientNameFixes
  ) -> Bool {
    guard let lhsName = fixes.canonicalName(lhs.canonicalIngredientName),
          let rhsName = fixes.canonicalName(rhs.canonicalIngredientName),
          lhsName == rhsName
    else { return false }
    return measuresCanMerge(lhs.quantity, lhs.quantityText, lhs.unit, rhs.quantity, rhs.quantityText, rhs.unit)
  }

  static func canConsolidate(
    _ item: GroceryItem,
    with draft: GroceryGeneratedItemDraft,
    fixes: IngredientNameFixes
  ) -> Bool {
    guard let itemName = fixes.canonicalName(item.canonicalIngredientName),
          itemName == draft.fixedName
    else { return false }
    return measuresCanMerge(item.quantity, item.quantityText, item.unit, draft.quantity, draft.quantityText, draft.unit)
  }

  private static func measuresCanMerge(
    _ lhsQuantity: Double?, _ lhsQuantityText: String?, _ lhsUnit: String?,
    _ rhsQuantity: Double?, _ rhsQuantityText: String?, _ rhsUnit: String?
  ) -> Bool {
    switch (lhsQuantity, rhsQuantity) {
    case let (.some(lhs), .some(rhs)):
      return Measure(quantity: lhs, unit: lhsUnit).merged(with: Measure(quantity: rhs, unit: rhsUnit)) != nil
    case (.none, .none):
      return lhsQuantityText == nil && rhsQuantityText == nil
    default:
      return false
    }
  }

  static func mergedNotes(
    for item: GroceryItem,
    withRecipeNotes addedRecipeNotes: String?,
    sources: [GroceryItemSource],
    in db: Database
  ) throws -> String? {
    let itemParts = try noteParts(for: item.notes, sources: sources, in: db)
    return mergeNotes([itemParts, NoteParts(typed: nil, recipe: addedRecipeNotes)])
  }

  private static func mergedNotes(
    _ lhs: GroceryItem,
    sources lhsSources: [GroceryItemSource],
    with rhs: GroceryItem,
    sources rhsSources: [GroceryItemSource],
    in db: Database
  ) throws -> String? {
    mergeNotes([
      try noteParts(for: lhs.notes, sources: lhsSources, in: db),
      try noteParts(for: rhs.notes, sources: rhsSources, in: db),
    ])
  }

  private struct NoteParts {
    var typed: String?
    var recipe: String?
  }

  private static func noteParts(
    for notes: String?,
    sources: [GroceryItemSource],
    in db: Database
  ) throws -> NoteParts {
    guard let notes = notes?.nonEmptyGroceryText else { return NoteParts() }
    for source in sources {
      guard let lineID = source.ingredientLineID,
            let line = try IngredientLine.find(lineID).fetchOne(db),
            let recipeNotes = line.groceryNotes,
            CanonicalIngredient.canonicalText(notes) == CanonicalIngredient.canonicalText(recipeNotes)
      else { continue }
      return NoteParts(typed: nil, recipe: notes)
    }
    return NoteParts(typed: notes, recipe: nil)
  }

  private static func mergeNotes(_ parts: [NoteParts]) -> String? {
    var typed: [String] = []
    for note in parts.compactMap(\.typed) {
      if !typed.contains(where: { CanonicalIngredient.canonicalText($0) == CanonicalIngredient.canonicalText(note) }) {
        typed.append(note)
      }
    }
    let recipeNotes = parts.first?.recipe
    let recipesAgree = parts.allSatisfy {
      CanonicalIngredient.canonicalText($0.recipe) == CanonicalIngredient.canonicalText(recipeNotes)
    }
    let kept = typed + (recipesAgree ? recipeNotes.map { [$0] } ?? [] : [])
    var distinct: [String] = []
    for note in kept where !distinct.contains(where: {
      CanonicalIngredient.canonicalText($0) == CanonicalIngredient.canonicalText(note)
    }) {
      distinct.append(note)
    }
    return distinct.joined(separator: "; ").nonEmptyGroceryText
  }

  private static func merge(
    _ item: GroceryItem,
    into survivor: GroceryItem,
    in db: Database,
    now: Date
  ) throws -> GroceryItem {
    let itemSources = try GroceryItemSource.where { $0.groceryItemID.eq(item.id) }.fetchAll(db)
    let survivorSources = try GroceryItemSource.where { $0.groceryItemID.eq(survivor.id) }.fetchAll(db)
    var updated = survivor
    if let quantity = item.quantity, let survivorQuantity = survivor.quantity,
       let amount = Measure(quantity: survivorQuantity, unit: survivor.unit)
         .merged(with: Measure(quantity: quantity, unit: item.unit)) {
      updated.quantity = amount.quantity
      updated.quantityText = formatGroceryQuantity(amount.quantity)
      updated.unit = amount.unit?.nonEmptyGroceryText
    }
    updated.notes = try mergedNotes(survivor, sources: survivorSources, with: item, sources: itemSources, in: db)
    if updated != survivor {
      updated.dateModified = now
      try GroceryItem.upsert { updated }.execute(db)
    }
    for var source in itemSources {
      source.groceryItemID = survivor.id
      try GroceryItemSource.upsert { source }.execute(db)
    }
    try GroceryItem.find(item.id).delete().execute(db)
    return updated
  }

  @discardableResult
  public static func consolidate(listID: GroceryList.ID, in db: Database, now: Date) throws -> Int {
    _ = try requireList(listID, in: db)
    let fixes = try IngredientNameFixes.load(in: db)
    let items = try GroceryItem.where { $0.groceryListID.eq(listID) }
      .fetchAll(db)
      .filter { !$0.isPurchased }
      .sorted {
        if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
        return $0.id.uuidString < $1.id.uuidString
      }
    var survivors: [GroceryItem] = []
    var mergedCount = 0
    for item in items {
      if let survivorIndex = survivors.firstIndex(where: { canConsolidate($0, item, fixes: fixes) }) {
        survivors[survivorIndex] = try merge(item, into: survivors[survivorIndex], in: db, now: now)
        mergedCount += 1
      } else {
        survivors.append(item)
      }
    }
    return mergedCount
  }

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

    let updatedFixes = try IngredientNameFixes.load(in: db)
    let compatible = !item.isPurchased && !target.isPurchased
      && toName.nonEmptyGroceryText != nil
      && canConsolidate(item, target, fixes: updatedFixes)

    if compatible {
      _ = try merge(item, into: target, in: db, now: now)
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
