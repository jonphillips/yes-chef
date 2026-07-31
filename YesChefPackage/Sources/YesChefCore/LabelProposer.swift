import Dependencies
import Foundation
import LLMClientKit

/// The small, capture-ready representation the label model classifies.
///
/// This intentionally contains recipe content, not persistence types. The proposer can therefore
/// run before a captured recipe exists and can be reused by later detail and queue surfaces.
public struct LabelProposalRecipe: Equatable, Sendable {
  public var title: String
  public var summary: String?
  public var publisherName: String?
  public var ingredientLines: [String]

  public init(
    title: String,
    summary: String? = nil,
    publisherName: String? = nil,
    ingredientLines: [String] = []
  ) {
    self.title = title
    self.summary = summary
    self.publisherName = publisherName
    self.ingredientLines = ingredientLines
  }
}

/// A reviewable label suggestion. It is only a value until a person accepts it and the existing
/// category reconciler writes it while saving the recipe.
public struct SuggestedLabel: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case existingCategory
    case newChild
    case loose
    case namespace
  }

  public var kind: Kind
  public var path: [String]

  public init(kind: Kind, path: [String]) {
    self.kind = kind
    self.path = path
  }

  public var id: String {
    path.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
      .joined(separator: ">")
  }

  /// The form the existing deterministic category reconciler accepts.
  public var categoryName: String {
    path.joined(separator: " > ")
  }

  public var reviewTitle: String {
    switch kind {
    case .existingCategory:
      categoryName
    case .newChild:
      "New category: \(categoryName)"
    case .loose:
      "Loose category: \(categoryName)"
    case .namespace:
      "New category group: \(categoryName)"
    }
  }
}

public enum LabelProposerError: Error, Equatable, LocalizedError, Sendable {
  case responseTruncated
  case responseUnreadable
  case invalidSuggestion(String)

  public var errorDescription: String? {
    switch self {
    case .responseTruncated:
      "The label suggestions ran out of room before they finished. Try again."
    case .responseUnreadable:
      "The label suggestions could not be read. Try again."
    case let .invalidSuggestion(reason):
      "The label suggestions could not be safely mapped: \(reason)"
    }
  }
}

/// A model-backed, advisory classifier anchored to the category tree already owned by the cook.
/// It never writes categories or recipe-category joins.
public struct LabelProposer: Sendable {
  public var propose: @Sendable (_ recipe: LabelProposalRecipe, _ categories: [Category]) async throws -> [SuggestedLabel]

  public init(
    propose: @escaping @Sendable (_ recipe: LabelProposalRecipe, _ categories: [Category]) async throws -> [SuggestedLabel]
  ) {
    self.propose = propose
  }

  public func callAsFunction(
    recipe: LabelProposalRecipe,
    existingTree categories: [Category]
  ) async throws -> [SuggestedLabel] {
    try await propose(recipe, categories)
  }
}

extension LabelProposer: DependencyKey {
  public static var liveValue: Self {
    Self { recipe, categories in
      @Dependency(\.modelClient) var modelClient
      let response = try await call(recipe: recipe, categories: categories)
        .complete(using: modelClient)
      guard !response.wasTruncated else { throw LabelProposerError.responseTruncated }
      return try parse(response.text, categories: categories)
    }
  }

  public static let testValue = Self { _, _ in [] }

  static let maxTokens = 1_024

  static let instructions = """
    Suggest a small set of useful recipe categories. Return ONLY strict JSON in this shape:
    {"suggestions":[{"kind":"existingCategory","path":["Cuisine","Italian"]}]}

    Each suggestion has exactly one of these kinds:
    - existingCategory: path is an exact existing category path from the supplied tree.
    - newChild: path ends in a new child and every preceding path component is an exact existing category path.
    - loose: path has one new, parentless category name.
    - namespace: path has one new parent category name. Use this rarely and only for a genuinely useful new dimension.

    Prefer exact existing paths over new labels. A new child under an existing category is cheaper than a new
    loose label; a new namespace is the most expensive and should be exceptional. Do not duplicate suggestions,
    invent paths that cannot be mapped to the supplied tree, or suggest irrelevant labels.
    """

  static func prompt(recipe: LabelProposalRecipe, categories: [Category]) -> String {
    let orderedCategories = CategoryRepository.sortedCategories(categories)
    let categoriesByID = Dictionary(uniqueKeysWithValues: orderedCategories.map { ($0.id, $0) })
    let tree = orderedCategories
      .map { CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID) }
      .joined(separator: "\n")
    let ingredients = recipe.ingredientLines.isEmpty
      ? "(none available)"
      : recipe.ingredientLines.map { "- \($0)" }.joined(separator: "\n")
    let summary = recipe.summary.map { "\nSummary: \($0)" } ?? ""
    let publisher = recipe.publisherName.map { "\nPublisher: \($0)" } ?? ""

    return """
      Existing category tree (use these exact paths when possible):
      \(tree.isEmpty ? "(empty)" : tree)

      Recipe title: \(recipe.title)\(summary)\(publisher)
      Ingredients:
      \(ingredients)
      """
  }

  static func call(recipe: LabelProposalRecipe, categories: [Category]) -> ModelCall {
    ModelCall(
      surface: .capture,
      task: .categorization,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .candidates],
      tier: .onDevice,
      system: instructions,
      prompt: prompt(recipe: recipe, categories: categories),
      maxTokens: maxTokens,
      reasoningEffort: .low
    )
  }

  public static func parse(_ text: String, categories: [Category]) throws -> [SuggestedLabel] {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let response = try? JSONDecoder().decode(Response.self, from: data)
    else { throw LabelProposerError.responseUnreadable }

    let orderedCategories = CategoryRepository.sortedCategories(categories)
    let categoriesByID = Dictionary(uniqueKeysWithValues: orderedCategories.map { ($0.id, $0) })
    let existingPaths = Set(orderedCategories.map {
      normalizedPath(CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID))
    })

    let suggestions = try response.suggestions.map { raw in
      let path = raw.path.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty }) else {
        throw LabelProposerError.invalidSuggestion("a category path was empty")
      }
      let normalized = normalizedPath(path.joined(separator: " > "))
      guard !normalized.isEmpty else {
        throw LabelProposerError.invalidSuggestion("a category path was empty")
      }

      switch raw.kind {
      case .existingCategory:
        guard existingPaths.contains(normalized) else {
          throw LabelProposerError.invalidSuggestion("\(path.joined(separator: " > ")) is not in the existing tree")
        }
      case .newChild:
        guard path.count > 1 else {
          throw LabelProposerError.invalidSuggestion("a new child did not name its existing parent")
        }
        let parentPath = normalizedPath(path.dropLast().joined(separator: " > "))
        guard existingPaths.contains(parentPath) else {
          throw LabelProposerError.invalidSuggestion("\(path.dropLast().joined(separator: " > ")) is not an existing parent")
        }
        guard !existingPaths.contains(normalized) else {
          throw LabelProposerError.invalidSuggestion("\(path.joined(separator: " > ")) already exists")
        }
      case .loose, .namespace:
        guard path.count == 1 else {
          throw LabelProposerError.invalidSuggestion("\(raw.kind.rawValue) must be a single root name")
        }
        guard !existingPaths.contains(normalized) else {
          throw LabelProposerError.invalidSuggestion("\(path[0]) is already in the existing tree")
        }
      }
      return SuggestedLabel(kind: raw.kind, path: path)
    }

    guard Set(suggestions.map(\.id)).count == suggestions.count else {
      throw LabelProposerError.invalidSuggestion("the response repeated a category destination")
    }
    return suggestions
  }

  private struct Response: Decodable {
    var suggestions: [RawSuggestion]
  }

  private struct RawSuggestion: Decodable {
    var kind: SuggestedLabel.Kind
    var path: [String]
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else {
      return nil
    }
    return String(text[open...close])
  }

  private static func normalizedPath(_ path: String) -> String {
    path
      .split(separator: ">")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: ">")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}

extension DependencyValues {
  public var labelProposer: LabelProposer {
    get { self[LabelProposer.self] }
    set { self[LabelProposer.self] = newValue }
  }
}
