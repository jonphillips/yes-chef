import Foundation

public enum GroceryPantryAssumptions {
  public static let defaultStaples: [String] = CanonicalIngredient.defaultPantryStaples

  public static func skippedStapleTitles(from pantryItems: [PantryItem]) -> [String] {
    pantryItems.filter { $0.policy == .unlimited }.map(\.title)
  }

  public static func isPantryStaple(_ line: IngredientLine, fixes: IngredientNameFixes = .empty) -> Bool {
    isPantryStaple(line, pantryStaples: defaultStaples, fixes: fixes)
  }

  public static func isPantryStaple(
    _ line: IngredientLine,
    pantryStaples: [String],
    fixes: IngredientNameFixes = .empty
  ) -> Bool {
    let pantryStapleSet = Set(pantryStaples.compactMap(fixes.canonicalName))
    if let canonicalName = line.canonicalIngredientName,
       isPantryStapleName(
         fixes.canonicalName(canonicalName) ?? canonicalName,
         pantryStaples: pantryStapleSet,
         fixes: fixes
       ) {
      return true
    }
    return pantryStapleTexts(for: line).contains { text in
      guard let canonicalName = fixes.canonicalName(text) else { return false }
      return isPantryStapleName(canonicalName, pantryStaples: pantryStapleSet, fixes: fixes)
    }
  }

  private static func pantryStapleTexts(for line: IngredientLine) -> [String] {
    [
      line.item,
      line.originalText,
    ]
    .compactMap(\.self)
  }

  private static func isPantryStapleName(
    _ canonicalName: String,
    pantryStaples: Set<String>,
    fixes: IngredientNameFixes
  ) -> Bool {
    if pantryStaples.contains(canonicalName) || canonicalName.hasPrefix("salt and pepper") {
      return true
    }
    return CanonicalIngredient.compoundParts(canonicalName, fixes: fixes)?.allSatisfy(pantryStaples.contains) ?? false
  }
}

public extension IngredientLine {
  var canonicalIngredientName: String? {
    canonicalName ?? CanonicalIngredient.baseName(item ?? originalText)
  }
}

public extension GroceryItem {
  var canonicalIngredientName: String? {
    canonicalName ?? CanonicalIngredient.baseName(title)
  }
}
