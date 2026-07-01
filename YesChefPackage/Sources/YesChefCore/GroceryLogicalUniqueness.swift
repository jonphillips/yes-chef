import Foundation
import SQLiteData

extension GroceryRepository {
  static func reconciledDefaultList(
    in db: Database,
    lists: [GroceryList],
    now: Date
  ) throws -> GroceryList? {
    let defaultLists = lists.filter(\.isDefault)
    guard let defaultList = defaultLists.first else { return nil }

    for var list in defaultLists.dropFirst() {
      list.isDefault = false
      list.dateModified = now
      try GroceryList.upsert { list }.execute(db)
    }
    return defaultList
  }
}

extension PantryRepository {
  static func canonicalPantryItem(
    matching title: String,
    in db: Database
  ) throws -> PantryItem? {
    let key = title.groceryConsolidationKey
    let items = try PantryItem.fetchAll(db)
      .filter { $0.title.groceryConsolidationKey == key }
      .sorted(by: arePantryItemsInCanonicalOrder)
    guard var canonicalItem = items.first else { return nil }

    for duplicateItem in items.dropFirst() {
      if canonicalItem.notes == nil, let notes = duplicateItem.notes {
        canonicalItem.notes = notes
        canonicalItem.dateModified = max(canonicalItem.dateModified, duplicateItem.dateModified)
        try PantryItem.upsert { canonicalItem }.execute(db)
      }
      try PantryItem.find(duplicateItem.id).delete().execute(db)
    }
    return canonicalItem
  }
}

private func arePantryItemsInCanonicalOrder(_ lhs: PantryItem, _ rhs: PantryItem) -> Bool {
  if lhs.dateCreated != rhs.dateCreated {
    return lhs.dateCreated < rhs.dateCreated
  }
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  return lhs.id.uuidString < rhs.id.uuidString
}
