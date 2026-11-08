import YesChefCore

extension HandoffReviewCoordinator {
  func workbenchDraftReviewItems(
    for review: AIHandoffWorkbenchDraftReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    let draft = review.draftRecipe
    if draft.hasReviewableContent {
      let originalEditableText = draft.editableProseReviewText()
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review working recipe",
          summary: draft.renderedReview(),
          presentation: .sheet,
          editableTitle: "Draft prose fields",
          editableText: originalEditableText,
          commitTitle: "Create Working Recipe",
          committingTitle: "Creating working recipe…",
          committedTitle: "Created Working Recipe",
          prepareCommit: { [weak self] in
            guard let self else { return nil }
            do {
              let existing = try await self.database.read { db -> (Recipe.ID, RecipeLibraryPlacement)? in
                guard
                  let workbench = try Workbench.find(review.workbenchID).fetchOne(db),
                  let recipeID = workbench.draftRecipeID,
                  let recipe = try Recipe.find(recipeID).fetchOne(db)
                else { return nil }
                return (recipeID, recipe.libraryPlacement)
              }
              guard let existing else {
                self.confirmedWorkbenchRecipeIDs.removeValue(forKey: review.workbenchID)
                return nil
              }
              self.confirmedWorkbenchRecipeIDs[review.workbenchID] = existing.0
              let message = existing.1 == .reference
                ? "Replaces the draft working recipe, including any edits you made to it. This can't be undone."
                : "Detaches it from this workbench and stays in your library."
              return ChatApplyReviewConfirmation(
                title: "Replace Working Recipe?",
                message: message,
                confirmTitle: "Replace Working Recipe…"
              )
            } catch {
              return nil
            }
          },
          commit: { [weak self] editedText in
            let approved = editedText == originalEditableText
              ? draft
              : draft.applyingEditableProseReviewText(editedText)
            try self?.commitWorkbenchDraftRecipe(approved, workbenchID: review.workbenchID)
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      items.append(workbenchLearningsReviewItem(workbenchID: review.workbenchID, learnings: review.learnings))
    }
    return items
  }

  func workbenchLearningsReviewItem(
    workbenchID: Workbench.ID,
    learnings: [String]
  ) -> ChatApplyReviewItem {
    let editableText = learnings.map { "- \($0)" }.joined(separator: "\n")
    return ChatApplyReviewItem(
      title: "Review learnings",
      summary: editableText,
      presentation: .sheet,
      editableTitle: "Learnings",
      editableText: editableText,
      commitTitle: "Save to Workbench Log",
      committingTitle: "Saving learnings…",
      committedTitle: "Saved to Workbench Log",
      commit: { [weak self] approvedText in
        try self?.commitWorkbenchObservation(workbenchID: workbenchID, text: "Learnings:\n\(approvedText)")
      }
    )
  }

  func commitWorkbenchDraftRecipe(_ draft: WorkbenchDraftRecipe, workbenchID: Workbench.ID) throws {
    guard draft.hasReviewableContent else { throw HandoffReviewError.emptyDeliverable }
    let confirmedRecipeID = confirmedWorkbenchRecipeIDs.removeValue(forKey: workbenchID)
    _ = try commitReviewWrite { db in
      let currentRecipeID = try Workbench.find(workbenchID).fetchOne(db)?.draftRecipeID
      guard currentRecipeID == nil || currentRecipeID == confirmedRecipeID else {
        throw HandoffReviewError.workingRecipeChanged
      }
      if currentRecipeID != nil {
        try WorkbenchRepository.removeDraftRecipe(workbenchID: workbenchID, in: db, now: now)
      }
      try WorkbenchRepository.createDraftRecipe(draft, for: workbenchID, in: db, now: now, uuid: { uuid() })
    }
  }
}
