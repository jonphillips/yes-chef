import Dependencies
import Foundation
import LLMClientKit

public struct MakeAheadPlan: Equatable, Sendable {
  public var steps: [MakeAheadStep]

  public init(steps: [MakeAheadStep] = []) {
    self.steps = steps
  }

  public func rendered() -> String {
    steps
      .map { step in
        var lines = ["\(step.when): \(step.task)"]
        if let why = step.why {
          lines.append("Why: \(why)")
        }
        return lines.joined(separator: "\n")
      }
      .joined(separator: "\n\n")
  }
}

public struct MakeAheadStep: Equatable, Sendable, Identifiable {
  public var when: String
  public var task: String
  public var why: String?

  public var id: String { "\(when)|\(task)|\(why ?? "")" }

  public init(when: String, task: String, why: String? = nil) {
    self.when = when
    self.task = task
    self.why = why
  }
}

public struct MakeAheadPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> MakeAheadPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> MakeAheadPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> MakeAheadPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension MakeAheadPlanClient: DependencyKey {
  public static let liveValue = MakeAheadPlanClient { selection, messages, context, tier in
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

  public static let testValue = MakeAheadPlanClient { _, _, _, _ in
    MakeAheadPlan()
  }

  static let instructions = """
    You distill a cooking conversation into a practical make-ahead plan for one recipe.
    The recipe context and conversation are provided by the app. Return ONLY strict JSON:
    {"steps":[{"when":"short timing label","task":"concrete kitchen task","why":"optional brief reason"}]}.
    Use only the provided recipe and conversation. Do not invent storage times or food-safety claims.
    Prefer a short, useful plan. Return {"steps":[]} when there is no make-ahead strategy to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
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

      Distill the selected subject into the make-ahead JSON object. Use the conversation only as background
      when it clarifies what the selected subject means.
      """
  }

  public static func parse(_ text: String) -> MakeAheadPlan {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return MakeAheadPlan() }

    let elements: [[String: Any]]
    if let object = raw as? [String: Any] {
      elements = object["steps"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    return MakeAheadPlan(
      steps: elements.compactMap { element in
        guard
          let when = (element["when"] as? String)?.cleanedMakeAheadText,
          let task = (element["task"] as? String)?.cleanedMakeAheadText
        else { return nil }
        return MakeAheadStep(
          when: when,
          task: task,
          why: (element["why"] as? String)?.cleanedMakeAheadText
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
  public var makeAheadPlanClient: MakeAheadPlanClient {
    get { self[MakeAheadPlanClient.self] }
    set { self[MakeAheadPlanClient.self] = newValue }
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
  var cleanedMakeAheadText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
