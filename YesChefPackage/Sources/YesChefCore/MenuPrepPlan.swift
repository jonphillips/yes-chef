import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public struct PrepPlanStep: Codable, Equatable, Sendable {
  public var when: String
  public var task: String
  public var sourceDish: MenuItem.ID?

  public init(when: String, task: String, sourceDish: MenuItem.ID? = nil) {
    self.when = when
    self.task = task
    self.sourceDish = sourceDish
  }
}

public struct MenuPrepPlan: Equatable, Sendable {
  public var steps: [PrepPlanStep]

  public init(steps: [PrepPlanStep] = []) {
    self.steps = steps
  }

  public func rendered() -> String {
    steps
      .map { "\($0.when): \($0.task)" }
      .joined(separator: "\n")
  }
}

public enum MenuPrepPlanCoding {
  public static func encode(_ steps: [PrepPlanStep]) throws -> Data? {
    guard !steps.isEmpty else { return nil }
    return try JSONEncoder().encode(steps)
  }

  public static func decode(_ data: Data?) -> [PrepPlanStep] {
    guard let data else { return [] }
    return (try? JSONDecoder().decode([PrepPlanStep].self, from: data)) ?? []
  }
}

public struct MenuPrepPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> MenuPrepPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> MenuPrepPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> MenuPrepPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension MenuPrepPlanClient: DependencyKey {
  public static let liveValue = MenuPrepPlanClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 2048,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.makeAheadPrepPlan.rawValue
    )
    let response = try await modelClient.complete(request)
    return parse(response.text)
  }

  public static let testValue = MenuPrepPlanClient { _, _, _, _ in
    MenuPrepPlan()
  }

  static let instructions = """
    You refine a staged prep plan for one multi-day menu from the current menu context and conversation.
    Return ONLY strict JSON:
    {"steps":[{"when":"relative timing label","task":"concrete kitchen task","sourceDish":"menu item UUID or null"}]}.
    The menu context may include a Current prep plan. Treat it as the artifact being edited: preserve useful existing
    steps, apply the user's requested refinements, and return the full proposed replacement plan. Compose and sequence
    the existing per-recipe make-ahead notes from the menu context. Do not invent or rewrite per-dish make-ahead prose.
    Use sourceDish only when the step clearly comes from one menu item ID in the context; use null when a step spans
    dishes or the source is unclear. Return {"steps":[]} when there is no prep plan to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    let conversation = messages.isEmpty
      ? "(No conversation yet.)"
      : messages.map { "\($0.role.promptLabel): \($0.text)" }.joined(separator: "\n")
    return """
      Menu context:
      \(context)

      User-selected subject:
      \(selection)

      Conversation so far:
      \(conversation)

      Refine the menu prep plan into a full replacement JSON object. Use any Current prep plan in the menu context as
      the starting artifact, and use the conversation only when it clarifies the requested edits or sequencing.
      """
  }

  public static func parse(_ text: String) -> MenuPrepPlan {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return MenuPrepPlan() }

    let elements: [[String: Any]]
    if let object = raw as? [String: Any] {
      elements = object["steps"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    return MenuPrepPlan(
      steps: elements.compactMap { element in
        guard
          let when = (element["when"] as? String)?.cleanedPrepPlanText,
          let task = (element["task"] as? String)?.cleanedPrepPlanText
        else { return nil }
        return PrepPlanStep(
          when: when,
          task: task,
          sourceDish: (element["sourceDish"] as? String)
            .flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
      }
    )
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }

  private static func jsonArraySlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close
    else { return nil }
    return String(text[open...close])
  }
}

extension DependencyValues {
  public var menuPrepPlanClient: MenuPrepPlanClient {
    get { self[MenuPrepPlanClient.self] }
    set { self[MenuPrepPlanClient.self] = newValue }
  }
}

extension MenuRepository {
  public static func applyPrepPlan(
    _ plan: MenuPrepPlan,
    to menuID: Menu.ID,
    in db: Database,
    now: Date
  ) throws {
    try updatePrepPlan(MenuPrepPlanCoding.encode(plan.steps), menuID: menuID, in: db, now: now)
  }

  public static func clearPrepPlan(menuID: Menu.ID, in db: Database, now: Date) throws {
    try updatePrepPlan(nil, menuID: menuID, in: db, now: now)
  }

  private static func updatePrepPlan(
    _ prepPlan: Data?,
    menuID: Menu.ID,
    in db: Database,
    now: Date
  ) throws {
    try Menu.find(menuID).update {
      $0.prepPlan = prepPlan
      $0.dateModified = now
    }
    .execute(db)
  }
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
  var cleanedPrepPlanText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
