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

/// The visible, typed vocabulary the proposer may classify against.
///
/// Hidden rows are deliberately absent: a hidden category group means its vocabulary is tucked
/// away from new assignment, not merely hidden in the management UI.
public struct LabelVocabulary: Equatable, Sendable {
  public var facets: [Facet]
  public var categories: [Category]

  public init(facets: [Facet], categories: [Category]) {
    let visibleFacets = CategoryRepository.sortedFacets(facets.filter { !$0.hidden })
    let visibleFacetIDs = Set(visibleFacets.map(\.id))
    self.facets = visibleFacets
    self.categories = CategoryRepository.sortedCategories(categories.filter { category in
      !category.hidden && (category.facetID.map { visibleFacetIDs.contains($0) } ?? true)
    })
  }
}

/// A reviewable label suggestion. It is only a value until a person accepts it and the existing
/// category reconciler writes it while saving the recipe.
public enum SuggestedLabel: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case existingCategory
    case newChild
    case loose
    case namespace
  }

  /// A new value inside an existing, identified facet. A `nil` parent means the value belongs at
  /// the facet's top level; otherwise it belongs below that exact category row.
  public struct NewChild: Codable, Equatable, Sendable {
    public var facet: Facet
    public var parentCategory: Category?
    public var name: String

    public init(facet: Facet, parentCategory: Category?, name: String) {
      self.facet = facet
      self.parentCategory = parentCategory
      self.name = name
    }
  }

  /// A proposal to create a distinct `Facet` row and its first assignable value.
  public struct Namespace: Codable, Equatable, Sendable {
    public var facetName: String
    public var firstValueName: String

    public init(facetName: String, firstValueName: String) {
      self.facetName = facetName
      self.firstValueName = firstValueName
    }
  }

  case existingCategory(Category)
  case newChild(NewChild)
  case loose(String)
  case namespace(Namespace)

  public var kind: Kind {
    switch self {
    case .existingCategory:
      .existingCategory
    case .newChild:
      .newChild
    case .loose:
      .loose
    case .namespace:
      .namespace
    }
  }

  public var id: String {
    switch self {
    case let .existingCategory(category):
      "existing>\(category.id.uuidString)"
    case let .newChild(child):
      "newChild>\(child.facet.id.uuidString)>\(child.parentCategory?.id.uuidString ?? "root")>\(normalizedLabelName(child.name))"
    case let .loose(name):
      "loose>\(normalizedLabelName(name))"
    case let .namespace(namespace):
      "namespace>\(normalizedLabelName(namespace.facetName))>\(normalizedLabelName(namespace.firstValueName))"
    }
  }

  /// A user-facing description only. Persistence receives the resolved ids above, never this
  /// serialization.
  public var categoryName: String {
    switch self {
    case let .existingCategory(category):
      category.name
    case let .newChild(child):
      "\(child.facet.name): \(child.name)"
    case let .loose(name):
      name
    case let .namespace(namespace):
      "\(namespace.facetName): \(namespace.firstValueName)"
    }
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

  private func normalizedLabelName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}

/// A suggestion the proposer could not map to a safe destination. It is surfaced, never silently
/// dropped (ADR-0049 D2). On the on-device tier a small model emitting one sloppy path among several
/// is the expected case, so a single bad entry must not discard the good ones — see
/// [[loud-decode-not-in-migrator]] for the same tolerate-preserve-report correction.
public struct RejectedLabelSuggestion: Codable, Equatable, Identifiable, Sendable {
  public var raw: String
  public var reason: String

  public init(raw: String, reason: String) {
    self.raw = raw
    self.reason = reason
  }

  public var id: String { "\(raw)|\(reason)" }
}

/// The outcome of a label proposal: the mappable suggestions plus the ones that couldn't be mapped.
public struct LabelProposal: Equatable, Sendable {
  public var accepted: [SuggestedLabel]
  public var rejected: [RejectedLabelSuggestion]

  public init(accepted: [SuggestedLabel] = [], rejected: [RejectedLabelSuggestion] = []) {
    self.accepted = accepted
    self.rejected = rejected
  }
}

public enum LabelProposerError: Error, Equatable, LocalizedError, Sendable {
  case responseTruncated
  case responseUnreadable

  public var errorDescription: String? {
    switch self {
    case .responseTruncated:
      "The label suggestions ran out of room before they finished. Try again."
    case .responseUnreadable:
      "The label suggestions could not be read. Try again."
    }
  }
}

/// A model-backed, advisory classifier anchored to the category tree already owned by the cook.
/// It never writes categories or recipe-category joins.
public struct LabelProposer: Sendable {
  public var propose: @Sendable (_ recipe: LabelProposalRecipe, _ vocabulary: LabelVocabulary, _ tier: ModelTier, _ effort: ReasoningEffort) async throws -> LabelProposal

  public init(
    propose: @escaping @Sendable (_ recipe: LabelProposalRecipe, _ vocabulary: LabelVocabulary, _ tier: ModelTier, _ effort: ReasoningEffort) async throws -> LabelProposal
  ) {
    self.propose = propose
  }

  /// The labeling surfaces tolerate a little extra latency in exchange for a useful proposal.
  public func callAsFunction(
    recipe: LabelProposalRecipe,
    vocabulary: LabelVocabulary,
    tier: ModelTier = .onDevice,
    effort: ReasoningEffort = .high
  ) async throws -> LabelProposal {
    try await propose(recipe, vocabulary, tier, effort)
  }
}

extension LabelProposer: DependencyKey {
  public static var liveValue: Self {
    Self { recipe, vocabulary, tier, effort in
      @Dependency(\.modelClient) var modelClient
      let response = try await call(recipe: recipe, vocabulary: vocabulary, tier: tier, effort: effort)
        .complete(using: modelClient)
      guard !response.wasTruncated else { throw LabelProposerError.responseTruncated }
      return try parse(response.text, vocabulary: vocabulary)
    }
  }

  public static let testValue = Self { _, _, _, _ in LabelProposal() }

  static let maxTokens = 1_024

  static let instructions = """
    Suggest a small set of useful recipe categories. Return ONLY strict JSON in this shape:
    {"suggestions":[{"kind":"existingCategory","path":["Cuisine","Italian"]}]}

    Each suggestion has exactly one of these kinds:
    - existingCategory: path is an exact existing category path from the supplied vocabulary.
    - newChild: path begins with an existing category group and ends in a new child. Any intervening
      components are exact existing values inside that group.
    - loose: path has one new, parentless category name.
    - namespace: path has exactly two new names — a brand-new category group and its first child value,
      e.g. ["Season","Summer"]. Both are new. Use this rarely and only for a genuinely useful new dimension.

    Prefer exact existing paths over new labels. A new child under an existing category is cheaper than a new
    loose label; a new namespace is the most expensive and should be exceptional. Do not duplicate suggestions,
    invent paths that cannot be mapped to the supplied tree, or suggest irrelevant labels.
    """

  static func prompt(recipe: LabelProposalRecipe, vocabulary: LabelVocabulary) -> String {
    let categoriesByID = Dictionary(uniqueKeysWithValues: vocabulary.categories.map { ($0.id, $0) })
    let groups = vocabulary.facets.map { facet in
      let values = vocabulary.categories
        .filter { $0.facetID == facet.id }
        .map { "  - \(CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID))" }
        .joined(separator: "\n")
      return "\(facet.name):\(values.isEmpty ? " (no values yet)" : "\n\(values)")"
    }
    let looseLabels = vocabulary.categories
      .filter { $0.facetID == nil }
      .map(\.name)
      .joined(separator: ", ")
    let ingredients = recipe.ingredientLines.isEmpty
      ? "(none available)"
      : recipe.ingredientLines.map { "- \($0)" }.joined(separator: "\n")
    let summary = recipe.summary.map { "\nSummary: \($0)" } ?? ""
    let publisher = recipe.publisherName.map { "\nPublisher: \($0)" } ?? ""

    return """
      Existing category groups and their values (use these exact paths when possible):
      \(groups.isEmpty ? "(none)" : groups.joined(separator: "\n"))

      Existing loose labels: \(looseLabels.isEmpty ? "(none)" : looseLabels)

      Recipe title: \(recipe.title)\(summary)\(publisher)
      Ingredients:
      \(ingredients)
      """
  }

  static func call(
    recipe: LabelProposalRecipe,
    vocabulary: LabelVocabulary,
    tier: ModelTier = .onDevice,
    effort: ReasoningEffort = .high
  ) -> ModelCall {
    ModelCall(
      surface: .capture,
      task: .categorization,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .candidates],
      tier: tier,
      system: instructions,
      prompt: prompt(recipe: recipe, vocabulary: vocabulary),
      maxTokens: maxTokens,
      reasoningEffort: effort
    )
  }

  public static func parse(_ text: String, vocabulary: LabelVocabulary) throws -> LabelProposal {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let response = try? JSONDecoder().decode(Response.self, from: data)
    else { throw LabelProposerError.responseUnreadable }

    // Tolerate-preserve-report: one unmappable path must not sink the whole batch (ADR-0049 D2).
    var accepted: [SuggestedLabel] = []
    var rejected: [RejectedLabelSuggestion] = []
    var seenIDs: Set<SuggestedLabel.ID> = []

    for raw in response.suggestions {
      do {
        let suggestion = try mapSuggestion(
          raw,
          vocabulary: vocabulary
        )
        guard seenIDs.insert(suggestion.id).inserted else {
          rejected.append(
            RejectedLabelSuggestion(raw: suggestion.categoryName, reason: "duplicates an earlier suggestion")
          )
          continue
        }
        accepted.append(suggestion)
      } catch let failure as MappingFailure {
        rejected.append(RejectedLabelSuggestion(raw: failure.raw, reason: failure.reason))
      }
    }

    return LabelProposal(accepted: accepted, rejected: rejected)
  }

  /// Thrown per suggestion so `parse` can collect it into `rejected` instead of failing the batch.
  private struct MappingFailure: Error {
    var raw: String
    var reason: String
  }

  private static func mapSuggestion(
    _ raw: RawSuggestion,
    vocabulary: LabelVocabulary
  ) throws -> SuggestedLabel {
    let path = raw.path.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let rawLabel = path.joined(separator: " > ")
    let surfaced = rawLabel.isEmpty ? "(empty)" : rawLabel
    guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty }) else {
      throw MappingFailure(raw: surfaced, reason: "a category path was empty")
    }
    let normalized = normalizedPath(path.joined(separator: " > "))
    guard !normalized.isEmpty else {
      throw MappingFailure(raw: surfaced, reason: "a category path was empty")
    }

    switch raw.kind {
    case .existingCategory:
      guard let category = category(for: path, in: vocabulary) else {
        throw MappingFailure(raw: surfaced, reason: "\(rawLabel) is not in the existing tree")
      }
      return .existingCategory(category)
    case .newChild:
      guard path.count > 1 else {
        throw MappingFailure(raw: surfaced, reason: "a new value did not name its existing category group")
      }
      guard let facet = facet(named: path[0], in: vocabulary) else {
        throw MappingFailure(raw: surfaced, reason: "\(path[0]) is not an existing category group")
      }
      let parentComponents = Array(path.dropFirst().dropLast())
      let parent = parentComponents.isEmpty ? nil : category(for: [path[0]] + parentComponents, in: vocabulary)
      guard parentComponents.isEmpty || parent != nil else {
        throw MappingFailure(raw: surfaced, reason: "\(path.dropLast().joined(separator: " > ")) is not an existing category path")
      }
      let name = path[path.count - 1]
      guard !vocabulary.categories.contains(where: {
        $0.facetID == facet.id
          && $0.parentCategoryID == parent?.id
          && namesMatch($0.name, name)
      }) else {
        throw MappingFailure(raw: surfaced, reason: "\(rawLabel) already exists")
      }
      return .newChild(.init(facet: facet, parentCategory: parent, name: name))
    case .loose:
      guard path.count == 1 else {
        throw MappingFailure(raw: surfaced, reason: "a loose category must be a single new name")
      }
      guard !vocabulary.categories.contains(where: {
        $0.facetID == nil && namesMatch($0.name, path[0])
      }) else {
        throw MappingFailure(raw: surfaced, reason: "\(path[0]) is already an existing loose label")
      }
      return .loose(path[0])
    case .namespace:
      guard path.count == 2 else {
        throw MappingFailure(raw: surfaced, reason: "a new category group must name a new dimension and its first value")
      }
      guard facet(named: path[0], in: vocabulary) == nil else {
        throw MappingFailure(raw: surfaced, reason: "\(path[0]) is already a category group")
      }
      return .namespace(.init(facetName: path[0], firstValueName: path[1]))
    }
  }

  private static func category(for path: [String], in vocabulary: LabelVocabulary) -> Category? {
    if path.count == 1 {
      return vocabulary.categories.first {
        $0.facetID == nil && namesMatch($0.name, path[0])
      }
    }
    guard let facet = facet(named: path[0], in: vocabulary) else { return nil }
    var parentID: Category.ID?
    var current: Category?
    for component in path.dropFirst() {
      guard let category = vocabulary.categories.first(where: {
        $0.facetID == facet.id
          && $0.parentCategoryID == parentID
          && namesMatch($0.name, component)
      }) else { return nil }
      current = category
      parentID = category.id
    }
    return current
  }

  private static func facet(named name: String, in vocabulary: LabelVocabulary) -> Facet? {
    vocabulary.facets.first { namesMatch($0.name, name) }
  }

  private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
    lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
