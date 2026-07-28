import Dependencies
import Foundation
import LLMClientKit

public struct MakeAheadPlan: Equatable, Sendable {
  public var steps: [MakeAheadStep]

  public init(steps: [MakeAheadStep] = []) {
    self.steps = steps
  }

  /// Puts recognized relative timing labels in the cook's actionable order for a committed plan.
  /// Labels outside this small, settled vocabulary deliberately retain their source order at the end.
  public func orderedForDeposit() -> Self {
    Self(
      steps: steps
        .enumerated()
        .sorted { lhs, rhs in
          let lhsRank = MakeAheadTimingRank(label: lhs.element.when)
          let rhsRank = MakeAheadTimingRank(label: rhs.element.when)
          return switch (lhsRank, rhsRank) {
          case let (lhsRank?, rhsRank?):
            lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
          case (.some, nil):
            true
          case (nil, .some):
            false
          case (nil, nil):
            lhs.offset < rhs.offset
          }
        }
        .map(\.element)
    )
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

public enum MakeAheadTiming {
  /// The settled relative-timing vocabulary every make-ahead producer shares — the onboard extractor,
  /// the outboard hand-off, and the stored `Recipe.makeAhead` field — so a preference written into the
  /// one "Make-ahead & Prep Plans" setting reads the same way through every door instead of drifting
  /// into different label sets.
  public static let canonicalLabelList =
    "`Up to N days ahead`, `Day before`, `Night before`, `Morning of`, `Day of`, `N hours ahead`, `N minutes ahead`, or `Before serving`"
}

/// The order is the product decision: earliest available effort through serving time.
private enum MakeAheadTimingRank: Int, Comparable {
  case daysAhead
  case dayBefore
  case nightBefore
  case morningOf
  case dayOf
  case hoursAhead
  case minutesAhead
  case beforeServing

  init?(label: String) {
    let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.contains("day ahead") || normalized.contains("days ahead") {
      self = .daysAhead
    } else if normalized.contains("day before") {
      self = .dayBefore
    } else if normalized.contains("night before") {
      self = .nightBefore
    } else if normalized.contains("morning of") {
      self = .morningOf
    } else if normalized.contains("day of") {
      self = .dayOf
    } else if normalized.contains("hour ahead") || normalized.contains("hours ahead") {
      self = .hoursAhead
    } else if normalized.contains("minute ahead") || normalized.contains("minutes ahead") {
      self = .minutesAhead
    } else if normalized.contains("before serving") {
      self = .beforeServing
    } else {
      return nil
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
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
    let call = ModelCall(
      surface: .recipe,
      task: .makeAhead,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 4096,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.makeAheadPrepPlan.rawValue
    )
    let response = try await call.complete(using: modelClient)
    guard !response.wasTruncated else { throw StructuredModelResponseError.responseTruncated }
    return parse(response.text)
  }

  public static let testValue = MakeAheadPlanClient { _, _, _, _ in
    MakeAheadPlan()
  }

  static let instructions = """
    You distill a cooking conversation into a practical make-ahead plan for one recipe.
    The recipe context and conversation are provided by the app. Return ONLY strict JSON:
    {"steps":[{"when":"short timing label","task":"concrete kitchen task","why":"optional brief reason"}]}.
    Set each `when` to exactly one settled label: \(MakeAheadTiming.canonicalLabelList). Replace N with a number.
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
