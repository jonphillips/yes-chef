import Dependencies
import Foundation
import LLMClientKit

public struct MealPlanComplementPlan: Equatable, Sendable {
  public var items: [MealPlanComplementSuggestion]

  public init(items: [MealPlanComplementSuggestion] = []) {
    self.items = items
  }
}

public struct MealPlanComplementSuggestion: Equatable, Sendable {
  public var kind: MealPlanItemKind
  public var title: String
  public var mealSlot: MealPlanItemSlot

  public init(
    kind: MealPlanItemKind = .note,
    title: String,
    mealSlot: MealPlanItemSlot
  ) {
    self.kind = kind
    self.title = title
    self.mealSlot = mealSlot
  }

  public func rendered(dayTitle: String) -> String {
    """
    Note: \(title)
    \(dayTitle) - \(mealSlot.title)
    """
  }

  public func editableReviewText(dayTitle: String) -> String {
    rendered(dayTitle: dayTitle)
  }

  public func applyingEditableReviewText(_ text: String) -> MealPlanComplementSuggestion {
    let lines = text.editableMealPlanComplementLines
    var suggestion = self

    if let titleLine = lines.first {
      suggestion.kind = Self.kind(fromEditableReviewTitleLine: titleLine) ?? suggestion.kind
      suggestion.title = Self.title(fromEditableReviewTitleLine: titleLine) ?? suggestion.title
    }
    if let placementLine = lines.dropFirst().first {
      suggestion.mealSlot = Self.mealSlot(fromEditableReviewPlacementLine: placementLine) ?? suggestion.mealSlot
    }

    return suggestion
  }

  private static func kind(fromEditableReviewTitleLine line: String) -> MealPlanItemKind? {
    guard let label = line.split(separator: ":", maxSplits: 1).first else { return nil }
    let normalized = String(label).normalizedMealPlanComplementEnumValue
    return MealPlanItemKind.allCases.first {
      $0.rawValue == normalized || $0.title.normalizedMealPlanComplementEnumValue == normalized
    }
  }

  private static func title(fromEditableReviewTitleLine line: String) -> String? {
    let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    return String(pieces.count > 1 ? pieces[1] : pieces[0]).cleanedMealPlanComplementText
  }

  private static func mealSlot(fromEditableReviewPlacementLine line: String) -> MealPlanItemSlot? {
    guard let slotText = line.components(separatedBy: " - ").last?.cleanedMealPlanComplementText else { return nil }
    return MealPlanItemSlot.allCases.first {
      $0.rawValue == slotText.normalizedMealPlanComplementEnumValue
        || $0.title.normalizedMealPlanComplementEnumValue == slotText.normalizedMealPlanComplementEnumValue
    }
  }
}

public struct MealPlanComplementClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> MealPlanComplementPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> MealPlanComplementPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> MealPlanComplementPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension MealPlanComplementClient: DependencyKey {
  public static let liveValue = MealPlanComplementClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .mealPlan,
      task: .complement,
      tierResolution: .callerProvided,
      contextLayers: [.mealPlan, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 1536,
      reasoningEffort: .medium,
      promptPreferenceKey: AIPromptPreferenceKind.complements.rawValue
    )
    let response = try await call.complete(using: modelClient)
    return parse(response.text)
  }

  public static let testValue = MealPlanComplementClient { _, _, _, _ in
    MealPlanComplementPlan()
  }

  static let instructions = """
    You distill a cooking conversation into concrete dish suggestions that complement one meal plan day.
    Return ONLY strict JSON:
    {"items":[{"kind":"note","title":"short dish name","mealSlot":"dinner"}]}.
    Allowed kind values are "note" and "recipe"; use "note" for freeform suggested dishes that are not already
    represented by an existing recipe row. The date is fixed by the meal plan context; do not invent or return
    dates. Allowed mealSlot values are "breakfast", "lunch", "dinner", and "snack".
    Return {"items":[]} when there is no concrete dish to add.
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

      Distill the selected subject into meal plan item suggestions that would complement the fixed meal plan day.
      Choose only the meal slot for each suggestion; the app will insert every accepted item on the context date.
      """
  }

  public static func parse(_ text: String) -> MealPlanComplementPlan {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return MealPlanComplementPlan() }

    let elements: [[String: Any]]
    if let object = raw as? [String: Any] {
      elements = object["items"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    return MealPlanComplementPlan(
      items: elements.compactMap { element in
        guard
          let title = (element["title"] as? String)?.cleanedMealPlanComplementText,
          let mealSlot = (element["mealSlot"] as? String).flatMap(MealPlanItemSlot.init(mealPlanComplementRawValue:))
        else { return nil }

        return MealPlanComplementSuggestion(
          kind: .note,
          title: title,
          mealSlot: mealSlot
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
  public var mealPlanComplementClient: MealPlanComplementClient {
    get { self[MealPlanComplementClient.self] }
    set { self[MealPlanComplementClient.self] = newValue }
  }
}

private extension MealPlanItemSlot {
  init?(mealPlanComplementRawValue: String) {
    self.init(rawValue: mealPlanComplementRawValue.normalizedMealPlanComplementEnumValue)
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
  var editableMealPlanComplementLines: [String] {
    components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var cleanedMealPlanComplementText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var normalizedMealPlanComplementEnumValue: String {
    trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
