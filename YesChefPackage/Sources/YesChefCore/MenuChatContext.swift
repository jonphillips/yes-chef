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
  public var placementStartDate: Date?
  public var prepPlan: [PrepPlanStepRecord]
  public var items: [MenuChatItemContext]
  public var learnings: [Learning]

  public init(
    menuID: Menu.ID? = nil,
    title: String,
    notes: String? = nil,
    dayCount: Int,
    placementStartDate: Date? = nil,
    prepPlan: [PrepPlanStepRecord] = [],
    items: [MenuChatItemContext] = [],
    learnings: [Learning] = []
  ) {
    self.menuID = menuID
    self.title = title
    self.notes = notes
    self.dayCount = dayCount
    self.placementStartDate = placementStartDate
    self.prepPlan = prepPlan
    self.items = items
    self.learnings = learnings
  }

  public init(detail: MenuDetailData) {
    self.init(
      menuID: detail.menu.id,
      title: detail.menu.title,
      notes: detail.menu.notes,
      dayCount: detail.menu.dayCount,
      placementStartDate: detail.placements.count == 1 ? detail.placements[0].startDate : nil,
      prepPlan: detail.prepPlanSteps,
      items: detail.itemRows.map(MenuChatItemContext.init(row:)),
      learnings: detail.learnings
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

  public func prepPrompt(destination: AIHandoffPromptDestination = .outboard) -> String {
    @Dependency(\.aiPromptPreferences) var preferences
    let settings = preferences.current()
    return prepPrompt(
      context: serialized(for: .frontierPreferred),
      tasteProfile: settings.tasteProfile,
      makeAheadPreference: AISettingsRepository.preference(
        in: settings,
        for: .makeAheadPrepPlan
      ),
      destination: destination
    )
  }

  public func serialized(characterBudget: Int = Self.serializedCharacterBudget) -> String {
    budgetedSerialization(characterBudget: characterBudget).text
  }

  public func scoped(toDayOffset dayOffset: Int) -> Self {
    var context = self
    context.dayCount = 1
    context.items = items.filter { $0.dayOffset == dayOffset }
    return context
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
      omittedItemCount: sortedItems.count,
      includeLearnings: false
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

  private func prepPrompt(
    context: String,
    tasteProfile: String,
    makeAheadPreference: String,
    destination: AIHandoffPromptDestination
  ) -> String {
    let calendarInstruction: String
    if placementStartDate != nil {
      calendarInstruction = """
      The calendar dates in the menu context are authoritative. Use day-anchored work-session labels such as "Thursday evening" or "Saturday · ~3 hrs out", not relative horizons. In each serves suffix, name the actual day and dish when useful, such as "Saturday's Korean Bavette".
      """
    } else {
      calendarInstruction = """
      This menu has no calendar dates. Keep work-session labels in relative-horizon wording such as "Two days ahead" or "Morning of"; do not invent a day. Use the same relative wording in serves when needed, such as "tomorrow's beef".
      """
    }
    let transportInstruction = switch destination {
    case .outboard:
      " This text will be pasted back into the recipe app, so do not include commentary, Markdown fences, menu item IDs, or JSON."
    case .onboard:
      ""
    }
    let subjectContext = switch destination {
    case .outboard: "\n\n\(context)"
    case .onboard: ""
    }
    return """
    You weave a staged prep plan for one multi-day menu from the menu context below. Compose from stored per-recipe Make-Ahead notes when present, and invent grounded sequencing, work sessions, and new prep steps from the menu's dishes. Prefer the authored Make-Ahead notes when they are available.

    \(calendarInstruction)

    Taste profile:
    \(tasteProfile)

    Make-ahead & prep-plan preferences:
    \(makeAheadPreference)

    Return only paste-ready review text, not JSON. Use free-form session headers ending with a colon, followed by one or more bullets, exactly like this:
    Wednesday evening:
    - Salt the chicken → Thursday dinner

    Put one task on each `- task → serves` bullet, using the Unicode `→` glyph (not ASCII `->`) for the optional serves suffix.\(transportInstruction)\(subjectContext)
    """
  }

  private func renderedContext(
    items: [MenuChatItemContext],
    ingredientLimit: Int,
    makeAheadCharacterLimit: Int?,
    includeMethod: Bool,
    omittedItemCount: Int,
    includeLearnings: Bool = true
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
    if !includeLearnings, !learnings.isEmpty {
      budgetNotes.append("Menu learnings were omitted as the final context-budget reduction.")
    }

    var lines = ["The user is looking at this menu:"]
    lines.append("- Title: \(title.isEmpty ? "(untitled)" : title)")
    lines.append("- Duration: \(dayCount == 1 ? "1 day" : "\(dayCount) days")")
    if let placementStartDate {
      lines.append("- Dates: \(menuDateSpan(startingAt: placementStartDate, dayCount: dayCount))")
    }
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
    if includeLearnings, !learnings.isEmpty {
      lines.append(
        "Already-captured menu learnings — do NOT repeat these; in the learnings section return only genuinely new, durable learnings established this session that are not already listed:"
      )
      for learning in learnings {
        lines.append("- \(learning.text)")
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
      let date = placementStartDate.flatMap {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: item.dayOffset, to: $0)
      }
      let dayDescription = if let date {
        "\(item.dayOffset + 1) (dayOffset \(item.dayOffset), \(menuDateLabel(date)))"
      } else {
        "\(item.dayOffset + 1) (dayOffset \(item.dayOffset))"
      }
      lines.append("  - Day: \(dayDescription)")
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

public enum MenuDayHandoffScope {
  public static func prepInstruction(dayOffset: Int, placementStartDate: Date? = nil) -> String {
    let dayTitle = if let placementStartDate,
      let date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: dayOffset, to: placementStartDate)
    {
      "Day \(dayOffset + 1) (\(menuDateLabel(date)))"
    } else {
      "Day \(dayOffset + 1)"
    }
    return """
    This request focuses on \(dayTitle) dishes. The context includes only that day's dishes, but it also includes the full current prep plan for the menu. Return the whole menu prep plan: preserve every existing step for other days verbatim and in place, and weave \(dayTitle) changes into the existing horizon bands rather than adding a new appended section. Anything omitted from the reply will be deleted.
    """
  }

  public static func complementInstruction(dayOffset: Int) -> String {
    """
    This request is only for Day \(dayOffset + 1). The context includes only that day's dishes. Keep every proposed task or complement on Day \(dayOffset + 1); do not plan for another day.
    """
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

private func menuDateSpan(startingAt startDate: Date, dayCount: Int) -> String {
  guard dayCount > 1,
    let endDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: dayCount - 1, to: startDate)
  else {
    return menuDateLabel(startDate)
  }
  return "\(menuDateLabel(startDate))–\(menuDateLabel(endDate))"
}

private func menuDateLabel(_ date: Date) -> String {
  date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}
