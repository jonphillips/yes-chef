import Dependencies
import Foundation
import YesChefCore

extension RecipeDetailModel {
  func applyActionCatalog(for chatModel: RecipeChatModel) -> [AnyChatApplyAction] {
    @Dependency(\.makeAheadPlanClient) var makeAheadPlanClient
    @Dependency(\.chefItUpPlanClient) var chefItUpPlanClient
    @Dependency(\.serveWithPlanClient) var serveWithPlanClient
    @Dependency(\.recipeAdjustmentClient) var recipeAdjustmentClient

    let context = chatModel.context.serialized()
    let adjustRecipeAction = ChatApplyAction<RecipeAdjustmentProposal>(
      title: "Adjust this recipe",
      extractingTitle: "Drafting adjustment...",
      reviewTitle: "Review recipe adjustment",
      commitTitle: "Review Side by Side",
      committingTitle: "Opening review...",
      committedTitle: "Ready to review",
      extract: { [weak self] selection, messages in
        guard let detail = self?.detail else {
          throw RecipeDetailError.missingRecipeForAdjustment
        }
        return try await recipeAdjustmentClient(
          selection: selection,
          messages: messages,
          detail: detail,
          tier: chatModel.activeTier
        )
      },
      commit: { [weak self] proposal in
        try self?.presentAdjustmentReview(proposal)
      }
    )
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
      AnyChatApplyAction(adjustRecipeAction, requiresSubject: false, reviewPresentation: .inline) { proposal in
        proposal.reviewSummary()
      },
      AnyChatApplyAction(makeAheadAction, editableSummary: { plan in
        plan.rendered().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.rendered()
      }, commitEditedSummary: { [weak self] _, editedText in
        try self?.commitMakeAheadText(editedText)
      }),
      AnyChatApplyAction(chefItUpAction, editableSummary: { plan in
        plan.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.text
      }, commitEditedSummary: { [weak self] _, editedText in
        try self?.commitChefItUpText(editedText)
      }),
      AnyChatApplyAction(serveWithAction, editableSummary: { plan in
        plan.editableReviewText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil
          : plan.editableReviewText()
      }, commitEditedSummary: { [weak self] plan, editedText in
        try self?.commitServeWithPlan(plan.applyingEditableReviewText(editedText))
      })
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

  private func commitMakeAheadText(_ text: String) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    let approvedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !approvedText.isEmpty else {
      throw RecipeDetailError.emptyMakeAheadPlan
    }
    try database.write { db in
      try RecipeRepository.updateMakeAhead(approvedText, recipeID: recipeID, in: db, now: now)
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

  private func commitChefItUpText(_ text: String) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    let approvedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !approvedText.isEmpty else {
      throw RecipeDetailError.emptyChefItUpPlan
    }
    try database.write { db in
      try RecipeRepository.updateChefItUp(approvedText, recipeID: recipeID, in: db, now: now)
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
  case missingRecipeForAdjustment

  var description: String {
    switch self {
    case .emptyMakeAheadPlan:
      "The assistant did not find a make-ahead plan to save."
    case .emptyChefItUpPlan:
      "The assistant did not find a Chef It Up plan to save."
    case .emptyServeWithPlan:
      "The assistant did not find any accompaniments to save."
    case .missingRecipeForAdjustment:
      "The recipe could not be loaded for adjustment."
    }
  }

  var errorDescription: String? { description }
}
