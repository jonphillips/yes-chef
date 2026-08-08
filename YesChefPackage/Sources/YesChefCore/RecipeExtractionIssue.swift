import Foundation

/// An actionable, deterministic review cue produced after recipe extraction (ADR-0053 D6). It records
/// a detectable mismatch or omission without asking the model to assess its own confidence.
public struct RecipeExtractionIssue: Equatable, Identifiable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case missingTitle
    case emptyIngredients
    case emptyInstructions
    case missingIngredientQuantity
    case duplicateIngredient
    case ingredientNotReferenced
    case referencedIngredientNotListed
    case unparseablePrepTime
    case unparseableCookTime
    case unparseableTotalTime
    case unattributedSource
  }

  public var kind: Kind
  public var detail: String?
  public var sourceID: CreateRecipeSourceItem.ID?

  public init(kind: Kind, detail: String? = nil, sourceID: CreateRecipeSourceItem.ID? = nil) {
    self.kind = kind
    self.detail = detail
    self.sourceID = sourceID
  }

  public var id: String {
    [kind.rawValue, detail ?? "", sourceID?.uuidString ?? ""].joined(separator: ":")
  }

  public var message: String {
    switch kind {
    case .missingTitle:
      "Add a recipe title."
    case .emptyIngredients:
      "Add at least one ingredient."
    case .emptyInstructions:
      "Add at least one instruction."
    case .missingIngredientQuantity:
      "Check the quantity for \(quotedDetail)."
    case .duplicateIngredient:
      "\(quotedDetail) is listed more than once."
    case .ingredientNotReferenced:
      "\(quotedDetail) is listed but not mentioned in the instructions."
    case .referencedIngredientNotListed:
      "\(quotedDetail) is mentioned in the instructions but not listed as an ingredient."
    case .unparseablePrepTime:
      "Check prep time \(quotedDetail); it is not a readable duration."
    case .unparseableCookTime:
      "Check cook time \(quotedDetail); it is not a readable duration."
    case .unparseableTotalTime:
      "Check total time \(quotedDetail); it is not a readable duration."
    case .unattributedSource:
      "Review this source; its terms do not appear in the extracted recipe."
    }
  }

  private var quotedDetail: String {
    "“\(detail ?? "")”"
  }
}

/// The pure, fixture-testable uncertainty pass for Create Recipe. It is deliberately conservative:
/// linguistic provenance and semantic interpretation remain deferred, so it reports only direct structural,
/// parsing, and lexical mismatches that a cook can verify in the editor.
public enum RecipeExtractionIssueDetector {
  public static func issues(
    in extraction: RecipeExtraction,
    sources: [CreateRecipeSourceItem]
  ) -> [RecipeExtractionIssue] {
    let ingredientLines = extraction.ingredientSections
      .flatMap(\.lines)
      .filter { !$0.trimmedRecipeExtractionText.isEmpty }
    let instructionSteps = extraction.instructionSections
      .flatMap(\.steps)
      .filter { !$0.trimmedRecipeExtractionText.isEmpty }
    var issues: [RecipeExtractionIssue] = []

    if extraction.title?.trimmedRecipeExtractionText.isEmpty != false {
      issues.append(.init(kind: .missingTitle))
    }
    if ingredientLines.isEmpty {
      issues.append(.init(kind: .emptyIngredients))
    }
    if instructionSteps.isEmpty {
      issues.append(.init(kind: .emptyInstructions))
    }

    appendUnparseableDuration(extraction.prepTime, kind: .unparseablePrepTime, to: &issues)
    appendUnparseableDuration(extraction.cookTime, kind: .unparseableCookTime, to: &issues)
    appendUnparseableDuration(extraction.totalTime, kind: .unparseableTotalTime, to: &issues)

    let ingredients = ingredientLines.compactMap(Ingredient.init)
    for ingredient in ingredients where ingredient.parsed.quantity == nil {
      issues.append(.init(kind: .missingIngredientQuantity, detail: ingredient.line))
    }

    let duplicateNames = duplicateIngredientNames(in: ingredients)
    for name in duplicateNames {
      issues.append(.init(kind: .duplicateIngredient, detail: name))
    }

    let listedNames = Set(ingredients.map(\.canonicalName))
    let referencedNames = instructionIngredientNames(in: instructionSteps)
    for name in listedNames.sorted() where !referencedNames.contains(name) {
      issues.append(.init(kind: .ingredientNotReferenced, detail: name))
    }

    for name in unlistedInstructionIngredientNames(in: instructionSteps, listedNames: listedNames) {
      issues.append(.init(kind: .referencedIngredientNotListed, detail: name))
    }

    let extractionWords = meaningfulWords(in: extractionText(extraction))
    for source in sources {
      let sourceWords = meaningfulWords(in: source.text)
      guard !sourceWords.isEmpty, sourceWords.isDisjoint(with: extractionWords) else { continue }
      issues.append(.init(kind: .unattributedSource, sourceID: source.id))
    }

    return issues
  }

  private static func appendUnparseableDuration(
    _ text: String?,
    kind: RecipeExtractionIssue.Kind,
    to issues: inout [RecipeExtractionIssue]
  ) {
    guard let text = text?.trimmedRecipeExtractionText, !text.isEmpty,
      RecipeDurationParser.minutes(text) == nil
    else { return }
    issues.append(.init(kind: kind, detail: text))
  }

  private static func duplicateIngredientNames(in ingredients: [Ingredient]) -> [String] {
    var seen = Set<String>()
    var duplicates = Set<String>()
    var result: [String] = []

    for ingredient in ingredients where !seen.insert(ingredient.canonicalName).inserted {
      if duplicates.insert(ingredient.canonicalName).inserted {
        result.append(ingredient.canonicalName)
      }
    }
    return result
  }

  private static func instructionIngredientNames(in steps: [String]) -> Set<String> {
    var names = Set<String>()
    for step in steps {
      names.formUnion(canonicalIngredientPhrases(instructionWords(in: step)))
    }
    return names
  }

  private static func unlistedInstructionIngredientNames(
    in steps: [String],
    listedNames: Set<String>
  ) -> [String] {
    var result: [String] = []
    var reported = Set<String>()

    for step in steps {
      let words = instructionWords(in: step)
      for index in words.indices where ingredientIntroductionVerbs.contains(words[index]) {
        guard let candidate = ingredientNameFollowingIntroduction(at: index, in: words, listedNames: listedNames),
          !listedNames.contains(candidate), reported.insert(candidate).inserted
        else { continue }
        result.append(candidate)
      }
    }
    return result
  }

  private static func ingredientNameFollowingIntroduction(
    at index: Int,
    in words: [String],
    listedNames: Set<String>
  ) -> String? {
    let remainder = words.dropFirst(index + 1).drop { ingredientIntroductionFillers.contains($0) }
    guard let first = remainder.first else { return nil }

    let names = remainder.indices.compactMap { end in
      CanonicalIngredient.canonicalName(remainder[...end].joined(separator: " "))
    }
    // A listed multiword ingredient ("olive oil") wins over the first word ("olive"). When no listed
    // phrase exists, retain only the first noun-like token rather than falsely claiming an entire sentence
    // after the verb is one ingredient.
    if names.contains(where: listedNames.contains) {
      return nil
    }
    return CanonicalIngredient.canonicalName(first)
  }

  private static func canonicalIngredientPhrases(_ words: [String]) -> [String] {
    var names = Set<String>()
    for start in words.indices {
      for end in start..<words.count {
        if let name = CanonicalIngredient.canonicalName(words[start...end].joined(separator: " ")) {
          names.insert(name)
        }
      }
    }
    return Array(names)
  }

  private static func instructionWords(in text: String) -> [String] {
    text.foldedRecipeExtractionWords
  }

  private static func extractionText(_ extraction: RecipeExtraction) -> String {
    let fields = [
      extraction.title,
      extraction.summary,
      extraction.author,
      extraction.publisherName,
      extraction.servingsText,
      extraction.prepTime,
      extraction.cookTime,
      extraction.totalTime,
    ]
    .compactMap { $0 }
    return (fields + extraction.ingredientSections.flatMap(\.lines) + extraction.instructionSections.flatMap(\.steps))
      .joined(separator: "\n")
  }

  /// Excluding tokens no longer than the English article "an" avoids treating articles and short units as
  /// provenance evidence without a hand-tuned numeric threshold.
  private static func meaningfulWords(in text: String) -> Set<String> {
    Set(text.foldedRecipeExtractionWords.filter { $0.count > "an".count })
  }

  private static let ingredientIntroductionVerbs: Set<String> = ["add", "combine", "fold", "mix", "stir", "whisk"]
  private static let ingredientIntroductionFillers: Set<String> = ["a", "an", "in", "the", "together", "with"]

  private struct Ingredient {
    let line: String
    let parsed: (
      quantity: Double?, quantityText: String?, unit: String?, item: String?, preparation: String?,
      comment: String?, parsingText: String
    )
    let canonicalName: String

    init?(_ line: String) {
      let parsed = IngredientParser.parse(line)
      guard let canonicalName = CanonicalIngredient.canonicalName(parsed.item ?? parsed.parsingText) else {
        return nil
      }
      self.line = line
      self.parsed = parsed
      self.canonicalName = canonicalName
    }
  }
}

private extension String {
  var trimmedRecipeExtractionText: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var foldedRecipeExtractionWords: [String] {
    folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
  }
}
