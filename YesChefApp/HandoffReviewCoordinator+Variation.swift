import YesChefCore

extension HandoffReviewCoordinator {
  func saveScopedVariationButtonTapped(_ review: RecipeAdjustmentReviewState) -> Result<Void, any Error> {
    guard let variationID = review.variationID, let variationName = review.variationName else {
      return .failure(HandoffReviewError.invalidVariationReview)
    }
    do {
      let derivation = try commitReviewWrite(recordWhen: { $0.isRepresentable }) { db in
        let derivation = try RecipeRepository.saveEditedVariation(
          variationID,
          resolvedDetail: review.proposedDetail,
          name: variationName,
          note: review.proposal.methodNote ?? review.variationNote,
          in: db,
          now: now
        )
        guard derivation.isRepresentable else { return derivation }
        return derivation
      }
      guard derivation.isRepresentable else {
        return .failure(HandoffReviewError.variationCannotRepresent)
      }
      adjustmentReview = nil
      return .success(())
    } catch {
      return .failure(error)
    }
  }
}
