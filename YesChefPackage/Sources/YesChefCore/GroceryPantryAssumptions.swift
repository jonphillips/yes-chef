import Foundation

public enum GroceryPantryAssumptions {
  public static let defaultStaples: [String] = CanonicalIngredient.defaultPantryStaples

  public static func skippedStapleTitles(from pantryItems: [PantryItem]) -> [String] {
    pantryItems.filter { $0.policy == .unlimited }.map(\.title)
  }

  public static func isPantryStaple(_ line: IngredientLine) -> Bool {
    isPantryStaple(line, pantryStaples: defaultStaples)
  }

  public static func isPantryStaple(_ line: IngredientLine, pantryStaples: [String]) -> Bool {
    let pantryStapleSet = Set(pantryStaples.compactMap(CanonicalIngredient.canonicalName))
    if let canonicalName = line.canonicalIngredientName,
       isPantryStapleName(canonicalName, pantryStaples: pantryStapleSet) {
      return true
    }
    return pantryStapleTexts(for: line).contains { text in
      guard let canonicalName = CanonicalIngredient.canonicalName(text) else { return false }
      return isPantryStapleName(canonicalName, pantryStaples: pantryStapleSet)
    }
  }

  private static func pantryStapleTexts(for line: IngredientLine) -> [String] {
    [
      line.item,
      line.originalText,
    ]
    .compactMap(\.self)
  }

  private static func isPantryStapleName(_ canonicalName: String, pantryStaples: Set<String>) -> Bool {
    if pantryStaples.contains(canonicalName) || canonicalName.hasPrefix("salt and pepper") {
      return true
    }
    return CanonicalIngredient.compoundParts(canonicalName)?.allSatisfy(pantryStaples.contains) ?? false
  }
}

public extension IngredientLine {
  var canonicalIngredientName: String? {
    canonicalName ?? CanonicalIngredient.canonicalName(item ?? originalText)
  }
}

public extension GroceryItem {
  var canonicalIngredientName: String? {
    canonicalName ?? CanonicalIngredient.canonicalName(title)
  }
}
