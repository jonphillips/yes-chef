import Foundation

public enum GroceryPantryAssumptions {
  public static let defaultStaples: [String] = CanonicalIngredient.defaultPantryStaples

  public static func isPantryStaple(_ line: IngredientLine) -> Bool {
    isPantryStaple(line, pantryStaples: defaultStaples)
  }

  public static func isPantryStaple(_ line: IngredientLine, pantryStaples: [String]) -> Bool {
    let pantryStapleSet = Set(pantryStaples.compactMap(CanonicalIngredient.canonicalName))
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
    guard let canonicalName = CanonicalIngredient.canonicalName(text) else { return false }
    return pantryStaples.contains(canonicalName)
      || canonicalName.hasPrefix("salt and pepper")
  }
}
