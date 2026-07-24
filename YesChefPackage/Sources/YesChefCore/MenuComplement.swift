import Dependencies
import Foundation
import LLMClientKit

public struct MenuComplementPlan: Equatable, Sendable {
  public var items: [MenuComplementSuggestion]

  public init(items: [MenuComplementSuggestion] = []) {
    self.items = items
  }
}

public struct MenuComplementHandoffParseResult: Equatable, Sendable {
  public var plan: MenuComplementPlan
  public var unparsedBlocks: [String]

  public init(plan: MenuComplementPlan, unparsedBlocks: [String]) {
    self.plan = plan
    self.unparsedBlocks = unparsedBlocks
  }
}

public struct MenuComplementSuggestion: Equatable, Sendable {
  public var kind: MealPlanItemKind
  public var title: String
  /// The ingredient/spice/method detail for this one dish, stored into `MenuItem.notes` on commit
  /// (ADR-0012 Amendment 2). `nil` when the model returned only a dish name.
  public var body: String?
  public var dayOffset: Int
  public var mealSlot: MealPlanItemSlot

  public init(
    kind: MealPlanItemKind = .note,
    title: String,
    body: String? = nil,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot
  ) {
    self.kind = kind
    self.title = title
    self.body = body
    self.dayOffset = dayOffset
    self.mealSlot = mealSlot
  }

  public func rendered() -> String {
    var text = """
      \(kind.title): \(title)
      Day \(dayOffset + 1) - \(mealSlot.title)
      """
    if let body = body?.cleanedMenuComplementText {
      text += "\n\(body)"
    }
    return text
  }

  public func editableReviewText() -> String {
    rendered()
  }

  public func applyingEditableReviewText(_ text: String) -> MenuComplementSuggestion {
    let lines = text.editableMenuComplementLines
    var suggestion = self

    if let titleLine = lines.first {
      suggestion.kind = Self.kind(fromEditableReviewTitleLine: titleLine) ?? suggestion.kind
      suggestion.title = Self.title(fromEditableReviewTitleLine: titleLine) ?? suggestion.title
    }
    if let placementLine = lines.dropFirst().first {
      suggestion.dayOffset = Self.dayOffset(fromEditableReviewPlacementLine: placementLine) ?? suggestion.dayOffset
      suggestion.mealSlot = Self.mealSlot(fromEditableReviewPlacementLine: placementLine) ?? suggestion.mealSlot
    }
    // Everything after the title + placement lines is the editable ingredient/detail body.
    suggestion.body = lines.dropFirst(2).joined(separator: "\n").cleanedMenuComplementText

    return suggestion
  }

  private static func kind(fromEditableReviewTitleLine line: String) -> MealPlanItemKind? {
    guard let label = line.split(separator: ":", maxSplits: 1).first else { return nil }
    let normalized = String(label).normalizedMenuComplementEnumValue
    return MealPlanItemKind.allCases.first {
      $0.rawValue == normalized || $0.title.normalizedMenuComplementEnumValue == normalized
    }
  }

  private static func title(fromEditableReviewTitleLine line: String) -> String? {
    let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    return String(pieces.count > 1 ? pieces[1] : pieces[0]).cleanedMenuComplementText
  }

  private static func dayOffset(fromEditableReviewPlacementLine line: String) -> Int? {
    guard let dayText = line.components(separatedBy: " - ").first?.cleanedMenuComplementText else { return nil }
    let normalized = dayText.normalizedMenuComplementEnumValue
    guard normalized.hasPrefix("day ") else { return nil }
    let numberText = normalized.dropFirst("day ".count).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let dayNumber = Int(numberText), dayNumber > 0 else { return nil }
    return dayNumber - 1
  }

  private static func mealSlot(fromEditableReviewPlacementLine line: String) -> MealPlanItemSlot? {
    guard let slotText = line.components(separatedBy: " - ").last?.cleanedMenuComplementText else { return nil }
    return MealPlanItemSlot.allCases.first {
      $0.rawValue == slotText.normalizedMenuComplementEnumValue
        || $0.title.normalizedMenuComplementEnumValue == slotText.normalizedMenuComplementEnumValue
    }
  }
}

public extension MenuComplementPlan {
  /// Parses the deliberately human-editable external hand-off shape. Each
  /// suggestion is a separate blank-line-delimited block so the reviewer can
  /// accept, edit, or reject it independently before a menu write.
  static func parsingHandoffText(_ text: String, dayCount: Int) -> MenuComplementHandoffParseResult {
    let blocks = text
      .components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var items: [MenuComplementSuggestion] = []
    var unparsedBlocks: [String] = []
    for block in blocks {
      let lines = block.editableMenuComplementLines
      guard lines.count >= 2,
        let suggestion = handoffSuggestion(titleLine: lines[0], placementLine: lines[1], bodyLines: lines.dropFirst(2), dayCount: dayCount)
      else {
        unparsedBlocks.append(block)
        continue
      }
      items.append(suggestion)
    }
    return MenuComplementHandoffParseResult(plan: MenuComplementPlan(items: items), unparsedBlocks: unparsedBlocks)
  }

  private static func handoffSuggestion(
    titleLine: String,
    placementLine: String,
    bodyLines: ArraySlice<String>,
    dayCount: Int
  ) -> MenuComplementSuggestion? {
    guard let title = titleLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
      .map(String.init)?.cleanedMenuComplementText,
      let dayText = placementLine.components(separatedBy: " - ").first?.cleanedMenuComplementText,
      dayText.normalizedMenuComplementEnumValue.hasPrefix("day "),
      let dayNumber = Int(dayText.normalizedMenuComplementEnumValue.dropFirst("day ".count)),
      (1...dayCount).contains(dayNumber),
      let slotText = placementLine.components(separatedBy: " - ").last?.cleanedMenuComplementText,
      let mealSlot = MealPlanItemSlot.allCases.first(where: {
        $0.rawValue == slotText.normalizedMenuComplementEnumValue
          || $0.title.normalizedMenuComplementEnumValue == slotText.normalizedMenuComplementEnumValue
      })
    else { return nil }

    return MenuComplementSuggestion(
      title: title,
      body: bodyLines.joined(separator: "\n").cleanedMenuComplementText,
      dayOffset: dayNumber - 1,
      mealSlot: mealSlot
    )
  }
}

public struct MenuComplementClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> MenuComplementPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> MenuComplementPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> MenuComplementPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension MenuComplementClient: DependencyKey {
  public static let liveValue = MenuComplementClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .menu,
      task: .complement,
      tierResolution: .callerProvided,
      contextLayers: [.menu, .selection, .conversation],
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

  public static let testValue = MenuComplementClient { _, _, _, _ in
    MenuComplementPlan()
  }

  static let instructions = """
    You distill a cooking conversation into concrete dish suggestions that complement one menu.
    Return ONLY strict JSON:
    {"items":[{"kind":"note","title":"short dish name","body":"ingredients and method detail","dayOffset":0,"mealSlot":"dinner"}]}.
    Allowed kind values are "note" and "recipe"; use "note" for freeform suggested dishes that are not already
    represented by an existing recipe row. "body" holds the ingredient/spice/method detail for that one dish
    (omit it or use "" when there is no detail beyond the name). dayOffset is zero-based and must be valid for
    the menu context. Allowed mealSlot values are "breakfast", "lunch", "dinner", and "snack".
    Return {"items":[]} when there is no concrete dish to add.
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

      Distill the selected subject into menu-item suggestions that would complement the existing menu.
      """
  }

  public static func parse(_ text: String) -> MenuComplementPlan {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return MenuComplementPlan() }

    let elements: [[String: Any]]
    if let object = raw as? [String: Any] {
      elements = object["items"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    return MenuComplementPlan(
      items: elements.compactMap { element in
        guard
          let title = (element["title"] as? String)?.cleanedMenuComplementText,
          let dayOffset = element["dayOffset"] as? Int,
          let mealSlot = (element["mealSlot"] as? String).flatMap(MealPlanItemSlot.init(menuComplementRawValue:))
        else { return nil }

        return MenuComplementSuggestion(
          kind: .note,
          title: title,
          body: (element["body"] as? String)?.cleanedMenuComplementText,
          dayOffset: dayOffset,
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
  public var menuComplementClient: MenuComplementClient {
    get { self[MenuComplementClient.self] }
    set { self[MenuComplementClient.self] = newValue }
  }
}

private extension MealPlanItemSlot {
  init?(menuComplementRawValue: String) {
    self.init(rawValue: menuComplementRawValue.normalizedMenuComplementEnumValue)
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
  var editableMenuComplementLines: [String] {
    components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var cleanedMenuComplementText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var normalizedMenuComplementEnumValue: String {
    trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
