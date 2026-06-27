import Foundation

public enum GroceryPantryAssumptions {
  public static let defaultStaples: [String] = [
    "avocado oil",
    "black pepper",
    "canola oil",
    "cooking oil",
    "cooking spray",
    "extra virgin olive oil",
    "fine sea salt",
    "freshly ground pepper",
    "freshly ground black pepper",
    "ground black pepper",
    "ice",
    "ice cubes",
    "kosher salt",
    "neutral oil",
    "nonstick cooking spray",
    "olive oil",
    "pepper",
    "salt",
    "salt and pepper",
    "salt and freshly ground black pepper",
    "sea salt",
    "table salt",
    "vegetable oil",
    "water",
    "white pepper",
  ]

  public static func isPantryStaple(_ line: IngredientLine) -> Bool {
    isPantryStaple(line, pantryStaples: defaultStaples)
  }

  public static func isPantryStaple(_ line: IngredientLine, pantryStaples: [String]) -> Bool {
    let pantryStapleSet = Set(pantryStaples.map(normalizedPantryText))
    return pantryStapleTexts(for: line).contains { text in
      isPantryStapleText(text, pantryStaples: pantryStapleSet)
    }
  }

  private static func pantryStapleTexts(for line: IngredientLine) -> [String] {
    [
      line.item,
      line.originalText,
    ]
    .compactMap(\.self)
  }

  private static func isPantryStapleText(_ text: String, pantryStaples: Set<String>) -> Bool {
    let normalized = normalizedPantryText(text)
    guard !normalized.isEmpty else { return false }

    let baseText = normalizedBasePantryText(text)
    return pantryStaples.contains(normalized)
      || pantryStaples.contains(baseText)
      || normalized.hasPrefix("salt and pepper")
  }

  private static func normalizedBasePantryText(_ text: String) -> String {
    let separators = [",", "(", ";"]
    let base = separators.reduce(text) { partial, separator in
      partial.components(separatedBy: separator).first ?? partial
    }
    return normalizedPantryText(base)
  }

  private static func normalizedPantryText(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
