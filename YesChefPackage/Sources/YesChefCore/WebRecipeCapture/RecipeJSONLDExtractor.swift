import Foundation
import SwiftSoup

enum RecipeJSONLDExtractor {
  /// Mine a raw schema.org `Recipe` JSON-LD block that did not arrive inside an HTML `<script>` —
  /// the ADR-0042 workbench-draft hand-off return. Reuses the same parse + salvage + node-walk as the
  /// document path, so a curly-quote-mangled paste is normalized identically (see `cleanedJSON`).
  static func extract(fromJSONLD raw: String, into builder: inout RecipeParseBuilder) {
    guard let top = jsonObject(from: raw) else { return }
    minePrimaryCandidate(in: [top], into: &builder)
  }

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    let elements = (try? document.select("script[type=application/ld+json], meta[name]").array()) ?? []
    let documents = elements.compactMap { element -> Any? in
      if ((try? element.attr("name")) ?? "").lowercased() == "application/ld+json" {
        guard let content = try? element.attr("content"), !content.isEmpty else { return nil }
        return jsonObject(from: content)
      }
      return jsonObject(from: element.data())
    }
    minePrimaryCandidate(in: documents, into: &builder)
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

  /// Fidelity: lossless-or-loud. A page can contain more than one complete Recipe node, but this
  /// single-recipe builder mines only a deterministic primary and records the ambiguity for review.
  private static func minePrimaryCandidate(in documents: [Any], into builder: inout RecipeParseBuilder) {
    let candidates = documents.enumerated().flatMap { documentOrder, document in
      recipeCandidates(in: document, documentOrder: documentOrder)
    }
    guard let primary = candidates.min(by: primaryCandidatePrecedes) else { return }
    if candidates.count > 1 { builder.markMultipleRecipeCandidates() }
    mineIfComplete(primary.node, into: &builder)
  }

  /// A primary is a root Recipe, an `@graph` member, or a `mainEntity` before a Recipe nested in
  /// another field. Ties use document then `@graph` traversal order, never dictionary iteration.
  private static func primaryCandidatePrecedes(_ lhs: RecipeCandidate, _ rhs: RecipeCandidate) -> Bool {
    if lhs.isPreferredLocation != rhs.isPreferredLocation {
      return lhs.isPreferredLocation
    }
    if lhs.documentOrder != rhs.documentOrder { return lhs.documentOrder < rhs.documentOrder }
    return lhs.nodeOrder < rhs.nodeOrder
  }

  private static func recipeCandidates(in value: Any, documentOrder: Int) -> [RecipeCandidate] {
    var candidates: [RecipeCandidate] = []
    var nodeOrder = 0
    collectRecipeCandidates(
      in: value,
      documentOrder: documentOrder,
      location: .topLevel,
      nodeOrder: &nodeOrder,
      into: &candidates
    )
    return candidates
  }

  private static func collectRecipeCandidates(
    in value: Any,
    documentOrder: Int,
    location: RecipeCandidateLocation,
    nodeOrder: inout Int,
    into candidates: inout [RecipeCandidate]
  ) {
    switch value {
    case let dict as [String: Any]:
      if isRecipeNode(dict), isMateriallyComplete(dict) {
        candidates.append(
          RecipeCandidate(
            node: dict,
            isPreferredLocation: location.isPreferred,
            documentOrder: documentOrder,
            nodeOrder: nodeOrder
          )
        )
        nodeOrder += 1
      }
      for key in dict.keys.sorted() {
        guard let child = dict[key] else { continue }
        let childLocation: RecipeCandidateLocation
        switch key {
        case "@graph": childLocation = .topLevel
        case "mainEntity": childLocation = .mainEntity
        default: childLocation = .nested
        }
        collectRecipeCandidates(
          in: child,
          documentOrder: documentOrder,
          location: childLocation,
          nodeOrder: &nodeOrder,
          into: &candidates
        )
      }
    case let array as [Any]:
      for child in array {
        collectRecipeCandidates(
          in: child,
          documentOrder: documentOrder,
          location: location,
          nodeOrder: &nodeOrder,
          into: &candidates
        )
      }
    default:
      return
    }
  }

  private static func isRecipeNode(_ dict: [String: Any]) -> Bool {
    typeStrings(dict["@type"]).contains { RecipeSchemaOrg.recipeTypes.contains($0) }
  }

  private static func isMateriallyComplete(_ node: [String: Any]) -> Bool {
    let hasIngredients = !flatStrings(node["recipeIngredient"]).isEmpty
      || !ingredientSections(node["yesChef:ingredientSections"]).isEmpty
    return hasIngredients && !instructionSteps(node["recipeInstructions"]).isEmpty
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
        mineInstructionSection(dict, parentName: nil, into: &builder)
      } else if let text = firstString(dict["text"] ?? dict["name"]) {
        builder.addInstruction(text)
      }
    default:
      return
    }
  }

  private static func mineInstructionSection(
    _ section: [String: Any],
    parentName: String?,
    into builder: inout RecipeParseBuilder
  ) {
    let name = composedSectionName(parent: parentName, child: firstString(section["name"]))
    let items = section["itemListElement"] ?? section["steps"]
    var directSteps: [String] = []
    var nestedSections: [[String: Any]] = []
    collectInstructionItems(items, directSteps: &directSteps, nestedSections: &nestedSections)
    builder.addInstructionSection(name: name, steps: directSteps)

    for nestedSection in nestedSections {
      builder.markNestedInstructionSectionsFlattened()
      mineInstructionSection(nestedSection, parentName: name, into: &builder)
    }
  }

  private static func collectInstructionItems(
    _ value: Any?,
    directSteps: inout [String],
    nestedSections: inout [[String: Any]]
  ) {
    switch value {
    case let string as String:
      directSteps.append(string)
    case let array as [Any]:
      for item in array {
        collectInstructionItems(item, directSteps: &directSteps, nestedSections: &nestedSections)
      }
    case let dict as [String: Any]:
      if typeStrings(dict["@type"]).contains("HowToSection") {
        nestedSections.append(dict)
      } else if let text = firstString(dict["text"] ?? dict["name"]) {
        directSteps.append(text)
      } else {
        collectInstructionItems(dict["itemListElement"] ?? dict["steps"], directSteps: &directSteps, nestedSections: &nestedSections)
      }
    default:
      return
    }
  }

  private static func instructionSteps(_ value: Any?) -> [String] {
    var steps: [String] = []
    var nestedSections: [[String: Any]] = []
    collectInstructionItems(value, directSteps: &steps, nestedSections: &nestedSections)
    for section in nestedSections {
      steps.append(contentsOf: instructionSteps(section["itemListElement"] ?? section["steps"]))
    }
    return steps
  }

  private static func composedSectionName(parent: String?, child: String?) -> String? {
    let parent = parent?.trimmingCharacters(in: .whitespacesAndNewlines)
    let child = child?.trimmingCharacters(in: .whitespacesAndNewlines)
    return switch (parent?.isEmpty == false ? parent : nil, child?.isEmpty == false ? child : nil) {
    case let (parent?, child?): "\(parent) — \(child)"
    case let (parent?, nil): parent
    case let (nil, child?): child
    case (nil, nil): nil
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

  private struct RecipeCandidate {
    let node: [String: Any]
    let isPreferredLocation: Bool
    let documentOrder: Int
    let nodeOrder: Int
  }

  private enum RecipeCandidateLocation {
    case topLevel
    case mainEntity
    case nested

    var isPreferred: Bool {
      switch self {
      case .topLevel, .mainEntity: true
      case .nested: false
      }
    }
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
