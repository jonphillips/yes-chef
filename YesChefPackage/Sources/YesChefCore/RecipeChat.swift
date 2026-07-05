import Dependencies
import Foundation
import LLMClientKit
import Observation

public let recipeChatCustomInstructionsKey = "recipeChatCustomInstructions"
public let recipeChatFrontierProviderKey = "recipeChatFrontierProvider"

public struct RecipeChatInstructions: Sendable {
  public var current: @Sendable () -> String

  public init(current: @escaping @Sendable () -> String) {
    self.current = current
  }
}

extension RecipeChatInstructions: DependencyKey {
  public static let liveValue = RecipeChatInstructions {
    UserDefaults.standard.string(forKey: recipeChatCustomInstructionsKey) ?? ""
  }

  public static let testValue = RecipeChatInstructions { "" }
  public static let previewValue = RecipeChatInstructions { "" }
}

extension DependencyValues {
  public var recipeChatInstructions: RecipeChatInstructions {
    get { self[RecipeChatInstructions.self] }
    set { self[RecipeChatInstructions.self] = newValue }
  }
}

public struct RecipeChatProviderPreference: Sendable {
  public var current: @Sendable () -> FrontierProvider?
  public var set: @Sendable (FrontierProvider) -> Void

  public init(
    current: @escaping @Sendable () -> FrontierProvider?,
    set: @escaping @Sendable (FrontierProvider) -> Void
  ) {
    self.current = current
    self.set = set
  }
}

extension RecipeChatProviderPreference: DependencyKey {
  public static let liveValue = RecipeChatProviderPreference(
    current: {
      UserDefaults.standard.string(forKey: recipeChatFrontierProviderKey)
        .flatMap(FrontierProvider.init(rawValue:))
    },
    set: { provider in
      UserDefaults.standard.set(provider.rawValue, forKey: recipeChatFrontierProviderKey)
    }
  )

  public static let testValue = RecipeChatProviderPreference(current: { nil }, set: { _ in })
  public static let previewValue = RecipeChatProviderPreference(current: { nil }, set: { _ in })
}

extension DependencyValues {
  public var recipeChatProviderPreference: RecipeChatProviderPreference {
    get { self[RecipeChatProviderPreference.self] }
    set { self[RecipeChatProviderPreference.self] = newValue }
  }
}

public enum RecipeChatContext: Equatable, Sendable {
  case mealPlan(MealPlanChatContext)
  case menu(MenuChatContext)
  case recipe(RecipeChatRecipeContext)

  public var title: String {
    switch self {
    case let .mealPlan(context): context.title
    case let .menu(context): context.title.isEmpty ? "this menu" : context.title
    case let .recipe(context): context.title.isEmpty ? "this recipe" : context.title
    }
  }

  public var subject: String {
    switch self {
    case .mealPlan: "meal plan"
    case .menu: "menu"
    case .recipe: "recipe"
    }
  }

  public var promptSubjectDescription: String {
    switch self {
    case .mealPlan: "the meal plan day the user is looking at"
    case .menu: "the menu the user is looking at"
    case .recipe: "the recipe the user is looking at"
    }
  }

  public var seededContextDescription: String {
    switch self {
    case let .mealPlan(context): context.seededContextDescription
    case let .menu(context): context.seededContextDescription
    case .recipe: "Seeded with the recipe on screen."
    }
  }

  public var providerContextWarning: String {
    switch self {
    case .mealPlan: "Meal plan context leaves the device for this conversation."
    case .menu: "Menu context leaves the device for this conversation."
    case .recipe: "Recipe context leaves the device for this conversation."
    }
  }

  public func serialized() -> String {
    switch self {
    case let .mealPlan(context): context.serialized()
    case let .menu(context): context.serialized()
    case let .recipe(context): context.serialized()
    }
  }
}

public struct MealPlanChatContext: Equatable, Sendable {
  public static let defaultIngredientLimit = 8
  public static let serializedCharacterBudget = 12_000

  public var title: String
  public var items: [MealPlanChatItemContext]

  public init(
    title: String,
    items: [MealPlanChatItemContext] = []
  ) {
    self.title = title
    self.items = items
  }

  public init(title: String, rows: [MealPlanItemRowData]) {
    self.init(title: title, items: rows.map { MealPlanChatItemContext(row: $0) })
  }

  public var seededContextDescription: String {
    let budgeted = budgetedSerialization(characterBudget: Self.serializedCharacterBudget)
    guard !budgeted.notes.isEmpty else {
      return "Seeded with \(title) meal plan item summaries."
    }
    return "Seeded with \(title) meal plan item summaries. \(budgeted.notes.joined(separator: " "))"
  }

  public func serialized(characterBudget: Int = Self.serializedCharacterBudget) -> String {
    budgetedSerialization(characterBudget: characterBudget).text
  }

  private func budgetedSerialization(characterBudget: Int) -> MealPlanChatSerializedContext {
    let sortedItems = items.sorted(by: areMealPlanChatItemsInIncreasingOrder)
    for ingredientLimit in stride(from: Self.defaultIngredientLimit, through: 0, by: -1) {
      let candidate = renderedContext(
        items: sortedItems,
        ingredientLimit: ingredientLimit,
        omittedItemCount: 0
      )
      if candidate.text.count <= characterBudget || ingredientLimit == 0 {
        if candidate.text.count <= characterBudget {
          return candidate
        }
        break
      }
    }

    var includedItems = sortedItems
    while !includedItems.isEmpty {
      includedItems.removeLast()
      let candidate = renderedContext(
        items: includedItems,
        ingredientLimit: 0,
        omittedItemCount: sortedItems.count - includedItems.count
      )
      if candidate.text.count <= characterBudget {
        return candidate
      }
    }

    return renderedContext(
      items: [],
      ingredientLimit: 0,
      omittedItemCount: sortedItems.count
    )
  }

  private func renderedContext(
    items: [MealPlanChatItemContext],
    ingredientLimit: Int,
    omittedItemCount: Int
  ) -> MealPlanChatSerializedContext {
    var budgetNotes: [String] = []
    let ingredientListsWereTrimmed = items.contains { $0.keyIngredients.count > ingredientLimit }
    if ingredientListsWereTrimmed {
      budgetNotes.append(
        ingredientLimit > 0
          ? "Ingredient lists are capped at \(ingredientLimit) lines per meal plan item."
          : "Ingredient lists were omitted to stay within the context budget."
      )
    }
    if omittedItemCount > 0 {
      budgetNotes.append(
        "\(omittedItemCount) lower-priority meal plan item(s) were omitted to stay within the context budget."
      )
    }

    var lines = ["The user is looking at this meal plan day:"]
    lines.append("- Date: \(title.isEmpty ? "(unspecified day)" : title)")
    if !budgetNotes.isEmpty {
      lines.append("Context budget notes:")
      for note in budgetNotes {
        lines.append("- \(note)")
      }
    }
    guard !items.isEmpty else {
      lines.append("Meal plan items: none included.")
      return MealPlanChatSerializedContext(text: lines.joined(separator: "\n"), notes: budgetNotes)
    }

    lines.append("Meal plan item summaries:")
    for item in items {
      lines.append("- \(item.title.isEmpty ? "(untitled)" : item.title)")
      lines.append("  - Meal plan item ID: \(item.id.rawValue)")
      lines.append("  - Kind: \(item.kind.title)")
      lines.append("  - Date: \(title.isEmpty ? "(unspecified day)" : title)")
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
        lines.append("  - Meal plan item notes: \(notes.replacingOccurrences(of: "\n", with: " "))")
      }
      if let makeAhead = item.makeAhead {
        lines.append("  - Existing recipe make-ahead note, verbatim:")
        lines.append(makeAhead)
      }
    }
    return MealPlanChatSerializedContext(text: lines.joined(separator: "\n"), notes: budgetNotes)
  }
}

public struct MealPlanChatItemContext: Equatable, Sendable {
  public var id: MealPlanItemRowID
  public var title: String
  public var kind: MealPlanItemKind
  public var scheduledDate: Date
  public var mealSlot: MealPlanItemSlot
  public var sortOrder: Int
  public var keyIngredients: [String]
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var makeAhead: String?
  public var notes: String?

  public init(
    id: MealPlanItemRowID,
    title: String,
    kind: MealPlanItemKind,
    scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    sortOrder: Int,
    keyIngredients: [String] = [],
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    makeAhead: String? = nil,
    notes: String? = nil
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.scheduledDate = scheduledDate
    self.mealSlot = mealSlot
    self.sortOrder = sortOrder
    self.keyIngredients = keyIngredients
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.makeAhead = makeAhead
    self.notes = notes
  }

  public init(row: MealPlanItemRowData) {
    self.init(
      id: row.id,
      title: row.displayTitle,
      kind: row.item.kind,
      scheduledDate: row.item.scheduledDate,
      mealSlot: row.item.mealSlot,
      sortOrder: row.item.sortOrder,
      keyIngredients: row.recipeIngredientLines,
      prepTimeMinutes: row.recipe?.prepTimeMinutes,
      cookTimeMinutes: row.recipe?.cookTimeMinutes,
      totalTimeMinutes: row.recipe?.totalTimeMinutes,
      makeAhead: row.recipe?.makeAhead,
      notes: row.item.notes
    )
  }
}

private struct MealPlanChatSerializedContext: Equatable {
  var text: String
  var notes: [String]
}

private func areMealPlanChatItemsInIncreasingOrder(
  _ lhs: MealPlanChatItemContext,
  _ rhs: MealPlanChatItemContext
) -> Bool {
  if lhs.scheduledDate != rhs.scheduledDate {
    return lhs.scheduledDate < rhs.scheduledDate
  }
  if lhs.mealSlot.sortOrder != rhs.mealSlot.sortOrder {
    return lhs.mealSlot.sortOrder < rhs.mealSlot.sortOrder
  }
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.id.rawValue < rhs.id.rawValue
}

public struct MenuChatContext: Equatable, Sendable {
  public static let defaultIngredientLimit = 8
  public static let serializedCharacterBudget = 12_000

  public var title: String
  public var notes: String?
  public var dayCount: Int
  public var items: [MenuChatItemContext]

  public init(
    title: String,
    notes: String? = nil,
    dayCount: Int,
    items: [MenuChatItemContext] = []
  ) {
    self.title = title
    self.notes = notes
    self.dayCount = dayCount
    self.items = items
  }

  public init(detail: MenuDetailData) {
    self.init(
      title: detail.menu.title,
      notes: detail.menu.notes,
      dayCount: detail.menu.dayCount,
      items: detail.itemRows.map(MenuChatItemContext.init(row:))
    )
  }

  public var seededContextDescription: String {
    let budgeted = budgetedSerialization(characterBudget: Self.serializedCharacterBudget)
    guard !budgeted.notes.isEmpty else {
      return "Seeded with menu dish summaries."
    }
    return "Seeded with menu dish summaries. \(budgeted.notes.joined(separator: " "))"
  }

  public func serialized(characterBudget: Int = Self.serializedCharacterBudget) -> String {
    budgetedSerialization(characterBudget: characterBudget).text
  }

  private func budgetedSerialization(characterBudget: Int) -> MenuChatSerializedContext {
    let sortedItems = items.sorted(by: areMenuChatItemsInIncreasingOrder)
    for ingredientLimit in stride(from: Self.defaultIngredientLimit, through: 0, by: -1) {
      let candidate = renderedContext(
        items: sortedItems,
        ingredientLimit: ingredientLimit,
        omittedItemCount: 0
      )
      if candidate.text.count <= characterBudget || ingredientLimit == 0 {
        if candidate.text.count <= characterBudget {
          return candidate
        }
        break
      }
    }

    var includedItems = sortedItems
    while !includedItems.isEmpty {
      includedItems.removeLast()
      let candidate = renderedContext(
        items: includedItems,
        ingredientLimit: 0,
        omittedItemCount: sortedItems.count - includedItems.count
      )
      if candidate.text.count <= characterBudget {
        return candidate
      }
    }

    return renderedContext(
      items: [],
      ingredientLimit: 0,
      omittedItemCount: sortedItems.count
    )
  }

  private func renderedContext(
    items: [MenuChatItemContext],
    ingredientLimit: Int,
    omittedItemCount: Int
  ) -> MenuChatSerializedContext {
    var budgetNotes: [String] = []
    let ingredientListsWereTrimmed = items.contains { $0.keyIngredients.count > ingredientLimit }
    if ingredientListsWereTrimmed {
      budgetNotes.append(
        ingredientLimit > 0
          ? "Ingredient lists are capped at \(ingredientLimit) lines per dish."
          : "Ingredient lists were omitted to stay within the context budget."
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
      if let makeAhead = item.makeAhead {
        lines.append("  - Existing recipe make-ahead note, verbatim:")
        lines.append(makeAhead)
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
      notes: row.item.notes
    )
  }
}

private struct MenuChatSerializedContext: Equatable {
  var text: String
  var notes: [String]
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

public struct RecipeChatRecipeContext: Equatable, Sendable {
  public var title: String
  public var subtitle: String?
  public var summary: String?
  public var servingsText: String?
  public var yieldText: String?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var ingredientSections: [RecipeChatSection]
  public var instructionSections: [RecipeChatSection]
  public var notes: [String]
  public var makeAhead: String?
  public var chefItUp: String?
  public var serveWith: [ServeWithItem]

  public init(
    title: String,
    subtitle: String? = nil,
    summary: String? = nil,
    servingsText: String? = nil,
    yieldText: String? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    ingredientSections: [RecipeChatSection] = [],
    instructionSections: [RecipeChatSection] = [],
    notes: [String] = [],
    makeAhead: String? = nil,
    chefItUp: String? = nil,
    serveWith: [ServeWithItem] = []
  ) {
    self.title = title
    self.subtitle = subtitle
    self.summary = summary
    self.servingsText = servingsText
    self.yieldText = yieldText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.ingredientSections = ingredientSections
    self.instructionSections = instructionSections
    self.notes = notes
    self.makeAhead = makeAhead
    self.chefItUp = chefItUp
    self.serveWith = serveWith
  }

  public init(detail: RecipeDetailData) {
    let ingredientLinesBySection = Dictionary(grouping: detail.ingredientLines) { $0.sectionID }
    let instructionStepsBySection = Dictionary(grouping: detail.instructionSteps) { $0.sectionID }
    self.init(
      title: detail.recipe.title,
      subtitle: detail.recipe.subtitle,
      summary: detail.recipe.summary,
      servingsText: detail.recipe.servingsText,
      yieldText: detail.recipe.yieldText,
      prepTimeMinutes: detail.recipe.prepTimeMinutes,
      cookTimeMinutes: detail.recipe.cookTimeMinutes,
      totalTimeMinutes: detail.recipe.totalTimeMinutes,
      ingredientSections: detail.ingredientSections
        .sorted { $0.sortOrder < $1.sortOrder }
        .map { section in
          RecipeChatSection(
            name: section.name,
            lines: (ingredientLinesBySection[section.id] ?? [])
              .sorted { $0.sortOrder < $1.sortOrder }
              .map(\.originalText)
          )
        }
        .filter { !$0.lines.isEmpty },
      instructionSections: detail.instructionSections
        .sorted { $0.sortOrder < $1.sortOrder }
        .map { section in
          RecipeChatSection(
            name: section.name,
            lines: (instructionStepsBySection[section.id] ?? [])
              .sorted { $0.sortOrder < $1.sortOrder }
              .map(\.text)
          )
        }
        .filter { !$0.lines.isEmpty },
      notes: detail.notes
        .filter { $0.noteType == .general }
        .sorted { $0.dateCreated < $1.dateCreated }
        .map(\.text),
      makeAhead: detail.recipe.makeAhead,
      chefItUp: detail.recipe.chefItUp,
      serveWith: ServeWithCoding.decode(detail.recipe.serveWith)
    )
  }

  public func serialized() -> String {
    var lines = ["The user is looking at this recipe:"]
    lines.append("- Title: \(title.isEmpty ? "(untitled)" : title)")
    if let subtitle { lines.append("- Subtitle: \(subtitle)") }
    if let summary { lines.append("- Summary: \(summary)") }
    if let servingsText { lines.append("- Servings: \(servingsText)") }
    if let yieldText { lines.append("- Yield: \(yieldText)") }
    if let prepTimeMinutes { lines.append("- Prep time: \(prepTimeMinutes) minutes") }
    if let cookTimeMinutes { lines.append("- Cook time: \(cookTimeMinutes) minutes") }
    if let totalTimeMinutes { lines.append("- Total time: \(totalTimeMinutes) minutes") }
    append(sections: ingredientSections, title: "Ingredients", to: &lines)
    append(sections: instructionSections, title: "Instructions", to: &lines)
    if !notes.isEmpty {
      lines.append("Notes:")
      for note in notes {
        lines.append("- \(note.replacingOccurrences(of: "\n", with: " "))")
      }
    }
    if let makeAhead {
      lines.append("Current make-ahead section:")
      lines.append(makeAhead)
    }
    if let chefItUp {
      lines.append("Current Chef It Up section:")
      lines.append(chefItUp)
    }
    if !serveWith.isEmpty {
      lines.append("Current Serve With section:")
      for item in serveWith {
        if let note = item.note {
          lines.append("- \(item.title): \(note)")
        } else {
          lines.append("- \(item.title)")
        }
      }
    }
    return lines.joined(separator: "\n")
  }

  private func append(sections: [RecipeChatSection], title: String, to lines: inout [String]) {
    guard !sections.isEmpty else { return }
    lines.append("\(title):")
    for section in sections {
      if let name = section.name, !name.isEmpty {
        lines.append("- \(name):")
        for line in section.lines { lines.append("  - \(line)") }
      } else {
        for line in section.lines { lines.append("- \(line)") }
      }
    }
  }
}

public struct RecipeChatSection: Equatable, Sendable {
  public var name: String?
  public var lines: [String]

  public init(name: String? = nil, lines: [String]) {
    self.name = name
    self.lines = lines
  }
}

public struct RecipeChatMessage: Identifiable, Sendable, Equatable {
  public enum Role: Sendable, Equatable {
    case user
    case assistant
  }

  public let id: UUID
  public var role: Role
  public var text: String

  public init(id: UUID = UUID(), role: Role, text: String) {
    self.id = id
    self.role = role
    self.text = text
  }
}

@MainActor
public struct ChatApplyAction<Payload: Sendable> {
  public var title: String
  public var extractingTitle: String
  public var reviewTitle: String
  public var commitTitle: String
  public var committingTitle: String
  public var committedTitle: String
  public var extract: @MainActor (_ selection: String, _ context: [RecipeChatMessage]) async throws -> Payload
  public var commit: @MainActor (_ payload: Payload) async throws -> Void

  public init(
    title: String,
    extractingTitle: String,
    reviewTitle: String,
    commitTitle: String = "Commit",
    committingTitle: String,
    committedTitle: String,
    extract: @escaping @MainActor (_ selection: String, _ context: [RecipeChatMessage]) async throws -> Payload,
    commit: @escaping @MainActor (_ payload: Payload) async throws -> Void
  ) {
    self.title = title
    self.extractingTitle = extractingTitle
    self.reviewTitle = reviewTitle
    self.commitTitle = commitTitle
    self.committingTitle = committingTitle
    self.committedTitle = committedTitle
    self.extract = extract
    self.commit = commit
  }

}

public struct ChatApplyReviewItem: Identifiable {
  public let id: UUID
  public var title: String
  public var summary: String
  public var commitTitle: String
  public var committingTitle: String
  public var committedTitle: String
  public var commit: @MainActor () async throws -> Void

  public init(
    id: UUID = UUID(),
    title: String,
    summary: String,
    commitTitle: String,
    committingTitle: String,
    committedTitle: String,
    commit: @escaping @MainActor () async throws -> Void
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.commitTitle = commitTitle
    self.committingTitle = committingTitle
    self.committedTitle = committedTitle
    self.commit = commit
  }
}

public struct AnyChatApplyAction: Identifiable {
  public var id: String { title }
  public var title: String
  public var extractingTitle: String
  public var run: @MainActor (_ selection: String, _ context: [RecipeChatMessage]) async throws
    -> [ChatApplyReviewItem]

  @MainActor
  public init<Payload>(
    _ action: ChatApplyAction<Payload>,
    renderedSummary: @escaping @MainActor (Payload) -> String?
  ) {
    self.init(action) { payload in
      guard
        let summary = renderedSummary(payload)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !summary.isEmpty
      else { return [] }
      return [
        ChatApplyReviewItem(
          title: action.reviewTitle,
          summary: summary,
          commitTitle: action.commitTitle,
          committingTitle: action.committingTitle,
          committedTitle: action.committedTitle,
          commit: {
            try await action.commit(payload)
          }
        )
      ]
    }
  }

  @MainActor
  public init<Payload>(
    _ action: ChatApplyAction<Payload>,
    reviewItems: @escaping @MainActor (Payload) -> [ChatApplyReviewItem]
  ) {
    self.title = action.title
    self.extractingTitle = action.extractingTitle
    self.run = { selection, context in
      let payload = try await action.extract(selection, context)
      return reviewItems(payload)
    }
  }
}

public enum RecipeChatErrorText {
  public static func describe(_ error: any Error) -> String {
    switch error {
    case ModelClientError.onDeviceUnavailable:
      "On-device intelligence is not available on this device yet."
    case ModelClientError.frontierUnavailable:
      "No frontier model key is configured."
    case let ModelClientError.http(status, message):
      "The model returned an error (\(status))." + (message.map { " \($0)" } ?? "")
    case ModelClientError.malformedResponse:
      "The model returned a response the app could not read."
    default:
      if let localizedError = error as? any LocalizedError,
        let description = localizedError.errorDescription
      {
        description
      } else {
        "Something went wrong reaching the model."
      }
    }
  }
}

@MainActor
@Observable
public final class RecipeChatModel: Identifiable {
  public let id = UUID()
  public let context: RecipeChatContext
  public private(set) var messages: [RecipeChatMessage] = []
  public var useFrontier = false
  public var selectedProvider: FrontierProvider = .anthropic {
    didSet {
      providerPreference.set(selectedProvider)
    }
  }
  public private(set) var isResponding = false
  public private(set) var errorText: String?

  @ObservationIgnored @Dependency(\.modelClient) private var modelClient
  @ObservationIgnored @Dependency(\.apiKeyStore) private var apiKeyStore
  @ObservationIgnored @Dependency(\.recipeChatInstructions) private var chatInstructions
  @ObservationIgnored @Dependency(\.recipeChatProviderPreference) private var providerPreference

  public init(context: RecipeChatContext) {
    self.context = context
    selectedProvider = defaultProvider()
  }

  public var frontierAvailable: Bool { !availableProviders.isEmpty }

  public var availableProviders: [FrontierProvider] {
    FrontierProvider.allCases.filter { apiKeyStore.key($0) != nil }
  }

  public var activeTier: ModelTier {
    useFrontier && apiKeyStore.key(selectedProvider) != nil
      ? .frontier(selectedProvider) : .onDevice
  }

  public var sendsToProvider: Bool {
    if case .frontier = activeTier { return true }
    return false
  }

  public func send(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isResponding else { return }
    messages.append(RecipeChatMessage(role: .user, text: trimmed))
    isResponding = true
    errorText = nil
    defer { isResponding = false }

    let requestMessages = history()
    let index = appendAssistantPlaceholder()
    do {
      if case .frontier = activeTier {
        let response = try await modelClient.complete(
          ModelRequest(tier: activeTier, system: systemPrompt(), messages: requestMessages, maxTokens: 2048)
        )
        messages[index].text = response.text.isEmpty ? "(No response.)" : response.text
      } else {
        let request = ModelRequest(
          tier: activeTier,
          system: systemPrompt(),
          messages: requestMessages,
          maxTokens: 1024
        )
        for try await chunk in modelClient.stream(request) {
          messages[index].text += chunk.text
        }
        if messages[index].text.isEmpty {
          messages[index].text = "(No response.)"
        }
      }
    } catch {
      removePlaceholderIfEmpty(at: index)
      errorText = describe(error)
    }
  }

  public func systemPrompt() -> String {
    let base = """
      You are a concise, practical cooking assistant inside a private recipe app.
      Discuss \(context.promptSubjectDescription), described below. Help with timing,
      prep, troubleshooting, and planning. You propose and explain;
      you never claim to have edited or saved anything yourself.

      Answer in short plain-prose paragraphs. Use inline Markdown links when useful.
      Do not use headings, tables, horizontal rules, or bold section labels; the panel is narrow.

      \(context.serialized())
      """
    let custom = chatInstructions.current().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !custom.isEmpty else { return base }
    return """
      \(base)

      Additional standing instructions from the user (honor these unless they conflict with the rules above):
      \(custom)
      """
  }

  private func history() -> [ModelMessage] {
    messages.compactMap { message in
      guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      return ModelMessage(role: message.role == .user ? .user : .assistant, text: message.text)
    }
  }

  private func appendAssistantPlaceholder() -> Int {
    messages.append(RecipeChatMessage(role: .assistant, text: ""))
    return messages.count - 1
  }

  private func removePlaceholderIfEmpty(at index: Int) {
    if messages.indices.contains(index),
      messages[index].role == .assistant,
      messages[index].text.isEmpty
    {
      messages.remove(at: index)
    }
  }

  private func describe(_ error: any Error) -> String {
    RecipeChatErrorText.describe(error)
  }

  private func defaultProvider() -> FrontierProvider {
    let availableProviders = availableProviders
    if let preferred = providerPreference.current(), availableProviders.contains(preferred) {
      return preferred
    }
    return availableProviders.first ?? .anthropic
  }
}
