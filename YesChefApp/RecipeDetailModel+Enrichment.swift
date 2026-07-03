import Dependencies
import Foundation
import YesChefCore

struct PendingIngredientSubstitution: Identifiable, Equatable {
  var lineID: IngredientLine.ID
  var ingredientText: String
  var substitution: String

  var id: IngredientLine.ID { lineID }
}

extension RecipeDetailModel {
  func applyActionCatalog(for chatModel: RecipeChatModel) -> [AnyChatApplyAction] {
    @Dependency(\.makeAheadPlanClient) var makeAheadPlanClient
    @Dependency(\.chefItUpPlanClient) var chefItUpPlanClient
    @Dependency(\.serveWithPlanClient) var serveWithPlanClient

    let context = chatModel.context.serialized()
    let makeAheadAction = ChatApplyAction<MakeAheadPlan>(
      title: "Summarize make-ahead -> Make-ahead section",
      extractingTitle: "Summarizing make-ahead...",
      reviewTitle: "Review make-ahead",
      commitTitle: "Commit to Make-ahead",
      committingTitle: "Saving make-ahead...",
      committedTitle: "Saved to Make-ahead",
      extract: { selection, messages in
        try await makeAheadPlanClient(selection: selection, messages: messages, context: context, tier: chatModel.activeTier)
      },
      commit: { [weak self] plan in
        try self?.commitMakeAheadPlan(plan)
      }
    )
    let chefItUpAction = ChatApplyAction<ChefItUpPlan>(
      title: "Chef It Up -> Chef It Up section",
      extractingTitle: "Building Chef It Up...",
      reviewTitle: "Review Chef It Up",
      commitTitle: "Commit to Chef It Up",
      committingTitle: "Saving Chef It Up...",
      committedTitle: "Saved to Chef It Up",
      extract: { selection, messages in
        try await chefItUpPlanClient(selection: selection, messages: messages, context: context, tier: chatModel.activeTier)
      },
      commit: { [weak self] plan in
        try self?.commitChefItUpPlan(plan)
      }
    )
    let serveWithAction = ChatApplyAction<ServeWithPlan>(
      title: "Serve With -> Serve With section",
      extractingTitle: "Finding accompaniments...",
      reviewTitle: "Review Serve With",
      commitTitle: "Add to Serve With",
      committingTitle: "Saving Serve With...",
      committedTitle: "Saved to Serve With",
      extract: { selection, messages in
        try await serveWithPlanClient(selection: selection, messages: messages, context: context, tier: chatModel.activeTier)
      },
      commit: { [weak self] plan in
        try self?.commitServeWithPlan(plan)
      }
    )
    return [
      AnyChatApplyAction(makeAheadAction) { plan in
        plan.rendered().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.rendered()
      },
      AnyChatApplyAction(chefItUpAction) { plan in
        plan.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.text
      },
      AnyChatApplyAction(serveWithAction) { plan in
        plan.rendered().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.rendered()
      }
    ]
  }

  func clearChefItUpButtonTapped() {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    do {
      try database.write { db in
        try RecipeRepository.clearChefItUp(recipeID: recipeID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func removeServeWithButtonTapped(_ itemID: ServeWithItem.ID) {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    do {
      try database.write { db in
        try RecipeRepository.removeServeWithItem(itemID, recipeID: recipeID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func findSubstituteButtonTapped(lineID: IngredientLine.ID) async {
    @Dependency(\.ingredientSubstitutionClient) var ingredientSubstitutionClient

    guard
      let detail,
      let line = detail.ingredientLines.first(where: { $0.id == lineID })
    else { return }

    isFindingSubstitution = true
    defer { isFindingSubstitution = false }

    do {
      let suggestion = try await ingredientSubstitutionClient(
        ingredient: line.originalText,
        context: RecipeChatRecipeContext(detail: detail).serialized(),
        tier: .onDevice
      )
      let text = suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        throw RecipeDetailError.emptyIngredientSubstitution
      }
      pendingSubstitution = PendingIngredientSubstitution(
        lineID: line.id,
        ingredientText: line.originalText,
        substitution: text
      )
    } catch {
      errorMessage = RecipeChatErrorText.describe(error)
      isShowingError = true
    }
  }

  func savePendingSubstitutionButtonTapped() {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    guard let pendingSubstitution else { return }
    do {
      try database.write { db in
        try RecipeRepository.setIngredientSubstitution(
          pendingSubstitution.substitution,
          lineID: pendingSubstitution.lineID,
          recipeID: recipeID,
          now: now,
          in: db
        )
      }
      self.pendingSubstitution = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func clearSubstitutionButtonTapped(lineID: IngredientLine.ID) {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    do {
      try database.write { db in
        try RecipeRepository.setIngredientSubstitution(nil, lineID: lineID, recipeID: recipeID, now: now, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  private func commitMakeAheadPlan(_ plan: MakeAheadPlan) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    guard !plan.rendered().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RecipeDetailError.emptyMakeAheadPlan
    }
    try database.write { db in
      try RecipeRepository.applyMakeAheadPlan(plan, to: recipeID, in: db, now: now)
    }
  }

  private func commitChefItUpPlan(_ plan: ChefItUpPlan) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    guard !plan.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RecipeDetailError.emptyChefItUpPlan
    }
    try database.write { db in
      try RecipeRepository.applyChefItUpPlan(plan, to: recipeID, in: db, now: now)
    }
  }

  private func commitServeWithPlan(_ plan: ServeWithPlan) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid

    guard !plan.items.isEmpty else {
      throw RecipeDetailError.emptyServeWithPlan
    }
    try database.write { db in
      try RecipeRepository.appendServeWithPlan(plan, to: recipeID, in: db, now: now) {
        uuid()
      }
    }
  }
}

private enum RecipeDetailError: Error, CustomStringConvertible, LocalizedError {
  case emptyMakeAheadPlan
  case emptyChefItUpPlan
  case emptyServeWithPlan
  case emptyIngredientSubstitution

  var description: String {
    switch self {
    case .emptyMakeAheadPlan:
      "The assistant did not find a make-ahead plan to save."
    case .emptyChefItUpPlan:
      "The assistant did not find a Chef It Up plan to save."
    case .emptyServeWithPlan:
      "The assistant did not find any accompaniments to save."
    case .emptyIngredientSubstitution:
      "The assistant did not find a substitution to save."
    }
  }

  var errorDescription: String? { description }
}
