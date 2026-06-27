import Foundation

public enum IngredientParser {
  public static func lines(
    from text: String,
    recipeID: Recipe.ID,
    sectionID: IngredientSection.ID,
    uuid: () -> UUID
  ) -> [IngredientLine] {
    text
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .enumerated()
      .map { index, text in
        let parsed = parse(text)
        return IngredientLine(
          id: uuid(),
          recipeID: recipeID,
          sectionID: sectionID,
          originalText: text,
          quantity: parsed.quantity,
          quantityText: parsed.quantityText,
          unit: parsed.unit,
          item: parsed.item,
          preparation: parsed.preparation,
          isOptional: text.localizedCaseInsensitiveContains("optional"),
          doNotShop: Self.doNotShop(text),
          isHeader: text.hasSuffix(":"),
          sortOrder: index,
          confidence: parsed.quantity == nil ? .low : .medium
        )
      }
  }

  public static func parse(
    _ text: String
  ) -> (quantity: Double?, quantityText: String?, unit: String?, item: String?, preparation: String?) {
    let parts = ingredientParts(text)
    let tokens = parts.ingredient.split(separator: " ").map(String.init)
    guard let first = tokens.first else { return (nil, nil, nil, nil, nil) }

    if tokens.count >= 2, let whole = Double(first), let fraction = fractionValue(tokens[1]) {
      let quantityText = "\(first) \(tokens[1])"
      return parsedQuantity(
        quantity: whole + fraction,
        quantityText: quantityText,
        remainingTokens: Array(tokens.dropFirst(2)),
        preparation: parts.preparation
      )
    }

    if let quantity = Double(first) ?? fractionValue(first) {
      return parsedQuantity(
        quantity: quantity,
        quantityText: first,
        remainingTokens: Array(tokens.dropFirst()),
        preparation: parts.preparation
      )
    }

    return (nil, nil, nil, nonEmpty(parts.ingredient), parts.preparation)
  }

  private static func parsedQuantity(
    quantity: Double,
    quantityText: String,
    remainingTokens: [String],
    preparation: String?
  ) -> (quantity: Double?, quantityText: String?, unit: String?, item: String?, preparation: String?) {
    guard let firstRemainingToken = remainingTokens.first else {
      return (quantity, quantityText, nil, nil, preparation)
    }

    if isUnit(firstRemainingToken) {
      return (
        quantity,
        quantityText,
        firstRemainingToken,
        nonEmpty(remainingTokens.dropFirst().joined(separator: " ")),
        preparation
      )
    }

    return (
      quantity,
      quantityText,
      nil,
      nonEmpty(remainingTokens.joined(separator: " ")),
      preparation
    )
  }

  private static func ingredientParts(_ text: String) -> (ingredient: String, preparation: String?) {
    let separators = [",", ";", "("]
    let separatorIndex = separators
      .compactMap { separator in text.firstIndex(of: Character(separator)) }
      .min()
    guard let separatorIndex else {
      return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    let ingredient = String(text[..<separatorIndex])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let preparation = String(text[text.index(after: separatorIndex)...])
      .trimmingCharacters(in: CharacterSet(charactersIn: ")").union(.whitespacesAndNewlines))
    return (ingredient, nonEmpty(preparation))
  }

  private static func isUnit(_ token: String) -> Bool {
    units.contains(normalizedUnit(token))
  }

  private static func normalizedUnit(_ token: String) -> String {
    token
      .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func fractionValue(_ text: String) -> Double? {
    let parts = text.split(separator: "/")
    guard
      parts.count == 2,
      let numerator = Double(parts[0]),
      let denominator = Double(parts[1]),
      denominator != 0
    else { return nil }
    return numerator / denominator
  }

  private static func nonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static let units: Set<String> = [
    "bag",
    "bags",
    "bottle",
    "bottles",
    "box",
    "boxes",
    "bunch",
    "bunches",
    "can",
    "cans",
    "clove",
    "cloves",
    "cup",
    "cups",
    "dash",
    "dashes",
    "ear",
    "ears",
    "g",
    "gallon",
    "gallons",
    "gram",
    "grams",
    "head",
    "heads",
    "jar",
    "jars",
    "kg",
    "kilogram",
    "kilograms",
    "l",
    "lb",
    "lbs",
    "liter",
    "liters",
    "milliliter",
    "milliliters",
    "ml",
    "ounce",
    "ounces",
    "oz",
    "package",
    "packages",
    "packet",
    "packets",
    "pinch",
    "pinches",
    "pint",
    "pints",
    "pkg",
    "pound",
    "pounds",
    "quart",
    "quarts",
    "slice",
    "slices",
    "sprig",
    "sprigs",
    "stalk",
    "stalks",
    "stick",
    "sticks",
    "tablespoon",
    "tablespoons",
    "tbsp",
    "teaspoon",
    "teaspoons",
    "tsp",
  ]

  private static func doNotShop(_ text: String) -> Bool {
    let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lowercased == "water"
      || lowercased == "kosher salt"
      || lowercased == "salt"
      || lowercased == "freshly ground black pepper"
      || lowercased == "black pepper"
  }
}
