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
}

public struct ServeWithSuggestion: Equatable, Sendable {
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
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 2048
    )
    let response = try await modelClient.complete(request)
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
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 2048
    )
    let response = try await modelClient.complete(request)
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

  private static func updateChefItUp(
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
  var cleanedEnrichmentText: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyEnrichmentText
  }

  var nonEmptyEnrichmentText: String? {
    isEmpty ? nil : self
  }
}
