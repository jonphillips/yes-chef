import Foundation
import SwiftSoup

enum RecipeJSONLDExtractor {
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
    for image in imageStrings(node["image"]) { builder.addImage(image) }
    for ingredient in flatStrings(node["recipeIngredient"]) { builder.addIngredient(ingredient) }
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

  private static func cleanedJSON(_ raw: String) -> Data? {
    raw
      .replacingOccurrences(of: "[\u{201C}\u{201D}\u{2019}]", with: "", options: .regularExpression)
      .data(using: .utf8)
  }
}
