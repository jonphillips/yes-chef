import Foundation
import YesChefCore

extension HandoffReviewCoordinator {
  /// All external hand-off doors present a staged result through the same router.
  func presentStaged(
    _ result: AIHandoffReviewResult,
    pendingHandoff: AIHandoff? = nil,
    preservingQueue: Bool = false,
    toastCenter: AppToastCenter? = nil
  ) async {
    if !preservingQueue { recipeReturnToastCenter = toastCenter }
    if case let .recipeNew(_, text) = result.review {
      if !preservingQueue { discardAll() }
      await createRecipeCoordinator.stage(text: text)
      newRecipeWarning = result.warning
    } else {
      present(result.review, warning: result.warning, pendingHandoff: pendingHandoff)
    }
  }

  func fileUnlabeled(_ text: String, label: String, handoffID: UUID, recipeID: UUID) async throws {
    if label == "YC-NEW-RECIPE:" {
      guard try RecipeAdjustmentFinalize.classify(payload: text) == .newRecipe else {
        throw AIHandoffIntentImportError.invalidNewRecipe
      }
      await presentStaged(.init(review: .recipeNew(handoffID: handoffID, text: text), warning: nil),
        preservingQueue: true)
      review = nil
      recipeReturnToastCenter?.postSuccess("New recipe sent to Create Recipe.")
      return
    }
    let handoff = AIHandoff(id: handoffID, sourceType: .recipe, sourceID: recipeID,
      taskType: .recipe, createdAt: now, exportedPrompt: "")
    let staged = try await database.read { db in
      try AIHandoffIntentImport.stageOnboardReview(handoff: handoff, result: "\(label)\n " + text.replacingOccurrences(of: "\nYC-", with: "\n YC-"), in: db)
    }
    if case let .recipeItems(_, items) = staged.review {
      pendingRecipeReviews.insert(contentsOf: items, at: 0)
    }
    review = nil
  }

}

extension HandoffReviewCoordinator {
  func setPresentedReview(_ review: AIHandoffReview) {
    pendingRecipeReviews = []
    if case let .recipeItems(id, items) = review {
      let ordinary = items.filter {
        switch $0 {
        case .recipeAdjustmentBrief, .recipeUnfiled: false
        default: true
        }
      }
      pendingRecipeReviews = items.filter {
        switch $0 {
        case .recipeAdjustmentBrief, .recipeUnfiled: true
        default: false
        }
      }
      if ordinary.isEmpty {
        self.review = pendingRecipeReviews.isEmpty ? nil : pendingRecipeReviews.removeFirst()
      } else {
        self.review = .recipeItems(handoffID: id, items: ordinary)
      }
    } else {
      self.review = review
    }
  }
}
