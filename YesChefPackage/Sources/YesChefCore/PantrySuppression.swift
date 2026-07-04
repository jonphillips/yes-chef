import Foundation

public enum PantrySuppression {
  public struct Evaluation: Equatable, Sendable {
    public var shown: [GroceryItemRowData]
    public var assumedInPantry: [GroceryItemRowData]
    public var needsReview: [GroceryItemRowData]

    public init(
      shown: [GroceryItemRowData] = [],
      assumedInPantry: [GroceryItemRowData] = [],
      needsReview: [GroceryItemRowData] = []
    ) {
      self.shown = shown
      self.assumedInPantry = assumedInPantry
      self.needsReview = needsReview
    }

    public var shoppingRows: [GroceryItemRowData] {
      (needsReview + shown).sorted(by: arePantrySuppressionRowsInDisplayOrder)
    }
  }

  public static func evaluate(
    list: [GroceryItemRowData],
    policies: [PantryItem]
  ) -> Evaluation {
    let policiesByCanonicalName: [String: PantryItem] = Dictionary(
      grouping: policies.compactMap { item -> (String, PantryItem)? in
        guard let canonicalName = CanonicalIngredient.canonicalName(item.title) else { return nil }
        return (canonicalName, item)
      },
      by: \.0
    )
    .compactMapValues { values in
      values.map(\.1).sorted(by: arePantryItemsInSuppressionOrder).first
    }

    var evaluation = Evaluation()
    for row in list {
      guard let canonicalName = row.item.canonicalIngredientName,
            let pantryItem = policiesByCanonicalName[canonicalName]
      else {
        evaluation.shown.append(row)
        continue
      }

      switch pantryItem.policy {
      case .unlimited:
        evaluation.assumedInPantry.append(row)

      case .alwaysConfirm:
        evaluation.shown.append(row)

      case let .threshold(quantity, unit):
        let comparison = row.item.measureForPantrySuppression?
          .compare(to: Measure(quantity: quantity, unit: unit)) ?? .incomparable
        switch comparison {
        case .over, .incomparable:
          evaluation.needsReview.append(row)
        case .underOrEqual:
          evaluation.assumedInPantry.append(row)
        }
      }
    }
    return evaluation
  }

  public static func addBack(
    itemIDs: Set<GroceryItem.ID>,
    to evaluation: Evaluation
  ) -> Evaluation {
    var evaluation = evaluation
    var addBackRows: [GroceryItemRowData] = []
    evaluation.assumedInPantry.removeAll { row in
      guard itemIDs.contains(row.id) else { return false }
      addBackRows.append(row)
      return true
    }
    evaluation.shown = (evaluation.shown + addBackRows)
      .sorted(by: arePantrySuppressionRowsInDisplayOrder)
    return evaluation
  }

  public static func addBack(
    itemID: GroceryItem.ID,
    to evaluation: Evaluation
  ) -> Evaluation {
    addBack(itemIDs: [itemID], to: evaluation)
  }
}

private func arePantryItemsInSuppressionOrder(_ lhs: PantryItem, _ rhs: PantryItem) -> Bool {
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func arePantrySuppressionRowsInDisplayOrder(
  _ lhs: GroceryItemRowData,
  _ rhs: GroceryItemRowData
) -> Bool {
  if lhs.item.groceryListID != rhs.item.groceryListID {
    return lhs.item.groceryListID.uuidString < rhs.item.groceryListID.uuidString
  }
  if lhs.item.isPurchased != rhs.item.isPurchased {
    return !lhs.item.isPurchased
  }
  if lhs.item.sortOrder != rhs.item.sortOrder {
    return lhs.item.sortOrder < rhs.item.sortOrder
  }
  let titleComparison = lhs.item.title.localizedStandardCompare(rhs.item.title)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.item.id.uuidString < rhs.item.id.uuidString
}

private extension GroceryItem {
  var measureForPantrySuppression: Measure? {
    quantity.map { Measure(quantity: $0, unit: unit) }
  }
}
