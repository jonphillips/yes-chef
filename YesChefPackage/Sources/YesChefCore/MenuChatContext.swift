import Dependencies
import Foundation
import LLMClientKit

public struct MenuChatContext: Equatable, Sendable {
  public static let defaultIngredientLimit = 8
  public static let onDeviceSerializedCharacterBudget = 12_000
  public static let frontierSerializedCharacterBudget = 120_000
  public static let serializedCharacterBudget = onDeviceSerializedCharacterBudget

  public var menuID: Menu.ID?
  public var title: String
  public var notes: String?
  public var dayCount: Int
  public var prepPlan: [PrepPlanStepRecord]
  public var items: [MenuChatItemContext]

  public init(
    menuID: Menu.ID? = nil,
    title: String,
    notes: String? = nil,
    dayCount: Int,
    prepPlan: [PrepPlanStepRecord] = [],
    items: [MenuChatItemContext] = []
  ) {
    self.menuID = menuID
    self.title = title
    self.notes = notes
    self.dayCount = dayCount
    self.prepPlan = prepPlan
    self.items = items
  }

  public init(detail: MenuDetailData) {
    self.init(
      menuID: detail.menu.id,
      title: detail.menu.title,
      notes: detail.menu.notes,
      dayCount: detail.menu.dayCount,
      prepPlan: detail.prepPlanSteps,
      items: detail.itemRows.map(MenuChatItemContext.init(row:))
    )
  }

  public var seededContextDescription: String {
    let budgeted = budgetedSerialization(characterBudget: Self.onDeviceSerializedCharacterBudget)
    guard !budgeted.notes.isEmpty else {
      return "Seeded with menu dish summaries."
    }
    return "Seeded with menu dish summaries. \(budgeted.notes.joined(separator: " "))"
  }

  public func serialized(for tier: ModelTier) -> String {
    serialized(characterBudget: Self.serializedCharacterBudget(for: tier))
  }

  public func prepPrompt() -> String {
    @Dependency(\.aiPromptPreferences) var preferences
    let settings = preferences.current()
    return Self.prepPrompt(
      context: serialized(for: .frontierPreferred),
      tasteProfile: settings.tasteProfile,
      makeAheadPreference: AISettingsRepository.preference(
        in: settings,
        for: .makeAheadPrepPlan
      )
    )
  }

  public func serialized(characterBudget: Int = Self.serializedCharacterBudget) -> String {
    budgetedSerialization(characterBudget: characterBudget).text
  }

  public static func serializedCharacterBudget(for tier: ModelTier) -> Int {
    switch tier {
    case .onDevice:
      onDeviceSerializedCharacterBudget
    case .frontier, .frontierPreferred:
      frontierSerializedCharacterBudget
    }
  }

  private func budgetedSerialization(characterBudget: Int) -> MenuChatSerializedContext {
    let sortedItems = items.sorted(by: areMenuChatItemsInIncreasingOrder)
    let initialIngredientLimit = initialIngredientLimit(
      for: characterBudget,
      items: sortedItems
    )
    if sortedItems.contains(where: { !$0.method.isEmpty }) {
      let candidate = renderedContext(
        items: sortedItems,
        ingredientLimit: initialIngredientLimit,
        makeAheadCharacterLimit: nil,
        includeMethod: true,
        omittedItemCount: 0
      )
      if candidate.text.count <= characterBudget {
        return candidate
      }

      let methodTrimmedCandidate = renderedContext(
        items: sortedItems,
        ingredientLimit: initialIngredientLimit,
        makeAheadCharacterLimit: nil,
        includeMethod: false,
        omittedItemCount: 0
      )
      if methodTrimmedCandidate.text.count <= characterBudget {
        return methodTrimmedCandidate
      }
    }

    for ingredientLimit in stride(from: initialIngredientLimit, through: 0, by: -1) {
      let candidate = renderedContext(
        items: sortedItems,
        ingredientLimit: ingredientLimit,
        makeAheadCharacterLimit: nil,
        includeMethod: false,
        omittedItemCount: 0
      )
      if candidate.text.count <= characterBudget || ingredientLimit == 0 {
        if candidate.text.count <= characterBudget {
          return candidate
        }
        break
      }
    }

    let makeAheadLimits = [2_000, 1_000, 600, 300, 160, 80, 0]
    for makeAheadCharacterLimit in makeAheadLimits {
      for ingredientLimit in stride(from: initialIngredientLimit, through: 0, by: -1) {
        let candidate = renderedContext(
          items: sortedItems,
          ingredientLimit: ingredientLimit,
          makeAheadCharacterLimit: makeAheadCharacterLimit,
          includeMethod: false,
          omittedItemCount: 0
        )
        if candidate.text.count <= characterBudget {
          return candidate
        }
      }
    }

    var includedItems = sortedItems
    while !includedItems.isEmpty {
      includedItems.removeLast()
      let candidate = renderedContext(
        items: includedItems,
        ingredientLimit: 0,
        makeAheadCharacterLimit: 0,
        includeMethod: false,
        omittedItemCount: sortedItems.count - includedItems.count
      )
      if candidate.text.count <= characterBudget {
        return candidate
      }
    }

    return renderedContext(
      items: [],
      ingredientLimit: 0,
      makeAheadCharacterLimit: 0,
      includeMethod: false,
      omittedItemCount: sortedItems.count
    )
  }

  private func initialIngredientLimit(
    for characterBudget: Int,
    items: [MenuChatItemContext]
  ) -> Int {
    guard characterBudget >= Self.frontierSerializedCharacterBudget else {
      return Self.defaultIngredientLimit
    }
    return items.map { $0.keyIngredients.count }.max() ?? 0
  }

  private static func prepPrompt(
    context: String,
    tasteProfile: String,
    makeAheadPreference: String
  ) -> String {
    """
    You weave a staged prep plan for one multi-day menu from the menu context below. Compose from stored per-recipe Make-Ahead notes when present, and invent grounded sequencing, work sessions, and new prep steps from the menu's dishes. Prefer the authored Make-Ahead notes when they are available.

    Taste profile:
    \(tasteProfile)

    Make-ahead & prep-plan preferences:
    \(makeAheadPreference)

    Return only paste-ready review text, not JSON. Use free-form session headers ending with a colon, followed by one or more bullets, exactly like this:
    Wednesday evening:
    - Salt the chicken → Thursday dinner

    Put one task on each `- task → serves` bullet, using the Unicode `→` glyph (not ASCII `->`) for the optional serves suffix. This text will be pasted back into the recipe app, so do not include commentary, Markdown fences, menu item IDs, or JSON.

    \(context)
    """
  }

  private func renderedContext(
    items: [MenuChatItemContext],
    ingredientLimit: Int,
    makeAheadCharacterLimit: Int?,
    includeMethod: Bool,
    omittedItemCount: Int
  ) -> MenuChatSerializedContext {
    var budgetNotes: [String] = []
    if !includeMethod, items.contains(where: { !$0.method.isEmpty }) {
      budgetNotes.append(
        "Recipe methods were omitted before other dish details to stay within the context budget."
      )
    }
    let ingredientListsWereTrimmed = items.contains { $0.keyIngredients.count > ingredientLimit }
    if ingredientListsWereTrimmed {
      budgetNotes.append(
        ingredientLimit > 0
          ? "Ingredient lists are capped at \(ingredientLimit) lines per dish."
          : "Ingredient lists were omitted to stay within the context budget."
      )
    }
    if let makeAheadCharacterLimit,
      items.contains(where: { ($0.makeAhead?.count ?? 0) > makeAheadCharacterLimit })
    {
      budgetNotes.append(
        makeAheadCharacterLimit > 0
          ? "Recipe make-ahead notes are capped at \(makeAheadCharacterLimit) characters per dish."
          : "Recipe make-ahead notes were omitted to keep every dish represented."
      )
    }
    if omittedItemCount > 0 {
      budgetNotes.append(
        "\(omittedItemCount) lower-priority menu item(s) were omitted to stay within the context budget."
      )
    }

    var lines = ["The user is looking at this menu:"]
    lines.append("- Title: \(title.isEmpty ? "(untitled)" : title)")
    lines.append("- Duration: \(dayCount == 1 ? "1 day" : "\(dayCount) days")")
    if let notes { lines.append("- Menu notes: \(notes.replacingOccurrences(of: "\n", with: " "))") }
    if !prepPlan.isEmpty {
      lines.append("Current prep plan:")
      for step in prepPlan {
        lines.append("- \(step.session): \(step.task)")
        if let serves = step.serves {
          lines.append("  - Serves: \(serves)")
        }
        if let sourceDish = step.sourceDish {
          lines.append("  - Source menu item ID: \(sourceDish.uuidString)")
        }
      }
    }
    if !budgetNotes.isEmpty {
      lines.append("Context budget notes:")
      for note in budgetNotes {
        lines.append("- \(note)")
      }
    }
    guard !items.isEmpty else {
      lines.append("Menu items: none included.")
      return MenuChatSerializedContext(text: lines.joined(separator: "\n"), notes: budgetNotes)
    }

    lines.append("Menu item summaries:")
    for item in items {
      lines.append("- \(item.title.isEmpty ? "(untitled)" : item.title)")
      lines.append("  - Menu item ID: \(item.id.uuidString)")
      lines.append("  - Kind: \(item.kind.title)")
      lines.append("  - Day: \(item.dayOffset + 1) (dayOffset \(item.dayOffset))")
      lines.append("  - Meal slot: \(item.mealSlot.title)")
      if let prepTimeMinutes = item.prepTimeMinutes {
        lines.append("  - Prep time: \(prepTimeMinutes) minutes")
      }
      if let cookTimeMinutes = item.cookTimeMinutes {
        lines.append("  - Cook time: \(cookTimeMinutes) minutes")
      }
      if let totalTimeMinutes = item.totalTimeMinutes {
        lines.append("  - Total time: \(totalTimeMinutes) minutes")
      }
      let ingredients = Array(item.keyIngredients.prefix(ingredientLimit))
      if !ingredients.isEmpty {
        lines.append("  - Key ingredients:")
        for ingredient in ingredients {
          lines.append("    - \(ingredient.replacingOccurrences(of: "\n", with: " "))")
        }
      }
      if let notes = item.notes {
        lines.append("  - Menu item notes: \(notes.replacingOccurrences(of: "\n", with: " "))")
      }
      if let makeAhead = item.makeAhead?.truncated(to: makeAheadCharacterLimit) {
        lines.append("  - Existing recipe make-ahead note, verbatim:")
        lines.append(makeAhead)
      }
      if includeMethod, !item.method.isEmpty {
        lines.append("  - Method:")
        for line in item.method {
          lines.append("    - \(line.replacingOccurrences(of: "\n", with: " "))")
        }
      }
    }
    return MenuChatSerializedContext(text: lines.joined(separator: "\n"), notes: budgetNotes)
  }
}

public struct MenuChatItemContext: Equatable, Sendable {
  public var id: MenuItem.ID
  public var title: String
  public var kind: MealPlanItemKind
  public var dayOffset: Int
  public var mealSlot: MealPlanItemSlot
  public var sortOrder: Int
  public var keyIngredients: [String]
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var makeAhead: String?
  public var method: [String]
  public var notes: String?

  public init(
    id: MenuItem.ID,
    title: String,
    kind: MealPlanItemKind,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    sortOrder: Int,
    keyIngredients: [String] = [],
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    makeAhead: String? = nil,
    method: [String] = [],
    notes: String? = nil
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.dayOffset = dayOffset
    self.mealSlot = mealSlot
    self.sortOrder = sortOrder
    self.keyIngredients = keyIngredients
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.makeAhead = makeAhead
    self.method = method
    self.notes = notes
  }

  public init(row: MenuItemRowData) {
    self.init(
      id: row.item.id,
      title: row.displayTitle,
      kind: row.item.kind,
      dayOffset: row.item.dayOffset,
      mealSlot: row.item.mealSlot,
      sortOrder: row.item.sortOrder,
      keyIngredients: row.recipeIngredientLines,
      prepTimeMinutes: row.recipe?.prepTimeMinutes,
      cookTimeMinutes: row.recipe?.cookTimeMinutes,
      totalTimeMinutes: row.recipe?.totalTimeMinutes,
      makeAhead: row.recipe?.makeAhead,
      method: row.recipeMethodLines,
      notes: row.item.notes
    )
  }
}

private struct MenuChatSerializedContext: Equatable {
  var text: String
  var notes: [String]
}

private extension String {
  func truncated(to characterLimit: Int?) -> String? {
    guard let characterLimit else { return self }
    guard characterLimit > 0 else { return nil }
    guard count > characterLimit else { return self }
    let endIndex = index(startIndex, offsetBy: characterLimit)
    return String(self[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

private func areMenuChatItemsInIncreasingOrder(
  _ lhs: MenuChatItemContext,
  _ rhs: MenuChatItemContext
) -> Bool {
  if lhs.dayOffset != rhs.dayOffset {
    return lhs.dayOffset < rhs.dayOffset
  }
  if lhs.mealSlot.sortOrder != rhs.mealSlot.sortOrder {
    return lhs.mealSlot.sortOrder < rhs.mealSlot.sortOrder
  }
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}
