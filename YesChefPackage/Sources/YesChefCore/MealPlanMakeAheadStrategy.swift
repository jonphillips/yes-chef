import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public struct MealPlanMakeAheadStrategy: Equatable, Sendable {
  public var title: String
  public var mealSlot: MealPlanItemSlot
  public var steps: [MealPlanMakeAheadStep]

  public init(
    title: String = "Make-ahead strategy",
    mealSlot: MealPlanItemSlot = .dinner,
    steps: [MealPlanMakeAheadStep] = []
  ) {
    self.title = title
    self.mealSlot = mealSlot
    self.steps = steps
  }

  public func rendered() -> String {
    guard !steps.isEmpty else { return "" }
    var lines = ["\(title) - \(mealSlot.title)"]
    lines.append(contentsOf: steps.map(\.rendered))
    return lines.joined(separator: "\n")
  }

  public func renderedNotes() -> String {
    steps.map(\.rendered).joined(separator: "\n")
  }

  public func editableReviewText() -> String {
    rendered()
  }

  public func applyingEditableReviewText(_ text: String) -> MealPlanMakeAheadStrategy {
    Self.parsingEditableReviewText(text, preservingSourceItemsFrom: self).strategy
  }

  public struct EditableReviewParseResult: Equatable, Sendable {
    public var strategy: MealPlanMakeAheadStrategy
    public var unparsedLines: [String]

    public init(strategy: MealPlanMakeAheadStrategy, unparsedLines: [String]) {
      self.strategy = strategy
      self.unparsedLines = unparsedLines
    }
  }

  /// Preserves every non-empty review line by reporting lines that cannot be represented as a strategy step.
  /// The caller must surface or reject those lines rather than silently dropping human edits.
  public static func parsingEditableReviewText(
    _ text: String,
    preservingSourceItemsFrom existing: MealPlanMakeAheadStrategy = MealPlanMakeAheadStrategy()
  ) -> EditableReviewParseResult {
    let lines = text.editableMealPlanMakeAheadLines
    guard let titleLine = lines.first else {
      return EditableReviewParseResult(strategy: MealPlanMakeAheadStrategy(), unparsedLines: [])
    }
    var sourceItemsByLine = Dictionary(grouping: existing.steps) { $0.rendered }
      .mapValues { steps in steps.map(\.sourceItem) }
    var unparsedLines: [String] = []
    let steps = lines.dropFirst().compactMap { line -> MealPlanMakeAheadStep? in
      guard let parsedLine = MealPlanMakeAheadStep.editableReviewLine(line) else {
        unparsedLines.append(line)
        return nil
      }
      return MealPlanMakeAheadStep(
        when: parsedLine.when,
        task: parsedLine.task,
        sourceItem: Self.popSourceItem(for: line, from: &sourceItemsByLine)
      )
    }
    return EditableReviewParseResult(
      strategy: MealPlanMakeAheadStrategy(
        title: Self.title(fromEditableReviewTitleLine: titleLine) ?? existing.title,
        mealSlot: Self.mealSlot(fromEditableReviewTitleLine: titleLine) ?? existing.mealSlot,
        steps: steps
      ),
      unparsedLines: unparsedLines
    )
  }

  private static func title(fromEditableReviewTitleLine line: String) -> String? {
    line.components(separatedBy: " - ").first?.cleanedMealPlanMakeAheadText
  }

  private static func mealSlot(fromEditableReviewTitleLine line: String) -> MealPlanItemSlot? {
    guard let slotText = line.components(separatedBy: " - ").last?.cleanedMealPlanMakeAheadText else { return nil }
    return MealPlanItemSlot.allCases.first {
      $0.rawValue == slotText.normalizedMealPlanMakeAheadEnumValue
        || $0.title.normalizedMealPlanMakeAheadEnumValue == slotText.normalizedMealPlanMakeAheadEnumValue
    }
  }

  private static func popSourceItem(
    for line: String,
    from sourceItemsByLine: inout [String: [String?]]
  ) -> String? {
    guard var sourceItems = sourceItemsByLine[line], !sourceItems.isEmpty else { return nil }
    let sourceItem = sourceItems.removeFirst()
    sourceItemsByLine[line] = sourceItems
    return sourceItem
  }
}

public struct MealPlanMakeAheadStep: Equatable, Sendable {
  public var when: String
  public var task: String
  // Latent provenance: the meal plan item ID this step came from. Parsed and retained but not yet
  // rendered — kept for a future reconcile-against-day-items pass, so raw IDs never reach note text.
  public var sourceItem: String?

  public init(when: String, task: String, sourceItem: String? = nil) {
    self.when = when
    self.task = task
    self.sourceItem = sourceItem
  }

  public var rendered: String {
    "\(when): \(task)"
  }

  fileprivate static func editableReviewLine(_ line: String) -> (when: String, task: String)? {
    let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard
      pieces.count == 2,
      let when = String(pieces[0]).cleanedMealPlanMakeAheadText,
      let task = String(pieces[1]).cleanedMealPlanMakeAheadText
    else { return nil }
    return (when, task)
  }
}

public struct MealPlanMakeAheadStrategyClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> MealPlanMakeAheadStrategy

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> MealPlanMakeAheadStrategy
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> MealPlanMakeAheadStrategy {
    try await extract(selection, messages, context, tier)
  }
}

extension MealPlanMakeAheadStrategyClient: DependencyKey {
  public static let liveValue = MealPlanMakeAheadStrategyClient { selection, messages, context, tier in
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

  public static let testValue = MealPlanMakeAheadStrategyClient { _, _, _, _ in
    MealPlanMakeAheadStrategy()
  }

  static let instructions = """
    You distill a cooking conversation into a day-scoped make-ahead strategy for one meal plan day.
    Return ONLY strict JSON:
    {"title":"Make-ahead strategy","mealSlot":"dinner","steps":[{"when":"relative timing label","task":"concrete kitchen task","sourceItem":"meal plan item ID or null"}]}.
    Emit separable, atomic, context-free tasks that stand on their own. Do not generate choreography: never
    interleave recipe instructions, coordinate concurrent cooking, or turn the strategy into a merged mega-recipe.
    The recipes hold the cooking. Select distinct prep tasks grounded in the day's recipes. Lean on existing recipe
    make-ahead notes from the meal plan context when present. Do not flatten multiple recipes into one blob, do not
    rewrite entire recipes, and do not invent per-recipe make-ahead prose. Use sourceItem only when the step clearly
    comes from one meal plan item ID in the context; use null when the step spans items or the source is unclear. The
    date is fixed by the meal plan context; do not invent or return dates. Allowed mealSlot values are "breakfast",
    "lunch", "dinner", and "snack". Return {"steps":[]} when there is no strategy to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    let conversation = messages.isEmpty
      ? "(No conversation yet.)"
      : messages.map { "\($0.role.promptLabel): \($0.text)" }.joined(separator: "\n")
    return """
      Meal plan day context:
      \(context)

      User-selected subject:
      \(selection)

      Conversation so far:
      \(conversation)

      Distill the selected subject into one day-level make-ahead strategy note. Use the conversation only as
      background when it clarifies concrete prep tasks already grounded in the meal plan day.
      """
  }

  public static func parse(_ text: String) -> MealPlanMakeAheadStrategy {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return MealPlanMakeAheadStrategy() }

    let object = raw as? [String: Any]
    let elements: [[String: Any]]
    if let object {
      elements = object["steps"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    let title = (object?["title"] as? String)?.cleanedMealPlanMakeAheadText ?? "Make-ahead strategy"
    let mealSlot = (object?["mealSlot"] as? String)
      .flatMap(MealPlanItemSlot.init(mealPlanMakeAheadRawValue:)) ?? .dinner

    return MealPlanMakeAheadStrategy(
      title: title,
      mealSlot: mealSlot,
      steps: elements.compactMap { element in
        guard
          let when = (element["when"] as? String)?.cleanedMealPlanMakeAheadText,
          let task = (element["task"] as? String)?.cleanedMealPlanMakeAheadText
        else { return nil }
        return MealPlanMakeAheadStep(
          when: when,
          task: task,
          sourceItem: (element["sourceItem"] as? String)?.cleanedMealPlanMakeAheadText
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
  public var mealPlanMakeAheadStrategyClient: MealPlanMakeAheadStrategyClient {
    get { self[MealPlanMakeAheadStrategyClient.self] }
    set { self[MealPlanMakeAheadStrategyClient.self] = newValue }
  }
}

extension MealCalendarRepository {
  @discardableResult
  public static func addMakeAheadStrategyNote(
    _ strategy: MealPlanMakeAheadStrategy,
    on scheduledDate: Date,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MealPlanItem.ID {
    guard !strategy.steps.isEmpty else {
      throw MealCalendarRepositoryError.emptyMakeAheadStrategy
    }
    return try addNoteItem(
      title: strategy.title,
      notes: strategy.renderedNotes(),
      on: scheduledDate,
      mealSlot: strategy.mealSlot,
      in: db,
      now: now,
      uuid: uuid
    )
  }
}

private extension MealPlanItemSlot {
  init?(mealPlanMakeAheadRawValue: String) {
    self.init(rawValue: mealPlanMakeAheadRawValue.normalizedMealPlanMakeAheadEnumValue)
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
  var editableMealPlanMakeAheadLines: [String] {
    components(separatedBy: .newlines)
      .map(\.cleanedEditableMealPlanMakeAheadLine)
      .filter { !$0.isEmpty }
  }

  var cleanedEditableMealPlanMakeAheadLine: String {
    var line = trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
      line.removeFirst(2)
    } else if line.hasPrefix("• ") {
      line.removeFirst(2)
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedMealPlanMakeAheadText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var normalizedMealPlanMakeAheadEnumValue: String {
    trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
