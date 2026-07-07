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
          canonicalName: CanonicalIngredient.canonicalName(parsed.item ?? text),
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

    if let quantity = mixedNumberValue(first) {
      return parsedQuantity(
        quantity: quantity,
        quantityText: first,
        remainingTokens: Array(tokens.dropFirst()),
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
    // Drop a leading range clause ("40 to 45 g …") before the unit is read, so the shared unit and
    // item survive rather than leaking "to 45 …" into the item.
    let tokens = strippingAlternateMeasurement(remainingTokens, consumingUnit: false)
    guard let firstRemainingToken = tokens.first else {
      return (quantity, quantityText, nil, nil, preparation)
    }

    if isUnit(firstRemainingToken) {
      // With the primary unit consumed, a dual-unit clause ("4 lb / 1.8 kg …") carries its own unit;
      // strip connector + number + unit so the item is the ingredient noun, not "/ 1.8 kg …".
      let itemTokens = strippingAlternateMeasurement(
        Array(tokens.dropFirst()),
        consumingUnit: true
      )
      return (
        quantity,
        quantityText,
        firstRemainingToken,
        nonEmpty(itemTokens.joined(separator: " ")),
        preparation
      )
    }

    return (
      quantity,
      quantityText,
      nil,
      nonEmpty(tokens.joined(separator: " ")),
      preparation
    )
  }

  /// Strip a leading *alternate measurement* clause from ingredient tokens — a connector
  /// (`/`, `to`, `or`, a dash) followed by a number, and (when `consumingUnit`) that number's own
  /// unit. Fixes two known-bad inputs that leak quantity fragments into the parsed item:
  /// dual-unit lines ("4 lb / 1.8 kg beef chuck roast" → "beef chuck roast") and range / metric-first
  /// lines ("28 to 32 g kosher salt" → unit "g", item "kosher salt"). Tightly scoped: it only fires
  /// when the tokens *begin* with a connector, so ordinary lines are untouched.
  private static func strippingAlternateMeasurement(
    _ tokens: [String],
    consumingUnit: Bool
  ) -> [String] {
    guard
      tokens.count >= 2,
      connectors.contains(tokens[0].lowercased()),
      isQuantityToken(tokens[1])
    else { return tokens }

    var dropCount = 2
    if consumingUnit, tokens.count > dropCount, isUnit(tokens[dropCount]) {
      dropCount += 1
    }
    return Array(tokens.dropFirst(dropCount))
  }

  private static func isQuantityToken(_ token: String) -> Bool {
    Double(token) != nil || fractionValue(token) != nil || mixedNumberValue(token) != nil
  }

  private static let connectors: Set<String> = ["/", "to", "or", "-", "–", "—"]

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
    if text.count == 1, let character = text.first, let value = vulgarFractions[character] {
      return value
    }

    let parts = text.split(separator: "/")
    guard
      parts.count == 2,
      let numerator = Double(parts[0]),
      let denominator = Double(parts[1]),
      denominator != 0
    else { return nil }
    return numerator / denominator
  }

  private static func mixedNumberValue(_ text: String) -> Double? {
    guard
      let fractionCharacter = text.last,
      let fraction = vulgarFractions[fractionCharacter]
    else { return nil }

    let wholeText = text.dropLast()
    guard !wholeText.isEmpty, let whole = Double(wholeText) else { return nil }
    return whole + fraction
  }

  private static func nonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static let vulgarFractions: [Character: Double] = [
    "¼": 1.0 / 4.0,
    "½": 1.0 / 2.0,
    "¾": 3.0 / 4.0,
    "⅓": 1.0 / 3.0,
    "⅔": 2.0 / 3.0,
    "⅛": 1.0 / 8.0,
    "⅜": 3.0 / 8.0,
    "⅝": 5.0 / 8.0,
    "⅞": 7.0 / 8.0,
    "⅕": 1.0 / 5.0,
    "⅖": 2.0 / 5.0,
    "⅗": 3.0 / 5.0,
    "⅘": 4.0 / 5.0,
    "⅙": 1.0 / 6.0,
    "⅚": 5.0 / 6.0,
  ]

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
