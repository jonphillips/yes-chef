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
  public var propose: @Sendable (_ recipe: LabelProposalRecipe, _ categories: [Category], _ tier: ModelTier) async throws -> LabelProposal

  public init(
    propose: @escaping @Sendable (_ recipe: LabelProposalRecipe, _ categories: [Category], _ tier: ModelTier) async throws -> LabelProposal
  ) {
    self.propose = propose
  }

  /// Defaults to the on-device tier (ADR-0049), but the tier is a parameter so the S5 detail labeler
  /// and S6 queue can escalate a weak on-device pass without touching a shared constant.
  public func callAsFunction(
    recipe: LabelProposalRecipe,
    existingTree categories: [Category],
    tier: ModelTier = .onDevice
  ) async throws -> LabelProposal {
    try await propose(recipe, categories, tier)
  }
}

extension LabelProposer: DependencyKey {
  public static var liveValue: Self {
    Self { recipe, categories, tier in
      @Dependency(\.modelClient) var modelClient
      let response = try await call(recipe: recipe, categories: categories, tier: tier)
        .complete(using: modelClient)
      guard !response.wasTruncated else { throw LabelProposerError.responseTruncated }
      return try parse(response.text, categories: categories)
    }
  }

  public static let testValue = Self { _, _, _ in LabelProposal() }

  static let maxTokens = 1_024

  static let instructions = """
    Suggest a small set of useful recipe categories. Return ONLY strict JSON in this shape:
    {"suggestions":[{"kind":"existingCategory","path":["Cuisine","Italian"]}]}

    Each suggestion has exactly one of these kinds:
    - existingCategory: path is an exact existing category path from the supplied tree.
    - newChild: path ends in a new child and every preceding path component is an exact existing category path.
    - loose: path has one new, parentless category name.
    - namespace: path has exactly two new names — a brand-new parent dimension and its first child value,
      e.g. ["Season","Summer"]. Both are new. Use this rarely and only for a genuinely useful new dimension.

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

  static func call(recipe: LabelProposalRecipe, categories: [Category], tier: ModelTier = .onDevice) -> ModelCall {
    ModelCall(
      surface: .capture,
      task: .categorization,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .candidates],
      tier: tier,
      system: instructions,
      prompt: prompt(recipe: recipe, categories: categories),
      maxTokens: maxTokens,
      reasoningEffort: .low
    )
  }

  public static func parse(_ text: String, categories: [Category]) throws -> LabelProposal {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let response = try? JSONDecoder().decode(Response.self, from: data)
    else { throw LabelProposerError.responseUnreadable }

    let orderedCategories = CategoryRepository.sortedCategories(categories)
    let categoriesByID = Dictionary(uniqueKeysWithValues: orderedCategories.map { ($0.id, $0) })
    // Map each existing path to the canonical stored components so accepted suggestions carry the
    // tree's exact spelling. The reconciler (`findOrCreateCategory`) matches diacritic-sensitively,
    // so returning `["Cuisine", "Cafe"]` when the tree stores `["Cuisine", "Café"]` would make Save
    // create a duplicate child. Canonicalizing here keeps the proposer's diacritic-insensitive
    // matching from diverging from the writer.
    let canonicalComponentsByNormalizedPath: [String: [String]] = orderedCategories.reduce(into: [:]) { result, category in
      let components = CategoryHierarchy.pathComponents(for: category, categoriesByID: categoriesByID)
      result[normalizedPath(components.joined(separator: " > "))] = components
    }
    let existingPaths = Set(canonicalComponentsByNormalizedPath.keys)

    // Tolerate-preserve-report: one unmappable path must not sink the whole batch (ADR-0049 D2).
    var accepted: [SuggestedLabel] = []
    var rejected: [RejectedLabelSuggestion] = []
    var seenIDs: Set<SuggestedLabel.ID> = []

    for raw in response.suggestions {
      do {
        let suggestion = try mapSuggestion(
          raw,
          canonicalComponentsByNormalizedPath: canonicalComponentsByNormalizedPath,
          existingPaths: existingPaths
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
    canonicalComponentsByNormalizedPath: [String: [String]],
    existingPaths: Set<String>
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
      guard let canonical = canonicalComponentsByNormalizedPath[normalized] else {
        throw MappingFailure(raw: surfaced, reason: "\(rawLabel) is not in the existing tree")
      }
      return SuggestedLabel(kind: .existingCategory, path: canonical)
    case .newChild:
      guard path.count > 1 else {
        throw MappingFailure(raw: surfaced, reason: "a new child did not name its existing parent")
      }
      let parentPath = normalizedPath(path.dropLast().joined(separator: " > "))
      guard let canonicalParent = canonicalComponentsByNormalizedPath[parentPath] else {
        throw MappingFailure(raw: surfaced, reason: "\(path.dropLast().joined(separator: " > ")) is not an existing parent")
      }
      guard !existingPaths.contains(normalized) else {
        throw MappingFailure(raw: surfaced, reason: "\(rawLabel) already exists")
      }
      // Canonicalize the existing-parent prefix; keep the model's new child name verbatim.
      return SuggestedLabel(kind: .newChild, path: canonicalParent + [path[path.count - 1]])
    case .loose:
      guard path.count == 1 else {
        throw MappingFailure(raw: surfaced, reason: "a loose category must be a single new name")
      }
      guard !existingPaths.contains(normalized) else {
        throw MappingFailure(raw: surfaced, reason: "\(path[0]) is already in the existing tree")
      }
      return SuggestedLabel(kind: .loose, path: path)
    case .namespace:
      // Finding 3: a namespace carries the new dimension AND its first value, so accepting it files the
      // recipe under a real child (`Season > Summer`) instead of a bare root that is indistinguishable
      // from a loose label at the storage layer (D1).
      guard path.count == 2 else {
        throw MappingFailure(raw: surfaced, reason: "a new category group must name a new dimension and its first value")
      }
      guard !existingPaths.contains(normalizedPath(path[0])) else {
        throw MappingFailure(raw: surfaced, reason: "\(path[0]) is already a category, so it is not a new dimension")
      }
      guard !existingPaths.contains(normalized) else {
        throw MappingFailure(raw: surfaced, reason: "\(rawLabel) already exists")
      }
      return SuggestedLabel(kind: .namespace, path: path)
    }
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
