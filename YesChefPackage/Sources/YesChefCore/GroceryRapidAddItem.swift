import Foundation

/// The lossless grocery-item fields parsed from one rapid-add line.
public struct GroceryRapidAddItem: Equatable, Sendable {
  public var title: String
  public var quantityText: String?
  public var unit: String?
  public var notes: String?

  public init(
    title: String,
    quantityText: String? = nil,
    unit: String? = nil,
    notes: String? = nil
  ) {
    self.title = title
    self.quantityText = quantityText
    self.unit = unit
    self.notes = notes
  }

  public init?(line: String) {
    let parsed = IngredientParser.parse(line)
    guard let title = parsed.item?.nonEmptyGroceryText else { return nil }

    self.init(
      title: title,
      quantityText: parsed.quantityText,
      unit: parsed.unit,
      notes: [parsed.preparation, parsed.comment]
      .compactMap { $0?.nonEmptyGroceryText }
      .joined(separator: "; ")
      .nonEmptyGroceryText
    )
  }
}
