import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public enum ServeWithCoding {
  public static func encode(_ items: [ServeWithItem]) throws -> Data? {
    guard !items.isEmpty else { return nil }
    return try JSONEncoder().encode(items)
  }

  public static func decode(_ data: Data?) -> [ServeWithItem] {
    guard let data else { return [] }
    return (try? JSONDecoder().decode([ServeWithItem].self, from: data)) ?? []
  }
}

public struct ChefItUpPlan: Equatable, Sendable {
  public var text: String

  public init(text: String) {
    self.text = text
  }
}

/// Presentation-ready text for the prose Playbook sections.
///
/// Multi-line paragraphs read as a list in the Playbook, while a single-line paragraph remains prose.
/// This also normalizes common pasted list markers before applying the app's consistent bullet treatment.
public struct PlaybookEnrichmentDisplayText: Equatable, Sendable {
  public var text: String
  public var hasBulletedLines: Bool

  public init(text: String, hasBulletedLines: Bool) {
    self.text = text
    self.hasBulletedLines = hasBulletedLines
  }
}

public enum PlaybookEnrichmentText {
  public static func displayText(for text: String) -> PlaybookEnrichmentDisplayText {
    let paragraphs = text
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .split(omittingEmptySubsequences: true) { line in
        line.allSatisfy(\.isWhitespace)
      }

    var hasBulletedLines = false
    let renderedParagraphs = paragraphs.map { paragraph in
      guard paragraph.count > 1 else {
        return paragraph.map(String.init).joined(separator: "\n")
      }

      hasBulletedLines = true
      return paragraph
        .map { "• \(strippingLeadingBullet(from: String($0)))" }
        .joined(separator: "\n")
    }

    return PlaybookEnrichmentDisplayText(
      text: renderedParagraphs.joined(separator: "\n\n"),
      hasBulletedLines: hasBulletedLines
    )
  }

  private static func strippingLeadingBullet(from line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let marker = trimmed.first, ["-", "*", "•", "–"].contains(String(marker)) else {
      return trimmed
    }

    let remainder = trimmed.dropFirst()
    guard remainder.first?.isWhitespace == true else { return trimmed }
    return String(remainder.drop(while: \.isWhitespace))
  }
}

public struct ServeWithPlan: Equatable, Sendable {
  public var items: [ServeWithSuggestion]

  public init(items: [ServeWithSuggestion] = []) {
    self.items = items
  }

  public func rendered() -> String {
    items
      .map { item in
        guard let note = item.note else { return item.title }
        return "\(item.title): \(note)"
      }
      .joined(separator: "\n")
  }

  public func editableReviewText() -> String {
    rendered()
  }

  public func applyingEditableReviewText(_ text: String) -> ServeWithPlan {
    ServeWithPlan(
      items: text
        .editableReviewLines
        .compactMap(Self.suggestion(fromEditableReviewLine:))
    )
  }

  /// Keeps every existing suggestion at the top of a handoff review while adding only genuinely new returns.
  /// The exact title-and-note match mirrors `RecipeRepository.reconciledServeWithItems`, which preserves the
  /// stored UUIDs when this review is committed.
  public func unioning(_ returnedPlan: ServeWithPlan) -> ServeWithPlan {
    var seen = Set<ServeWithSuggestion>()
    let items = (items + returnedPlan.items).filter { seen.insert($0).inserted }
    return ServeWithPlan(items: items)
  }

  private static func suggestion(fromEditableReviewLine line: String) -> ServeWithSuggestion? {
    let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard let title = String(pieces[0]).removingMarkdownEmphasis.cleanedEnrichmentText else { return nil }
    return ServeWithSuggestion(
      title: title,
      note: pieces.count > 1 ? String(pieces[1]).cleanedEnrichmentText : nil
    )
  }
}

private extension String {
  var removingMarkdownEmphasis: String {
    replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
  }
}

public struct ServeWithSuggestion: Hashable, Sendable {
  public var title: String
  public var note: String?

  public init(title: String, note: String? = nil) {
    self.title = title
    self.note = note
  }
}

public struct ChefItUpPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> ChefItUpPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> ChefItUpPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> ChefItUpPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension ChefItUpPlanClient: DependencyKey {
  public static let liveValue = ChefItUpPlanClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .recipe,
      task: .chefItUp,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 2048,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.chefItUp.rawValue
    )
    let response = try await call.complete(using: modelClient)
    return parse(response.text)
  }

  public static let testValue = ChefItUpPlanClient { _, _, _, _ in ChefItUpPlan(text: "") }

  static let instructions = """
    You distill a cooking conversation into practical ways to make one recipe more impressive.
    Return ONLY strict JSON: {"text":"short concrete upgrade plan"}.
    Use only the provided recipe and conversation. Prefer useful technique and flavor upgrades over vague praise.
    Return {"text":""} when there is nothing useful to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    enrichmentPrompt(
      selection: selection,
      messages: messages,
      context: context,
      task: "Distill the selected subject into a concise Chef It Up plan."
    )
  }

  public static func parse(_ text: String) -> ChefItUpPlan {
    let object = jsonObject(text)
    let value = object?["text"] as? String ?? text
    return ChefItUpPlan(text: value.cleanedEnrichmentText ?? "")
  }
}

public struct ServeWithPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> ServeWithPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> ServeWithPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> ServeWithPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension ServeWithPlanClient: DependencyKey {
  public static let liveValue = ServeWithPlanClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .recipe,
      task: .serveWith,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 2048,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.serveWith.rawValue
    )
    let response = try await call.complete(using: modelClient)
    return parse(response.text)
  }

  public static let testValue = ServeWithPlanClient { _, _, _, _ in ServeWithPlan() }

  static let instructions = """
    You distill a cooking conversation into accompaniment ideas for one recipe.
    Return ONLY strict JSON: {"items":[{"title":"short accompaniment name","note":"optional one-sentence note"}]}.
    Do not write full recipes. Keep each item small enough to live as an accompaniment on the parent recipe.
    Return {"items":[]} when there is nothing useful to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    enrichmentPrompt(
      selection: selection,
      messages: messages,
      context: context,
      task: "Distill the selected subject into Serve With accompaniment items."
    )
  }

  public static func parse(_ text: String) -> ServeWithPlan {
    guard let raw = jsonObject(text) else { return ServeWithPlan() }
    let elements = raw["items"] as? [[String: Any]] ?? []
    return ServeWithPlan(
      items: elements.compactMap { element in
        guard let title = (element["title"] as? String)?.cleanedEnrichmentText else { return nil }
        return ServeWithSuggestion(
          title: title,
          note: (element["note"] as? String)?.cleanedEnrichmentText
        )
      }
    )
  }
}

extension DependencyValues {
  public var chefItUpPlanClient: ChefItUpPlanClient {
    get { self[ChefItUpPlanClient.self] }
    set { self[ChefItUpPlanClient.self] = newValue }
  }

  public var serveWithPlanClient: ServeWithPlanClient {
    get { self[ServeWithPlanClient.self] }
    set { self[ServeWithPlanClient.self] = newValue }
  }
}

extension RecipeRepository {
  public static func applyChefItUpPlan(
    _ plan: ChefItUpPlan,
    to recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try updateChefItUp(plan.text.nonEmptyEnrichmentText, recipeID: recipeID, in: db, now: now)
  }

  public static func updateChefItUp(
    _ chefItUp: String?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try Recipe.find(recipeID).update {
      $0.chefItUp = chefItUp
      $0.dateModified = now
    }
    .execute(db)
  }

  public static func clearChefItUp(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try updateChefItUp(nil, recipeID: recipeID, in: db, now: now)
  }

  public static func appendServeWithPlan(
    _ plan: ServeWithPlan,
    to recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let recipe = try Recipe.find(recipeID).fetchOne(db)
    var items = ServeWithCoding.decode(recipe?.serveWith)
    items.append(
      contentsOf: plan.items.map { item in
        ServeWithItem(id: uuid(), title: item.title, note: item.note)
      }
    )
    try updateServeWith(items, recipeID: recipeID, in: db, now: now)
  }

  public static func replaceServeWithPlan(
    _ plan: ServeWithPlan,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let recipe = try Recipe.find(recipeID).fetchOne(db)
    let existingItems = ServeWithCoding.decode(recipe?.serveWith)
    let items = reconciledServeWithItems(existingItems, with: plan.items, uuid: uuid)
    try updateServeWith(items, recipeID: recipeID, in: db, now: now)
  }

  public static func removeServeWithItem(
    _ itemID: ServeWithItem.ID,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    let recipe = try Recipe.find(recipeID).fetchOne(db)
    let items = ServeWithCoding.decode(recipe?.serveWith).filter { $0.id != itemID }
    try updateServeWith(items, recipeID: recipeID, in: db, now: now)
  }

  public static func clearServeWith(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try updateServeWith([], recipeID: recipeID, in: db, now: now)
  }

  private static func reconciledServeWithItems(
    _ existingItems: [ServeWithItem],
    with suggestions: [ServeWithSuggestion],
    uuid: () -> UUID
  ) -> [ServeWithItem] {
    var unmatchedItems = existingItems

    return suggestions.map { suggestion in
      if let index = unmatchedItems.firstIndex(where: {
        $0.title == suggestion.title && $0.note == suggestion.note
      }) {
        return unmatchedItems.remove(at: index)
      }
      return ServeWithItem(id: uuid(), title: suggestion.title, note: suggestion.note)
    }
  }

  private static func updateServeWith(
    _ items: [ServeWithItem],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    let data = try ServeWithCoding.encode(items)
    try Recipe.find(recipeID).update {
      $0.serveWith = data
      $0.dateModified = now
    }
    .execute(db)
  }
}

private func enrichmentPrompt(
  selection: String,
  messages: [RecipeChatMessage],
  context: String,
  task: String
) -> String {
  let conversation = messages.isEmpty
    ? "(No conversation yet.)"
    : messages.map { "\($0.role.promptLabel): \($0.text)" }.joined(separator: "\n")
  return """
    Recipe context:
    \(context)

    User-selected subject:
    \(selection)

    Conversation so far:
    \(conversation)

    \(task)
    """
}

private func jsonObject(_ text: String) -> [String: Any]? {
  guard
    let open = text.firstIndex(of: "{"),
    let close = text.lastIndex(of: "}"),
    open < close,
    let data = String(text[open...close]).data(using: .utf8)
  else { return nil }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private extension RecipeChatMessage.Role {
  var promptLabel: String {
    switch self {
    case .user: "User"
    case .assistant: "Assistant"
    }
  }
}

private extension String {
  var editableReviewLines: [String] {
    components(separatedBy: .newlines)
      .map(\.cleanedEditableReviewLine)
      .filter { !$0.isEmpty }
  }

  var cleanedEditableReviewLine: String {
    var line = trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
      line.removeFirst(2)
    } else if line.hasPrefix("• ") {
      line.removeFirst(2)
    } else if let periodIndex = line.firstIndex(of: ".") {
      let prefix = line[..<periodIndex]
      if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
        line = String(line[line.index(after: periodIndex)...])
      }
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedEnrichmentText: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyEnrichmentText
  }

  var nonEmptyEnrichmentText: String? {
    isEmpty ? nil : self
  }
}
