import Dependencies
import Foundation
import LLMClientKit
import Observation
import SQLiteData

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

public struct RecipeChatTierPreference: Sendable {
  public var current: @Sendable () -> Bool?
  public var set: @Sendable (Bool) -> Void

  public init(
    current: @escaping @Sendable () -> Bool?,
    set: @escaping @Sendable (Bool) -> Void
  ) {
    self.current = current
    self.set = set
  }
}

extension RecipeChatTierPreference: DependencyKey {
  public static let liveValue = RecipeChatTierPreference(
    current: {
      guard UserDefaults.standard.object(forKey: recipeChatUseFrontierKey) != nil else { return nil }
      return UserDefaults.standard.bool(forKey: recipeChatUseFrontierKey)
    },
    set: { useFrontier in
      UserDefaults.standard.set(useFrontier, forKey: recipeChatUseFrontierKey)
    }
  )

  public static let testValue = RecipeChatTierPreference(current: { nil }, set: { _ in })
  public static let previewValue = RecipeChatTierPreference(current: { nil }, set: { _ in })
}

extension DependencyValues {
  public var recipeChatProviderPreference: RecipeChatProviderPreference {
    get { self[RecipeChatProviderPreference.self] }
    set { self[RecipeChatProviderPreference.self] = newValue }
  }

  public var recipeChatTierPreference: RecipeChatTierPreference {
    get { self[RecipeChatTierPreference.self] }
    set { self[RecipeChatTierPreference.self] = newValue }
  }
}

public enum RecipeChatContext: Equatable, Sendable {
  public static let workbenchTaskFraming = """
    The user is assembling candidate versions of a dish to compare them, reconcile their differences, and reason toward one working recipe. Help them see how the candidates differ and what's worth borrowing from each - don't blend everything into a bland average. The working recipe needn't be a single monolithic version: the user may want a base recipe plus a few deliberate variations, and those variations can live inside the one working recipe.
    """

  case mealPlan(MealPlanChatContext)
  case menu(MenuChatContext)
  case recipe(RecipeChatRecipeContext)
  case workbench(WorkbenchChatContext)

  public var title: String {
    switch self {
    case let .mealPlan(context): context.title
    case let .menu(context): context.title.isEmpty ? "this menu" : context.title
    case let .recipe(context): context.title.isEmpty ? "this recipe" : context.title
    case let .workbench(context): context.title.isEmpty ? "this workbench" : context.title
    }
  }

  public var subject: String {
    switch self {
    case .mealPlan: "meal plan"
    case .menu: "menu"
    case .recipe: "recipe"
    case .workbench: "workbench"
    }
  }

  public var promptSubjectDescription: String {
    switch self {
    case .mealPlan: "the meal plan day the user is looking at"
    case .menu: "the menu the user is looking at"
    case .recipe: "the recipe the user is looking at"
    case .workbench: "the recipe workbench the user is looking at"
    }
  }

  public var seededContextDescription: String {
    switch self {
    case let .mealPlan(context): context.seededContextDescription
    case let .menu(context): context.seededContextDescription
    case .recipe: "Seeded with the recipe on screen."
    case let .workbench(context): context.seededContextDescription
    }
  }

  public var taskFraming: String {
    switch self {
    case .workbench:
      Self.workbenchTaskFraming
    case .mealPlan, .menu, .recipe:
      ""
    }
  }

  public var providerContextWarning: String {
    switch self {
    case .mealPlan: "Meal plan context leaves the device for this conversation."
    case .menu: "Menu context leaves the device for this conversation."
    case .recipe: "Recipe context leaves the device for this conversation."
    case .workbench: "Workbench context leaves the device for this conversation."
    }
  }

  public func serialized(for tier: ModelTier = .onDevice) -> String {
    switch self {
    case let .mealPlan(context): context.serialized()
    case let .menu(context): context.serialized(for: tier)
    case let .recipe(context): context.serialized()
    case let .workbench(context): context.serialized(for: tier)
    }
  }
}

public struct MealPlanChatContext: Equatable, Sendable {
  public static let defaultIngredientLimit = 8
  public static let serializedCharacterBudget = 12_000

  public var title: String
  public var subjectDate: Date?
  public var items: [MealPlanChatItemContext]

  public init(
    title: String,
    subjectDate: Date? = nil,
    items: [MealPlanChatItemContext] = []
  ) {
    self.title = title
    self.subjectDate = subjectDate
    self.items = items
  }

  public init(title: String, subjectDate: Date? = nil, rows: [MealPlanItemRowData]) {
    self.init(title: title, subjectDate: subjectDate, items: rows.map { MealPlanChatItemContext(row: $0) })
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

public struct RecipeChatRecipeContext: Equatable, Sendable {
  public var recipeID: Recipe.ID?
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
    recipeID: Recipe.ID? = nil,
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
    self.recipeID = recipeID
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
      recipeID: detail.recipe.id,
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
  public enum Role: String, Codable, QueryBindable, QueryDecodable, Sendable, Equatable {
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
  public var presentation: ChatApplyReviewPresentation
  public var editableTitle: String
  public var editableText: String?
  public var commitTitle: String
  public var committingTitle: String
  public var committedTitle: String
  public var commit: @MainActor (_ approvedText: String) async throws -> Void

  public init(
    id: UUID = UUID(),
    title: String,
    summary: String,
    presentation: ChatApplyReviewPresentation = .sheet,
    editableTitle: String = "Proposal",
    editableText: String? = nil,
    commitTitle: String,
    committingTitle: String,
    committedTitle: String,
    commit: @escaping @MainActor () async throws -> Void
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.presentation = presentation
    self.editableTitle = editableTitle
    self.editableText = editableText
    self.commitTitle = commitTitle
    self.committingTitle = committingTitle
    self.committedTitle = committedTitle
    self.commit = { _ in try await commit() }
  }

  public init(
    id: UUID = UUID(),
    title: String,
    summary: String,
    presentation: ChatApplyReviewPresentation = .sheet,
    editableTitle: String = "Proposal",
    editableText: String? = nil,
    commitTitle: String,
    committingTitle: String,
    committedTitle: String,
    commit: @escaping @MainActor (_ approvedText: String) async throws -> Void
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.presentation = presentation
    self.editableTitle = editableTitle
    self.editableText = editableText
    self.commitTitle = commitTitle
    self.committingTitle = committingTitle
    self.committedTitle = committedTitle
    self.commit = commit
  }
}

public enum ChatApplyReviewPresentation: Sendable, Equatable {
  case inline
  case sheet
}

public struct AnyChatApplyAction: Identifiable {
  public var id: String { title }
  public var title: String
  public var extractingTitle: String
  public var requiresSubject: Bool
  public var run: @MainActor (_ selection: String, _ context: [RecipeChatMessage]) async throws
    -> [ChatApplyReviewItem]

  @MainActor
  public init<Payload>(
    _ action: ChatApplyAction<Payload>,
    requiresSubject: Bool = true,
    reviewPresentation: ChatApplyReviewPresentation = .sheet,
    renderedSummary: @escaping @MainActor (Payload) -> String?
  ) {
    self.init(action, requiresSubject: requiresSubject) { payload in
      guard
        let summary = renderedSummary(payload)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !summary.isEmpty
      else { return [] }
      return [
        ChatApplyReviewItem(
          title: action.reviewTitle,
          summary: summary,
          presentation: reviewPresentation,
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
    requiresSubject: Bool = true,
    editableSummary: @escaping @MainActor (Payload) -> String?,
    commitEditedSummary: @escaping @MainActor (_ payload: Payload, _ editedSummary: String) async throws -> Void
  ) {
    self.init(action, requiresSubject: requiresSubject) { payload in
      guard
        let summary = editableSummary(payload)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !summary.isEmpty
      else { return [] }
      return [
        ChatApplyReviewItem(
          title: action.reviewTitle,
          summary: summary,
          editableText: summary,
          commitTitle: action.commitTitle,
          committingTitle: action.committingTitle,
          committedTitle: action.committedTitle,
          commit: { editedSummary in
            try await commitEditedSummary(payload, editedSummary)
          }
        )
      ]
    }
  }

  @MainActor
  public init<Payload>(
    _ action: ChatApplyAction<Payload>,
    requiresSubject: Bool = true,
    reviewItems: @escaping @MainActor (Payload) -> [ChatApplyReviewItem]
  ) {
    self.title = action.title
    self.extractingTitle = action.extractingTitle
    self.requiresSubject = requiresSubject
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
    case ModelClientError.onDeviceContextTooLarge:
      "This is too large for on-device intelligence. Switch to a frontier model and try again."
    case ModelClientError.frontierUnavailable:
      "No frontier model key is configured."
    case let ModelClientError.http(status, message):
      "The model returned an error (\(status))." + (message.map { " \($0)" } ?? "")
    case ModelClientError.malformedResponse:
      "The model returned a response the app could not read."
    case let urlError as URLError where urlError.code == .timedOut:
      "The request timed out — the model took too long to respond. Try again in a moment."
    case let urlError as URLError
      where urlError.code == .notConnectedToInternet || urlError.code == .cannotConnectToHost:
      "Couldn't reach the model — check your internet connection and try again."
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
  public private(set) var context: RecipeChatContext
  public private(set) var messages: [RecipeChatMessage] = []
  public var useFrontier = false {
    didSet {
      tierPreference.set(useFrontier)
    }
  }
  public var selectedProvider: FrontierProvider = .anthropic {
    didSet {
      providerPreference.set(selectedProvider)
    }
  }
  public private(set) var isResponding = false
  public private(set) var errorText: String?

  @ObservationIgnored @Dependency(\.modelClient) private var modelClient
  @ObservationIgnored @Dependency(\.apiKeyStore) private var apiKeyStore
  @ObservationIgnored @Dependency(\.recipeChatProviderPreference) private var providerPreference
  @ObservationIgnored @Dependency(\.recipeChatTierPreference) private var tierPreference
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored private var responseTask: Task<Void, Never>?

  public init(context: RecipeChatContext) {
    self.context = context
    selectedProvider = defaultProvider()
    useFrontier = defaultUseFrontier()
    loadPersistedThread()
  }

  deinit {
    responseTask?.cancel()
  }

  public func updateContext(_ context: RecipeChatContext) {
    guard self.context != context else { return }
    let previousSubject = self.context.persistenceSubject
    let nextSubject = context.persistenceSubject
    if previousSubject != nextSubject {
      persistCurrentThread()
    }
    self.context = context
    if previousSubject != nextSubject {
      loadPersistedThread()
    }
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
    guard !trimmed.isEmpty, !isResponding, responseTask == nil else { return }

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.completeSend(trimmed)
    }
    responseTask = task
    await task.value
  }

  public func stop() {
    responseTask?.cancel()
  }

  public func clear() {
    guard !isResponding else { return }
    messages.removeAll()
    errorText = nil
    persistCurrentThread()
  }

  private func completeSend(_ trimmed: String) async {
    messages.append(RecipeChatMessage(id: uuid(), role: .user, text: trimmed))
    isResponding = true
    errorText = nil
    defer {
      responseTask = nil
      isResponding = false
      persistCurrentThread()
    }

    let requestMessages = history()
    let assistantID = appendAssistantPlaceholder()
    do {
      if case .frontier = activeTier {
        let response = try await modelClient.complete(
          ModelRequest(
            tier: activeTier,
            system: systemPrompt(),
            messages: requestMessages,
            maxTokens: 2048,
            reasoningEffort: .medium
          )
        )
        try Task.checkCancellation()
        setAssistantText(
          id: assistantID,
          text: response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(No response.)" : response.text
        )
      } else {
        let request = ModelRequest(
          tier: activeTier,
          system: systemPrompt(),
          messages: requestMessages,
          maxTokens: 1024,
          reasoningEffort: .medium
        )
        for try await chunk in modelClient.stream(request) {
          try Task.checkCancellation()
          appendAssistantText(id: assistantID, text: chunk.text)
        }
        try Task.checkCancellation()
        if assistantText(id: assistantID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          setAssistantText(id: assistantID, text: "(No response.)")
        }
      }
    } catch is CancellationError {
      removePlaceholderIfEmpty(id: assistantID)
    } catch {
      removePlaceholderIfEmpty(id: assistantID)
      errorText = describe(error)
    }
  }

  public func systemPrompt() -> String {
    let taskFraming = context.taskFraming.isEmpty
      ? """
        Help with timing, prep, troubleshooting, and planning.
        """
      : context.taskFraming
    let base = """
      You are a concise, practical cooking assistant inside a private recipe app.
      Discuss \(context.promptSubjectDescription), described below. \(taskFraming)
      You propose and explain; you never claim to have edited or saved anything yourself.

      Answer in short plain-prose paragraphs. Use inline Markdown links when useful.
      Do not use headings, tables, horizontal rules, or bold section labels; the panel is narrow.

      \(context.serialized(for: activeTier))
      """
    return base
  }

  private func history() -> [ModelMessage] {
    messages.compactMap { message in
      guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      return ModelMessage(role: message.role == .user ? .user : .assistant, text: message.text)
    }
  }

  private func appendAssistantPlaceholder() -> RecipeChatMessage.ID {
    let id = uuid()
    messages.append(RecipeChatMessage(id: id, role: .assistant, text: ""))
    return id
  }

  private func assistantText(id: RecipeChatMessage.ID) -> String {
    messages.first { $0.id == id && $0.role == .assistant }?.text ?? ""
  }

  private func appendAssistantText(id: RecipeChatMessage.ID, text: String) {
    guard
      let index = messages.firstIndex(where: { $0.id == id && $0.role == .assistant })
    else { return }
    messages[index].text += text
  }

  private func setAssistantText(id: RecipeChatMessage.ID, text: String) {
    guard
      let index = messages.firstIndex(where: { $0.id == id && $0.role == .assistant })
    else { return }
    messages[index].text = text
  }

  private func removePlaceholderIfEmpty(id: RecipeChatMessage.ID) {
    if let index = messages.firstIndex(where: { $0.id == id && $0.role == .assistant }),
      messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      messages.remove(at: index)
    }
  }

  private func describe(_ error: any Error) -> String {
    RecipeChatErrorText.describe(error)
  }

  private func loadPersistedThread() {
    guard let subject = context.persistenceSubject else { return }
    do {
      messages = try database.write { db in
        try RecipeChatStore.pruneMessages(olderThan: RecipeChatStore.cutoff(now: now), in: db)
        return try RecipeChatStore.fetchMessages(for: subject, in: db)
      }
    } catch {
      errorText = "Could not load the saved chat for this \(context.subject)."
    }
  }

  private func persistCurrentThread() {
    guard let subject = context.persistenceSubject else { return }
    do {
      try database.write { db in
        try RecipeChatStore.replaceMessages(messages, for: subject, in: db, now: now)
      }
    } catch {
      if errorText == nil {
        errorText = "Could not save this chat locally."
      }
    }
  }

  private func defaultProvider() -> FrontierProvider {
    let availableProviders = availableProviders
    if let preferred = providerPreference.current(), availableProviders.contains(preferred) {
      return preferred
    }
    return availableProviders.first ?? .anthropic
  }

  private func defaultUseFrontier() -> Bool {
    frontierAvailable && tierPreference.current() == true
  }
}
