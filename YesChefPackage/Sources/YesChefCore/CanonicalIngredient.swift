import Foundation

public enum CanonicalIngredient {
  public static let defaultPantryStaples: [String] = [
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

  private static let aliases: [String: String] = [
    "anchovy filet": "anchovies",
    "anchovy filets": "anchovies",
    "anchovy fillet": "anchovies",
    "anchovy fillets": "anchovies",
    "anchovies": "anchovies",
    "green onion": "green onions",
    "green onions": "green onions",
    "scallion": "green onions",
    "scallions": "green onions",
    "tomato": "tomatoes",
    "tomatoes": "tomatoes",
  ]

  private static let leadingDescriptors: Set<String> = [
    "chopped",
    "crushed",
    "diced",
    "fresh",
    "freshly",
    "grated",
    "ground",
    "large",
    "medium",
    "minced",
    "small",
    "sliced",
  ]

  /// State/form words the **grocery** key deliberately keeps (`fresh` vs `frozen` are different SKUs)
  /// but the **compare matrix** ignores — the matrix aligns on the base ingredient and lets each cell
  /// carry the form. See `comparisonKey`. Cost-of-error is asymmetric: a false merge is expensive on
  /// the shop but cheap and self-evident in the matrix (the cells show `fresh` vs `frozen`).
  private static let comparisonFormModifiers: Set<String> = [
    "boneless",
    "bottled",
    "canned",
    "cooked",
    "cured",
    "dried",
    "fresh",
    "frozen",
    "jarred",
    "packed",
    "raw",
    "ripe",
    "roasted",
    "skinless",
    "smoked",
    "toasted",
    "whole",
  ]

  public static func canonicalName(_ text: String?) -> String? {
    guard let text else { return nil }
    let base = baseText(text)
    let normalized = normalize(base)
    guard !normalized.isEmpty else { return nil }

    if let alias = aliases[normalized] {
      return alias
    }

    let stripped = strippingLeadingDescriptors(from: normalized)
    if let alias = aliases[stripped] {
      return alias
    }

    let singular = lightlySingularized(stripped)
    if let alias = aliases[singular] {
      return alias
    }
    return singular
  }

  /// A **coarser** key than `canonicalName`, used only by the Workbench Compare matrix to align rows.
  /// A strict coarsening: same alias/singularize pipeline, but form/state words (`fresh`, `frozen`,
  /// `dried`, `canned`…) and prep/size descriptors are stripped from **any** position, so variants of
  /// one ingredient share a row and the difference shows in the cells. Never feed this to grocery
  /// consolidation or pantry matching — those must keep `fresh`/`frozen`/`dried` distinct.
  public static func comparisonKey(_ text: String?) -> String? {
    guard let text else { return nil }
    let base = baseText(text)
    let normalized = normalize(base)
    guard !normalized.isEmpty else { return nil }

    if let alias = aliases[normalized] {
      return alias
    }

    let stripped = strippingModifiers(from: normalized)
    if !stripped.isEmpty, let alias = aliases[stripped] {
      return alias
    }

    let candidate = stripped.isEmpty ? normalized : stripped
    let singular = lightlySingularized(candidate)
    if let alias = aliases[singular] {
      return alias
    }
    return singular
  }

  static func displayName(_ text: String) -> String {
    let original = text.nonEmptyGroceryText ?? text
    let normalized = normalize(baseText(text))
    if let alias = aliases[normalized] {
      return alias
    }

    let stripped = strippingLeadingDescriptors(from: normalized)
    if let alias = aliases[stripped] {
      return alias
    }

    let singular = lightlySingularized(stripped)
    if let alias = aliases[singular] {
      return alias
    }
    return original
  }

  static func canonicalText(_ text: String?) -> String? {
    guard let text else { return nil }
    let normalized = normalize(text)
    return normalized.isEmpty ? nil : normalized
  }

  private static func baseText(_ text: String) -> String {
    let separators = [",", "(", ";"]
    return separators.reduce(text) { partial, separator in
      partial.components(separatedBy: separator).first ?? partial
    }
  }

  private static func normalize(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func strippingLeadingDescriptors(from text: String) -> String {
    var words = text.split(separator: " ").map(String.init)
    while let first = words.first, leadingDescriptors.contains(first) {
      words.removeFirst()
    }
    return words.joined(separator: " ")
  }

  /// Drop prep/size descriptors and form/state words from **any** position — the compare key's extra
  /// coarsening step over the grocery key's leading-only strip.
  private static func strippingModifiers(from text: String) -> String {
    let removable = leadingDescriptors.union(comparisonFormModifiers)
    let words = text.split(separator: " ").map(String.init).filter { !removable.contains($0) }
    return words.joined(separator: " ")
  }

  /// Words the generic `-ies → y` / `-s` rules singularize wrong. Keyed by the plural (as it appears
  /// after `normalize`), mapped to the canonical singular. Targeted exception, not a rule rewrite:
  /// only these listed forms divert; `berries → berry`, `tomatoes → tomato`, etc. stay on the generic
  /// path. Every chile-pepper spelling converges on `chile` so the Compare matrix aligns them on one
  /// row (the naive rule turned `chilies → chily`, which never matched `chile` from `chiles`).
  private static let irregularSingulars: [String: String] = [
    "chile": "chile",
    "chiles": "chile",
    "chilies": "chile",
    "chilis": "chile",
    "chilli": "chile",
    "chillies": "chile",
    "chillis": "chile",
  ]

  private static func lightlySingularized(_ text: String) -> String {
    let words = text.split(separator: " ").map(String.init)
    guard var last = words.last else { return text }

    if let irregular = irregularSingulars[last] {
      last = irregular
    } else if last.hasSuffix("ies"), last.count > 3 {
      last = String(last.dropLast(3)) + "y"
    } else if last.hasSuffix("oes"), last.count > 3 {
      last = String(last.dropLast(2))
    } else if last.hasSuffix("s"),
              !last.hasSuffix("ss"),
              !last.hasSuffix("us"),
              last.count > 3 {
      last = String(last.dropLast())
    }

    return (words.dropLast() + [last]).joined(separator: " ")
  }
}
