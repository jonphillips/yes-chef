import YesChefCore

extension HandoffReviewCoordinator {
  func prepPlanEvidenceTitle(for review: AIHandoffMenuPrepPlanReview) -> String? {
    switch (review.unparsedPlanLines.isEmpty, review.advisoryNotes.isEmpty) {
    case (true, true): nil
    case (false, true): "Couldn't parse — fix or remove these lines before saving"
    case (true, false): "Review omitted steps before saving"
    case (false, false): "Review before saving"
    }
  }
}
