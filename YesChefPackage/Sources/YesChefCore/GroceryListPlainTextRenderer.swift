import Foundation

public enum GroceryListPlainTextRenderer {
  public static func render(list: GroceryList, rows: [GroceryItemRowData]) -> String {
    var sections: [(title: String, rows: [GroceryItemRowData])] = [
      ("To Buy", rows.filter { !$0.item.isPurchased }),
      ("Purchased", rows.filter(\.item.isPurchased)),
    ]
    sections.removeAll { $0.rows.isEmpty }

    var lines = [list.title]
    if sections.isEmpty {
      lines.append("")
      lines.append("No grocery items.")
    } else {
      for section in sections {
        lines.append("")
        lines.append(section.title)
        lines.append(contentsOf: section.rows.map { itemLine(for: $0.item) })
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func itemLine(for item: GroceryItem) -> String {
    let quantity = [
      item.quantityText?.nonEmptyGroceryText,
      item.unit?.nonEmptyGroceryText,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .nonEmptyGroceryText

    let title = [
      quantity,
      item.title.nonEmptyGroceryText ?? item.title,
    ]
    .compactMap { $0 }
    .joined(separator: " ")

    let details = [
      item.aisle?.nonEmptyGroceryText,
      item.notes?.nonEmptyGroceryText,
    ]
    .compactMap { $0 }

    if details.isEmpty {
      return "- \(title)"
    }
    return "- \(title) (\(details.joined(separator: "; ")))"
  }
}
