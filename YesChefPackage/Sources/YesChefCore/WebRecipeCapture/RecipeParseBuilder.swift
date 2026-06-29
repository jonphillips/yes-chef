import Foundation

struct RecipeParseBuilder {
  var votes = RecipeAttributeVotes()
  private(set) var images: [URL] = []
  private(set) var schemaTypes: [String] = []
  private(set) var categoryNames: [String] = []
  private(set) var ingredients: [String] = []
  private(set) var instructionSections: [ParsedRecipeInstructionSection] = []

  let sourceURL: URL?
  let originalHTML: String

  init(sourceURL: URL?, originalHTML: String) {
    self.sourceURL = sourceURL
    self.originalHTML = originalHTML
  }

  mutating func addImage(_ rawValue: String?) {
    guard let url = resolvedURL(rawValue), RecipeImageFiltering.isRelevant(url) else { return }
    if !images.contains(url) { images.append(url) }
  }

  mutating func addSchemaType(_ rawValue: String?) {
    guard let value = Self.normalizedSchemaType(rawValue), !schemaTypes.contains(value) else { return }
    schemaTypes.append(value)
  }

  mutating func addCategory(_ rawValue: String?) {
    for name in Self.listNames(rawValue) where !categoryNames.contains(name) {
      categoryNames.append(name)
    }
  }

  mutating func addIngredient(_ rawValue: String?) {
    for line in Self.lines(rawValue) where !ingredients.contains(line) {
      ingredients.append(line)
    }
  }

  mutating func addInstruction(_ rawValue: String?) {
    let steps = Self.lines(rawValue)
    guard !steps.isEmpty else { return }
    appendInstructionSection(name: nil, steps: steps)
  }

  mutating func addInstructionSection(name: String?, steps: [String]) {
    let cleanedSteps = steps.flatMap(Self.lines)
    guard !cleanedSteps.isEmpty else { return }
    appendInstructionSection(name: name?.trimmingCharacters(in: .whitespacesAndNewlines), steps: cleanedSteps)
  }

  func build(capturedAt: Date) -> ParsedRecipePage {
    let prepTime = votes.winner(.prepTime).flatMap(RecipeDurationParser.minutes)
    let cookTime = votes.winner(.cookTime).flatMap(RecipeDurationParser.minutes)
    let totalTime = votes.winner(.totalTime).flatMap(RecipeDurationParser.minutes)
    let ingredientSections = Self.sectionedIngredients(ingredients)
    var warnings: [WebRecipeCaptureWarning] = []
    let hasStructuredRecipe = schemaTypes.contains("Recipe")
      || !ingredients.isEmpty
      || !instructionSections.isEmpty
      || votes.winner(.servingsText) != nil
      || prepTime != nil
      || cookTime != nil
      || totalTime != nil
    if !hasStructuredRecipe { warnings.append(.noStructuredRecipeData) }
    if votes.winner(.title) == nil { warnings.append(.untitledRecipe) }
    if ingredientSections.allSatisfy(\.lines.isEmpty) { warnings.append(.noIngredients) }
    if instructionSections.allSatisfy(\.steps.isEmpty) { warnings.append(.noInstructions) }

    return ParsedRecipePage(
      sourceURL: resolvedSourceURL(),
      title: resolvedTitle(),
      titleIsStructured: (votes.winnerPriority(.title) ?? RecipeAttributeVotes.chromePriority)
        > RecipeAttributeVotes.chromePriority,
      summary: votes.winner(.summary),
      author: votes.winner(.author),
      publisherName: votes.winner(.publisherName),
      servingsText: votes.winner(.servingsText),
      prepTimeMinutes: prepTime,
      cookTimeMinutes: cookTime,
      totalTimeMinutes: totalTime,
      rating: votes.winner(.rating).flatMap(Self.ratingValue),
      categoryNames: categoryNames,
      ingredientSections: ingredientSections,
      instructionSections: instructionSections,
      imageURLs: images,
      schemaTypes: schemaTypes,
      capturedAt: capturedAt,
      originalHTML: originalHTML,
      warnings: warnings
    )
  }

  private mutating func appendInstructionSection(name: String?, steps: [String]) {
    let section = ParsedRecipeInstructionSection(name: name?.nonEmpty, steps: steps)
    if !instructionSections.contains(section) { instructionSections.append(section) }
  }

  private func resolvedTitle() -> String? {
    guard let title = votes.winner(.title) else { return nil }
    guard votes.winnerPriority(.title) == RecipeAttributeVotes.chromePriority else { return title }
    return Self.trimmingTagline(title)
  }

  private func resolvedSourceURL() -> URL? {
    sourceURL ?? votes.winner(.sourceURL).flatMap { URL(string: $0) }
  }

  private func resolvedURL(_ rawValue: String?) -> URL? {
    guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return URL(string: value, relativeTo: sourceURL)?.absoluteURL
  }

  private static func normalizedSchemaType(_ rawValue: String?) -> String? {
    guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value.split(whereSeparator: { $0 == "/" || $0 == "#" }).last.map(String.init)
  }

  private static func trimmingTagline(_ title: String) -> String {
    guard let pipe = title.firstIndex(of: "|") else { return title }
    let head = title[..<pipe].trimmingCharacters(in: .whitespacesAndNewlines)
    return head.isEmpty ? title : String(head)
  }

  static func lines(_ rawValue: String?) -> [String] {
    guard let rawValue else { return [] }
    return rawValue
      .components(separatedBy: .newlines)
      .flatMap { line in line.components(separatedBy: "\u{2028}") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func listNames(_ rawValue: String?) -> [String] {
    guard let rawValue else { return [] }
    return rawValue
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func sectionedIngredients(_ lines: [String]) -> [ParsedRecipeIngredientSection] {
    IngredientSectionHeading.sections(in: lines)
      .map { ParsedRecipeIngredientSection(name: $0.name, lines: $0.lines) }
  }

  private static func ratingValue(_ text: String) -> Int? {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    let rounded = Int(value.rounded())
    return (0...5).contains(rounded) ? rounded : nil
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
