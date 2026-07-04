import Dependencies
import Foundation
import LLMClientKit

public struct MenuComplementPlan: Equatable, Sendable {
  public var items: [MenuComplementSuggestion]

  public init(items: [MenuComplementSuggestion] = []) {
    self.items = items
  }
}

public struct MenuComplementSuggestion: Equatable, Sendable {
  public var kind: MealPlanItemKind
  public var title: String
  public var dayOffset: Int
  public var mealSlot: MealPlanItemSlot

  public init(
    kind: MealPlanItemKind = .note,
    title: String,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot
  ) {
    self.kind = kind
    self.title = title
    self.dayOffset = dayOffset
    self.mealSlot = mealSlot
  }

  public func rendered() -> String {
    """
    \(kind.title): \(title)
    Day \(dayOffset + 1) - \(mealSlot.title)
    """
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
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 1536
    )
    let response = try await modelClient.complete(request)
    return parse(response.text)
  }

  public static let testValue = MenuComplementClient { _, _, _, _ in
    MenuComplementPlan()
  }

  static let instructions = """
    You distill a cooking conversation into concrete dish suggestions that complement one menu.
    Return ONLY strict JSON:
    {"items":[{"kind":"note","title":"short dish name","dayOffset":0,"mealSlot":"dinner"}]}.
    Allowed kind values are "note" and "recipe"; use "note" for freeform suggested dishes that are not already
    represented by an existing recipe row. dayOffset is zero-based and must be valid for the menu context.
    Allowed mealSlot values are "breakfast", "lunch", "dinner", and "snack".
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

        let kind = (element["kind"] as? String)
          .flatMap(MealPlanItemKind.init(menuComplementRawValue:))
          .flatMap { $0 == .reservation ? nil : $0 }
          ?? .note

        return MenuComplementSuggestion(
          kind: kind,
          title: title,
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

private extension MealPlanItemKind {
  init?(menuComplementRawValue: String) {
    self.init(rawValue: menuComplementRawValue.normalizedMenuComplementEnumValue)
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
  var cleanedMenuComplementText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var normalizedMenuComplementEnumValue: String {
    trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
