import Dependencies
import Foundation

public struct RecipeHandoffContext: Equatable, Sendable {
  public let recipe: RecipeChatRecipeContext

  public init(detail: RecipeDetailData) {
    self.recipe = RecipeChatRecipeContext(detail: detail)
  }

  public init(recipe: RecipeChatRecipeContext) {
    self.recipe = recipe
  }

  public func prompt(for section: PlaybookSectionKind) -> String {
    @Dependency(\.aiPromptPreferences) var preferences
    let settings = preferences.current()
    let context = bounded(recipe.serialized(excludingPlaybookSections: [section]))
    let knownLearnings = Self.knownLearningsBlock(recipe.learnings)

    switch section {
    case .makeAhead:
      return Self.makeAheadPrompt(
        context: context,
        knownLearnings: knownLearnings,
        tasteProfile: settings.tasteProfile,
        makeAheadPreference: AISettingsRepository.preference(in: settings, for: .makeAheadPrepPlan)
      )
    case .chefItUp:
      return Self.chefItUpPrompt(
        context: context,
        knownLearnings: knownLearnings,
        tasteProfile: settings.tasteProfile,
        chefItUpPreference: AISettingsRepository.preference(in: settings, for: .chefItUp)
      )
    case .serveWith:
      return Self.serveWithPrompt(
        context: context,
        knownLearnings: knownLearnings,
        tasteProfile: settings.tasteProfile,
        serveWithPreference: AISettingsRepository.preference(in: settings, for: .serveWith)
      )
    }
  }

  private static func knownLearningsBlock(_ learnings: [String]) -> String {
    let items = learnings
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !items.isEmpty else { return "" }
    return """

    Already-captured learnings for this recipe — do NOT repeat these; in the learnings section return only \
    genuinely new, durable learnings established this session that are not already listed:
    \(items.map { "- \($0)" }.joined(separator: "\n"))
    """
  }

  private static func makeAheadPrompt(
    context: String,
    knownLearnings: String,
    tasteProfile: String,
    makeAheadPreference: String
  ) -> String {
    """
    You are preparing practical make-ahead notes for one recipe. Preserve the recipe's authored method and
    ingredients as context; suggest only work that can happen before cooking or serving. Do not rewrite the
    recipe or turn the response into a merged mega-recipe.

    Taste profile:
    \(tasteProfile)

    Make-ahead preferences:
    \(makeAheadPreference)

    The return must be plain, paste-ready review text — not JSON — because the cook reviews and edits it in
    Yes Chef before it is saved.
    \(knownLearnings)
    \(context)
    """
  }

  private static func chefItUpPrompt(
    context: String,
    knownLearnings: String,
    tasteProfile: String,
    chefItUpPreference: String
  ) -> String {
    """
    You are preparing practical Chef It Up notes for one recipe. Suggest concrete technique and flavor upgrades;
    do not rewrite the recipe or turn the response into a merged mega-recipe.

    Taste profile:
    \(tasteProfile)

    Chef It Up preferences:
    \(chefItUpPreference)

    The return must be plain, paste-ready review text — not JSON — because the cook reviews and edits it in
    Yes Chef before it is saved.
    \(knownLearnings)
    \(context)
    """
  }

  private static func serveWithPrompt(
    context: String,
    knownLearnings: String,
    tasteProfile: String,
    serveWithPreference: String
  ) -> String {
    """
    You are suggesting accompaniments for one recipe. Return one suggestion per line, exactly as `title: note`
    (or `title` when no note is useful). Do not use bullets, Markdown emphasis, an introduction, JSON, or any
    other text. Do not rewrite the recipe or turn the response into a merged mega-recipe.

    Taste profile:
    \(tasteProfile)

    Serve With preferences:
    \(serveWithPreference)

    The cook reviews and edits the returned lines in Yes Chef before saving them.
    \(knownLearnings)
    \(context)
    """
  }
}

public struct MealPlanHandoffContext: Equatable, Sendable {
  public let title: String
  public let rows: [MealPlanItemRowData]
  public let recipeMethodLinesByID: [Recipe.ID: [String]]

  public init(
    title: String,
    rows: [MealPlanItemRowData],
    recipeMethodLinesByID: [Recipe.ID: [String]]
  ) {
    self.title = title
    self.rows = rows
    self.recipeMethodLinesByID = recipeMethodLinesByID
  }

  public func makeAheadPrompt() -> String {
    @Dependency(\.aiPromptPreferences) var preferences
    let settings = preferences.current()
    return Self.makeAheadPrompt(
      context: bounded(serialized()),
      tasteProfile: settings.tasteProfile,
      makeAheadPreference: AISettingsRepository.preference(in: settings, for: .makeAheadPrepPlan)
    )
  }

  public func serialized() -> String {
    var lines = ["The user is looking at this meal-plan day:", "- Date: \(title)"]
    let sortedRows = rows.sorted { lhs, rhs in
      if lhs.item.mealSlot.sortOrder != rhs.item.mealSlot.sortOrder {
        return lhs.item.mealSlot.sortOrder < rhs.item.mealSlot.sortOrder
      }
      return lhs.item.sortOrder < rhs.item.sortOrder
    }
    guard !sortedRows.isEmpty else {
      lines.append("Meal plan items: none included.")
      return lines.joined(separator: "\n")
    }

    lines.append("Meal plan item summaries:")
    for row in sortedRows {
      lines.append("- \(row.displayTitle.isEmpty ? "(untitled)" : row.displayTitle)")
      lines.append("  - Meal slot: \(row.item.mealSlot.title)")
      lines.append("  - Kind: \(row.item.kind.title)")
      if let recipe = row.recipe {
        if let prepTimeMinutes = recipe.prepTimeMinutes {
          lines.append("  - Prep time: \(prepTimeMinutes) minutes")
        }
        if let cookTimeMinutes = recipe.cookTimeMinutes {
          lines.append("  - Cook time: \(cookTimeMinutes) minutes")
        }
        if let totalTimeMinutes = recipe.totalTimeMinutes {
          lines.append("  - Total time: \(totalTimeMinutes) minutes")
        }
      }
      if !row.recipeIngredientLines.isEmpty {
        lines.append("  - Ingredients:")
        lines.append(contentsOf: row.recipeIngredientLines.map { "    - \($0)" })
      }
      if let recipeID = row.recipe?.id, let method = recipeMethodLinesByID[recipeID], !method.isEmpty {
        lines.append("  - Method:")
        lines.append(contentsOf: method.map { "    - \($0)" })
      }
      if let makeAhead = row.recipe?.makeAhead {
        lines.append("  - Existing recipe make-ahead note, verbatim:")
        lines.append(makeAhead)
      }
      if let notes = row.item.notes {
        lines.append("  - Meal plan item notes: \(notes)")
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func makeAheadPrompt(
    context: String,
    tasteProfile: String,
    makeAheadPreference: String
  ) -> String {
    """
    You are preparing a day-scoped make-ahead strategy for this meal plan. Compose a short sequence of
    distinct prep tasks across the day's dishes. Keep recipe instructions with their recipes; do not create
    choreography or a merged mega-recipe.

    Taste profile:
    \(tasteProfile)

    Make-ahead preferences:
    \(makeAheadPreference)

    The return must be plain, paste-ready review text — not JSON — because the cook reviews and edits it in
    Yes Chef before it is saved. Use this deliverable format:
    Make-ahead strategy - Dinner
    Two days ahead: Make the sauce.

    \(context)
    """
  }
}

private func bounded(_ context: String) -> String {
  let budget = MenuChatContext.frontierSerializedCharacterBudget
  guard context.count > budget else { return context }
  let end = context.index(context.startIndex, offsetBy: budget)
  return String(context[..<end])
    .trimmingCharacters(in: .whitespacesAndNewlines)
    + "\n\nContext was truncated at Yes Chef's frontier handoff budget."
}
