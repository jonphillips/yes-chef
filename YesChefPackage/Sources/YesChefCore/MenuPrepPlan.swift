import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public struct PrepPlanStep: Codable, Equatable, Sendable {
  public var session: String
  public var task: String
  public var serves: String?
  public var sourceDish: MenuItem.ID?

  public init(
    session: String,
    task: String,
    serves: String? = nil,
    sourceDish: MenuItem.ID? = nil
  ) {
    self.session = session
    self.task = task
    self.serves = serves
    self.sourceDish = sourceDish
  }

  private enum CodingKeys: String, CodingKey {
    case session
    case when
    case task
    case serves
    case sourceDish
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    session = try container.decodeIfPresent(String.self, forKey: .session)
      ?? container.decode(String.self, forKey: .when)
    task = try container.decode(String.self, forKey: .task)
    serves = try container.decodeIfPresent(String.self, forKey: .serves)
    sourceDish = try container.decodeIfPresent(MenuItem.ID.self, forKey: .sourceDish)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(session, forKey: .session)
    try container.encode(task, forKey: .task)
    try container.encodeIfPresent(serves, forKey: .serves)
    try container.encodeIfPresent(sourceDish, forKey: .sourceDish)
  }
}

public struct MenuPrepPlan: Equatable, Sendable {
  public var steps: [PrepPlanStep]

  public init(steps: [PrepPlanStep] = []) {
    self.steps = steps
  }

  public func rendered() -> String {
    editableReviewText()
  }

  public func editableReviewText() -> String {
    var lines: [String] = []
    var previousSession: String?
    for step in steps {
      if step.session != previousSession {
        lines.append("\(step.session):")
        previousSession = step.session
      }
      lines.append("- \(step.renderedEditableReviewLine)")
    }
    return lines.joined(separator: "\n")
  }

  public func applyingEditableReviewText(_ text: String) -> MenuPrepPlan {
    var sourceDishesByLine = Dictionary(grouping: steps) { $0.editableReviewKey }
      .mapValues { steps in steps.map(\.sourceDish) }
    var session: String?
    var revisedSteps: [PrepPlanStep] = []

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.cleanedEditablePrepPlanLine
      guard !line.isEmpty else { continue }

      if rawLine.isEditablePrepPlanSessionHeader, let parsedSession = line.editablePrepPlanSession {
        session = parsedSession
        continue
      }

      guard let session, let parsedLine = PrepPlanStep.editableReviewLine(line) else { continue }
      let reviewKey = PrepPlanStep(
        session: session,
        task: parsedLine.task,
        serves: parsedLine.serves
      )
      .editableReviewKey
      revisedSteps.append(
        PrepPlanStep(
          session: session,
          task: parsedLine.task,
          serves: parsedLine.serves,
          sourceDish: Self.popSourceDish(for: reviewKey, from: &sourceDishesByLine)
        )
      )
    }

    return MenuPrepPlan(
      steps: revisedSteps
    )
  }

  private static func popSourceDish(
    for line: String,
    from sourceDishesByLine: inout [String: [MenuItem.ID?]]
  ) -> MenuItem.ID? {
    guard var sourceDishes = sourceDishesByLine[line], !sourceDishes.isEmpty else { return nil }
    let sourceDish = sourceDishes.removeFirst()
    sourceDishesByLine[line] = sourceDishes
    return sourceDish
  }
}

private extension PrepPlanStep {
  var renderedEditableReviewLine: String {
    guard let serves else { return task }
    return "\(task) → \(serves)"
  }

  var editableReviewKey: String {
    "\(session)\n\(renderedEditableReviewLine)"
  }

  static func editableReviewLine(_ line: String) -> (task: String, serves: String?)? {
    let pieces = line.split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false)
    guard let task = String(pieces[0]).cleanedPrepPlanText else { return nil }
    guard pieces.count == 2 else { return (task, nil) }
    guard let serves = String(pieces[1]).cleanedPrepPlanText else { return nil }
    return (task, serves)
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
    You weave a staged prep plan for one multi-day menu from the current menu context and conversation.
    Return ONLY strict JSON:
    {"steps":[{"session":"work-session label","task":"concrete kitchen task","serves":"human-readable meal or day this feeds, or null","sourceDish":"menu item UUID or null"}]}.
    The menu context may include a Current prep plan. Treat it as the artifact being edited: preserve useful existing
    steps, apply the user's requested refinements, and return the full proposed replacement plan. Compose from stored
    per-recipe Make-Ahead notes when present, and invent grounded sequencing, work sessions, and new prep steps from
    the menu's dishes and conversation. Prefer the authored Make-Ahead notes when they are available.
    Group related work under free-form session labels such as "Anytime, get ahead" or "Wednesday evening". Set serves
    to the meal or day each step feeds when useful.
    Use sourceDish only when the step clearly comes from one menu item ID in the context; use null when a step spans
    dishes or the source is unclear. Return {"steps":[]} only when there is genuinely no prep plan to save.
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
          let session = (element["session"] as? String)?.cleanedPrepPlanText,
          let task = (element["task"] as? String)?.cleanedPrepPlanText
        else { return nil }
        return PrepPlanStep(
          session: session,
          task: task,
          serves: (element["serves"] as? String)?.cleanedPrepPlanText,
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
  var cleanedEditablePrepPlanLine: String {
    var line = trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
      line.removeFirst(2)
    } else if line.hasPrefix("• ") {
      line.removeFirst(2)
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedPrepPlanText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var editablePrepPlanSession: String? {
    guard hasSuffix(":") else { return nil }
    return String(dropLast()).cleanedPrepPlanText
  }

  var isEditablePrepPlanSessionHeader: Bool {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.hasPrefix("- ")
      && !trimmed.hasPrefix("* ")
      && !trimmed.hasPrefix("• ")
      && trimmed.hasSuffix(":")
  }
}
