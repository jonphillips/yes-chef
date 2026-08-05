import YesChefCore

extension HandoffReviewCoordinator {
  func saveScopedVariationButtonTapped(_ review: RecipeAdjustmentReviewState) -> Bool {
    guard let variationID = review.variationID, let variationName = review.variationName else {
      return false
    }
    do {
      let derivation = try database.write { db in
        try RecipeRepository.saveEditedVariation(
          variationID,
          resolvedDetail: review.proposedDetail,
          name: variationName,
          note: review.proposal.methodNote ?? review.variationNote,
          in: db,
          now: now
        )
      }
      guard derivation.isRepresentable else {
        errorTitle = "Could Not Save Variation"
        errorMessage = "This revision includes changes that cannot be kept in a variation yet."
        isShowingError = true
        return false
      }
      adjustmentReview = nil
      return true
    } catch {
      errorTitle = "Could Not Save Variation"
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }
}
