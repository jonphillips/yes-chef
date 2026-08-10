import Foundation
import SwiftSoup

enum RecipeJSONLDExtractor {
  /// Mine a raw schema.org `Recipe` JSON-LD block that did not arrive inside an HTML `<script>` —
  /// the ADR-0042 workbench-draft hand-off return. Reuses the same parse + salvage + node-walk as the
  /// document path, so a curly-quote-mangled paste is normalized identically (see `cleanedJSON`).
  static func extract(fromJSONLD raw: String, into builder: inout RecipeParseBuilder) {
    guard let top = jsonObject(from: raw) else { return }
    for node in recipeNodes(in: top) {
      mineIfComplete(node, into: &builder)
    }
  }

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    let scripts = (try? document.select("script[type=application/ld+json]").array()) ?? []
    for script in scripts {
      guard let top = jsonObject(from: script.data()) else { continue }
      for node in recipeNodes(in: top) {
        mineIfComplete(node, into: &builder)
      }
    }

    let metas = (try? document.select("meta[name]").array()) ?? []
    for meta in metas {
      guard ((try? meta.attr("name")) ?? "").lowercased() == "application/ld+json",
        let content = try? meta.attr("content"),
        !content.isEmpty,
        let top = jsonObject(from: content)
      else { continue }
      for node in recipeNodes(in: top) {
        mineIfComplete(node, into: &builder)
      }
    }
  }

  /// Parse the raw JSON-LD **first**, so well-formed content keeps its apostrophes and
  /// curly quotes (a title like "Grandma's Soup" must survive intact). Only on a strict
  /// parse failure do we attempt the smart-quote salvage — for pages that misuse curly
  /// quotes as JSON delimiters — accepting that lossy fallback rather than imposing it.
  private static func jsonObject(from raw: String) -> Any? {
    if let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) {
      return object
    }
    guard let salvaged = cleanedJSON(raw),
      let object = try? JSONSerialization.jsonObject(with: salvaged) else { return nil }
    return object
  }

  private static func recipeNodes(in value: Any) -> [[String: Any]] {
    switch value {
    case let dict as [String: Any]:
      var found: [[String: Any]] = []
      if isRecipeNode(dict) { found.append(dict) }
      for (_, child) in dict {
        found.append(contentsOf: recipeNodes(in: child))
      }
      return found
    case let array as [Any]:
      return array.flatMap(recipeNodes(in:))
    default:
      return []
    }
  }

  private static func isRecipeNode(_ dict: [String: Any]) -> Bool {
    typeStrings(dict["@type"]).contains { RecipeSchemaOrg.recipeTypes.contains($0) }
  }

  private static func mineIfComplete(_ node: [String: Any], into builder: inout RecipeParseBuilder) {
    if isTruncated(node) {
      builder.markTruncatedStructuredData()
      return
    }

    for type in typeStrings(node["@type"]) { builder.addSchemaType(type) }
    for (property, attribute) in RecipeSchemaOrg.scalarProperties {
      if property == "aggregateRating" {
        builder.votes.add(attribute, ratingString(node[property]), priority: RecipeAttributeVotes.jsonLDPriority)
      } else {
        builder.votes.add(attribute, firstString(node[property]), priority: RecipeAttributeVotes.jsonLDPriority)
      }
    }
    for category in flatStrings(node["recipeCategory"]) { builder.addCategory(category) }
    for cuisine in flatStrings(node["recipeCuisine"]) { builder.addCuisine(cuisine) }
    for keyword in flatStrings(node["keywords"]) { builder.addTag(keyword) }
    for image in imageStrings(node["image"]) { builder.addImage(image) }
    // v2's namespaced sections are authoritative. Also recover the early dogfood shape that put
    // HowToSection objects in `recipeIngredient`: it is not schema.org-correct, but losing every
    // ingredient line is worse than accepting that recoverable malformed return.
    let groupedIngredients = ingredientSections(node["yesChef:ingredientSections"])
    let legacyGroupedIngredients = ingredientSections(node["recipeIngredient"])
    if groupedIngredients.isEmpty {
      if legacyGroupedIngredients.isEmpty {
        for ingredient in flatStrings(node["recipeIngredient"]) { builder.addIngredient(ingredient) }
      } else {
        for section in legacyGroupedIngredients {
          builder.addIngredientSection(name: section.name, lines: section.lines)
        }
      }
    } else {
      for section in groupedIngredients {
        builder.addIngredientSection(name: section.name, lines: section.lines)
      }
    }
    mineInstructions(node["recipeInstructions"], into: &builder)
  }

  private static func isTruncated(_ node: [String: Any]) -> Bool {
    let recipeText = flatStrings(node["recipeIngredient"]) + instructionStrings(node["recipeInstructions"])
    return recipeText.contains(where: isTruncationSentinel)
  }

  private static func mineInstructions(_ value: Any?, into builder: inout RecipeParseBuilder) {
    switch value {
    case let string as String:
      builder.addInstruction(string)
    case let array as [Any]:
      for item in array { mineInstructions(item, into: &builder) }
    case let dict as [String: Any]:
      let types = typeStrings(dict["@type"])
      if types.contains("HowToSection") {
        let name = firstString(dict["name"])
        let steps = instructionStrings(dict["itemListElement"] ?? dict["steps"])
        builder.addInstructionSection(name: name, steps: steps)
      } else if let text = firstString(dict["text"] ?? dict["name"]) {
        builder.addInstruction(text)
      }
    default:
      return
    }
  }

  /// `recipeIngredient` has no schema.org equivalent of `HowToSection`: its values are ingredient
  /// entries, not named groups. The narrow v2 extension preserves Yes Chef's canonical grouping while
  /// the parallel standard `recipeIngredient` remains an interoperable flat fallback.
  private static func ingredientSections(_ value: Any?) -> [(name: String?, lines: [String])] {
    switch value {
    case let array as [Any]:
      return array.flatMap { ingredientSections($0) }
    case let dict as [String: Any]:
      let lines = flatStrings(dict["recipeIngredient"] ?? dict["itemListElement"])
      guard !lines.isEmpty else { return [] }
      return [(firstString(dict["name"]), lines)]
    default:
      return []
    }
  }

  private static func instructionStrings(_ value: Any?) -> [String] {
    switch value {
    case let string as String:
      return [string]
    case let array as [Any]:
      return array.flatMap(instructionStrings)
    case let dict as [String: Any]:
      return flatStrings(dict["text"] ?? dict["name"] ?? dict["itemListElement"])
    default:
      return []
    }
  }

  private static func typeStrings(_ value: Any?) -> [String] {
    flatStrings(value).map { $0.split(whereSeparator: { $0 == "/" || $0 == "#" }).last.map(String.init) ?? $0 }
  }

  private static func flatStrings(_ value: Any?) -> [String] {
    switch value {
    case let string as String:
      return [string]
    case let number as NSNumber:
      return [number.stringValue]
    case let array as [Any]:
      return array.flatMap { flatStrings($0) }
    case let dict as [String: Any]:
      if let resolved = firstString(dict["url"] ?? dict["@id"] ?? dict["name"]) {
        return [resolved]
      }
      return []
    default:
      return []
    }
  }

  private static func firstString(_ value: Any?) -> String? {
    flatStrings(value).first
  }

  private static func imageStrings(_ value: Any?) -> [String] {
    switch value {
    case let string as String:
      return [string]
    case let array as [Any]:
      return array.flatMap { imageStrings($0) }
    case let dict as [String: Any]:
      return flatStrings(dict["url"] ?? dict["contentUrl"] ?? dict["@id"])
    default:
      return []
    }
  }

  private static func ratingString(_ value: Any?) -> String? {
    switch value {
    case let dict as [String: Any]:
      return firstString(dict["ratingValue"])
    default:
      return firstString(value)
    }
  }

  private static func isTruncationSentinel(_ text: String) -> Bool {
    let normalized = text
      .replacingOccurrences(of: "\u{2026}", with: "...")
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .lowercased()
    return normalized.contains("sign up for full access")
      || normalized.hasPrefix("... and more")
  }

  /// Salvage JSON whose delimiters were replaced with typographic quotes — the signature of a
  /// copy/paste autoformatter (ADR-0042 Amd 2, the workbench-draft hand-run). We **replace** curly
  /// doubles with straight `"` (not delete them: deleting leaves keys/values unquoted, which never
  /// parses) and curly singles with a straight apostrophe, so `"Cook's Illustrated"` survives intact
  /// rather than becoming `"Cooks Illustrated"`. Only reached after a strict parse fails, so
  /// well-formed content keeps its real apostrophes and curly quotes untouched.
  private static func cleanedJSON(_ raw: String) -> Data? {
    raw
      .replacingOccurrences(of: "\u{201C}", with: "\"")
      .replacingOccurrences(of: "\u{201D}", with: "\"")
      .replacingOccurrences(of: "\u{2018}", with: "'")
      .replacingOccurrences(of: "\u{2019}", with: "'")
      .data(using: .utf8)
  }
}
