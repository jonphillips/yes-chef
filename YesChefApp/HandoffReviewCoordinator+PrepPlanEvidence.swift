import YesChefCore

extension HandoffReviewCoordinator {
  func prepPlanEvidenceTitle(for review: AIHandoffMenuPrepPlanReview) -> String? {
    if review.unparsedPlanLines.isEmpty,
      review.advisoryNotes.isEmpty,
      review.prepPlanIntent == .regenerate,
      review.replacementStepCount > 0
    {
      return "This replaces your \(review.replacementStepCount)-step prep plan"
    }
    return switch (review.unparsedPlanLines.isEmpty, review.advisoryNotes.isEmpty) {
    case (true, true): nil
    case (false, true): "Couldn't parse — fix or remove these lines before saving"
    case (true, false): "Review omitted steps before saving"
    case (false, false): "Review before saving"
    }
  }
}

extension HandoffReviewCoordinator {
  /// All external hand-off doors present a staged result through the same router.
  func presentStaged(
    _ result: AIHandoffReviewResult,
    pendingHandoff: AIHandoff? = nil
  ) async {
    if case let .recipeNew(_, text) = result.review {
      await createRecipeCoordinator.stage(text: text)
      contractWarning = result.warning
    } else {
      present(result.review, warning: result.warning, pendingHandoff: pendingHandoff)
    }
  }

  func fileUnlabeled(_ text: String, label: String, handoffID: UUID, recipeID: UUID) throws {
    let handoff = AIHandoff(id: handoffID, sourceType: .recipe, sourceID: recipeID,
      taskType: .recipe, createdAt: now, exportedPrompt: "")
    let staged = try database.read { db in
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
