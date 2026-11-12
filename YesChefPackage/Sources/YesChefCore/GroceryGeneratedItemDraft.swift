struct GroceryGeneratedItemDraft {
  var title: String
  var canonicalName: String?
  var fixedName: String?
  var quantity: Double?
  var quantityText: String?
  var unit: String?
  var aisle: String?
  var notes: String?

  init(line: IngredientLine, scale: Double = 1.0, fixes: IngredientNameFixes = .empty) {
    self.title = fixes.displayName(line.groceryItemTitle)
    self.canonicalName = line.canonicalIngredientName ?? CanonicalIngredient.baseName(line.groceryItemTitle)
    self.fixedName = fixes.canonicalName(self.canonicalName)
    if let range = QuantityParser.leadingIngredientRange(in: line.originalText),
       let upperBound = range.upperBound {
      let scaledQuantity = upperBound * scale
      self.quantity = scaledQuantity
      self.quantityText = formatGroceryQuantity(scaledQuantity)
    } else if let quantity = line.quantity {
      let scaledQuantity = quantity * scale
      self.quantity = scaledQuantity
      self.quantityText = scale == 1 ? line.groceryQuantityText : formatGroceryQuantity(scaledQuantity)
    } else {
      self.quantity = nil
      self.quantityText = line.groceryQuantityText
    }
    self.unit = line.unit?.nonEmptyGroceryText
    self.aisle = GroceryStoreArea.seed(for: fixedName)?.title
    self.notes = line.groceryNotes
  }

  var measure: Measure? {
    quantity.map { Measure(quantity: $0, unit: unit) }
  }
}

extension IngredientLine {
  var groceryItemTitle: String {
    CanonicalIngredient.displayName(item?.nonEmptyGroceryText ?? originalText)
  }

  var groceryQuantityText: String? {
    quantityText?.nonEmptyGroceryText ?? quantity.map(formatGroceryQuantity)
  }

  var groceryNotes: String? {
    [preparation, comment]
      .compactMap { $0?.nonEmptyGroceryText }
      .joined(separator: "; ")
      .nonEmptyGroceryText
  }
}
