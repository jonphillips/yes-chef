import Foundation
import YesChefCore

extension HandoffReviewCoordinator {
  func menuComplementReviewItems(
    for review: AIHandoffMenuComplementReview
  ) -> [ChatApplyReviewItem] {
    review.plan.items.map { suggestion in
      let originalEditableText = suggestion.editableReviewText()
      return ChatApplyReviewItem(
        title: suggestion.title,
        summary: suggestion.rendered(),
        presentation: .sheet,
        editableTitle: "Complement",
        editableText: originalEditableText,
        supportingEvidenceTitle: review.unparsedBlocks.isEmpty ? nil : "Couldn't parse these returned blocks",
        supportingEvidenceRows: review.unparsedBlocks,
        commitTitle: "Add to Menu",
        committingTitle: "Adding to Menu…",
        committedTitle: "Added to Menu",
        commit: { [weak self] approvedText in
          let approved = approvedText == originalEditableText
            ? suggestion
            : suggestion.applyingEditableReviewText(approvedText)
          try self?.commitMenuComplement(approved, to: review.menuID)
        }
      )
    }
  }

  func mealPlanComplementReviewItems(
    for review: AIHandoffMealPlanComplementReview
  ) -> [ChatApplyReviewItem] {
    review.plan.items.map { suggestion in
      let dayTitle = review.scheduledDate.formatted(date: .complete, time: .omitted)
      let originalEditableText = suggestion.editableReviewText(dayTitle: dayTitle)
      return ChatApplyReviewItem(
        title: suggestion.title,
        summary: suggestion.rendered(dayTitle: dayTitle),
        presentation: .sheet,
        editableTitle: "Complement",
        editableText: originalEditableText,
        supportingEvidenceTitle: review.unparsedBlocks.isEmpty ? nil : "Couldn't parse these returned blocks",
        supportingEvidenceRows: review.unparsedBlocks,
        commitTitle: "Add to Meal Plan",
        committingTitle: "Adding to Meal Plan…",
        committedTitle: "Added to Meal Plan",
        commit: { [weak self] approvedText in
          let approved = approvedText == originalEditableText
            ? suggestion
            : suggestion.applyingEditableReviewText(approvedText)
          try self?.commitMealPlanComplement(approved, on: review.scheduledDate)
        }
      )
    }
  }

  private func commitMenuComplement(_ suggestion: MenuComplementSuggestion, to menuID: Menu.ID) throws {
    _ = try database.write { db in
      try MenuRepository.addComplementItem(suggestion, to: menuID, in: db, now: now, uuid: { uuid() })
    }
  }

  private func commitMealPlanComplement(
    _ suggestion: MealPlanComplementSuggestion,
    on scheduledDate: Date
  ) throws {
    _ = try database.write { db in
      try MealCalendarRepository.addComplementItem(suggestion, on: scheduledDate, in: db, now: now, uuid: { uuid() })
    }
  }
}
