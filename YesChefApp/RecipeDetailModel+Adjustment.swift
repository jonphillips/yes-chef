import Dependencies
import Foundation
import YesChefCore

struct RecipeAdjustmentReviewState: Identifiable, Equatable {
  let id = UUID()
  var currentDetail: RecipeDetailData
  var proposedDetail: RecipeDetailData
  var proposal: RecipeAdjustmentProposal
}

struct RecipeAdjustmentRestorePoint: Equatable {
  var recipeTitle: String
  var data: Data
}

extension RecipeDetailModel {
  func presentAdjustmentReview(_ proposal: RecipeAdjustmentProposal) throws {
    guard let detail else { return }
    let proposedDetail = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { uuid() })
    destination = .adjustmentReview(
      RecipeAdjustmentReviewState(
        currentDetail: detail,
        proposedDetail: proposedDetail,
        proposal: proposal
      )
    )
  }

  func overwriteAdjustmentButtonTapped(_ review: RecipeAdjustmentReviewState) -> Bool {
    do {
      let restorePoint = try database.write { db in
        try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          review.proposal,
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      adjustmentRestorePoint = RecipeAdjustmentRestorePoint(
        recipeTitle: review.currentDetail.recipe.title,
        data: restorePoint
      )
      destination = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func keepAdjustmentAsVariationButtonTapped(
    _ review: RecipeAdjustmentReviewState,
    name: String
  ) -> Bool {
    do {
      try database.write { db in
        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          review.proposal,
          recipeID: recipeID,
          name: name,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func activeVariationSelectionChanged(_ variationID: RecipeVariation.ID?) {
    do {
      try database.write { db in
        try RecipeRepository.setActiveVariation(
          variationID,
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func undoLastAdjustmentButtonTapped() {
    guard let restorePoint = adjustmentRestorePoint else { return }
    do {
      try database.write { db in
        try RecipeRepository.restoreRecipeAdjustment(
          restorePoint.data,
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      adjustmentRestorePoint = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

}
