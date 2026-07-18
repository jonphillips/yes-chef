import Dependencies
import Foundation
import YesChefCore

extension RecipeDetailModel {
  func applyActionCatalog(for chatModel: RecipeChatModel) -> [AnyChatApplyAction] {
    @Dependency(\.makeAheadPlanClient) var makeAheadPlanClient
    @Dependency(\.chefItUpPlanClient) var chefItUpPlanClient
    @Dependency(\.serveWithPlanClient) var serveWithPlanClient
    @Dependency(\.recipeAdjustmentClient) var recipeAdjustmentClient
    @Dependency(\.menuNoteHarvestClient) var noteHarvestClient

    let context = chatModel.context.serialized()
    let adjustRecipeAction = ChatApplyAction<RecipeAdjustmentProposal>(
      title: "Revise Recipe",
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
      title: "Create Prep Plan",
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
      title: "Chef It Up",
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
      title: "Suggest Dishes",
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
    // ADR-0027 S2 — the recipe sibling of the menu "Capture to menu" harvest verb. Extraction,
    // not generation: captures a chat selection (or, absent one, the assistant transcript) into
    // one or more `.general` recipe notes. Per D2 the recipe is the write target, not source
    // material — so, exactly like the menu sibling, NO `context:` is sent to the client.
    let captureNoteAction = ChatApplyAction<MenuNoteHarvestPlan>(
      title: "Save to Notes",
      extractingTitle: "Capturing…",
      reviewTitle: "Review captured note",
      commitTitle: "Add to Notes",
      committingTitle: "Adding to notes…",
      committedTitle: "Added to Notes",
      extract: { selection, messages in
        try await noteHarvestClient(
          selection: selection,
          messages: messages,
          tier: chatModel.activeTier
        )
      },
      commit: { _ in
      }
    )
    return [
      AnyChatApplyAction(
        adjustRecipeAction,
        requiresSubject: false,
        reviewPresentation: .inline,
        systemImage: "pencil.and.outline"
      ) { proposal in
        proposal.reviewSummary()
      },
      AnyChatApplyAction(makeAheadAction, systemImage: "clock.badge.checkmark", editableSummary: { plan in
        plan.rendered().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.rendered()
      }, commitEditedSummary: { [weak self] _, editedText in
        try self?.commitMakeAheadText(editedText)
      }),
      AnyChatApplyAction(chefItUpAction, systemImage: "wand.and.stars", editableSummary: { plan in
        plan.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plan.text
      }, commitEditedSummary: { [weak self] _, editedText in
        try self?.commitChefItUpText(editedText)
      }),
      AnyChatApplyAction(serveWithAction, systemImage: "fork.knife.circle", editableSummary: { plan in
        plan.editableReviewText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil
          : plan.editableReviewText()
      }, commitEditedSummary: { [weak self] plan, editedText in
        try self?.commitServeWithPlan(plan.applyingEditableReviewText(editedText))
      }),
      // `requiresSubject: false` so the no-selection transcript-scan branch stays live in
      // production ([[harvest-verb-requires-subject-false]]); a list commit shape, one review
      // item per captured note through the ADR-0026 collection sheet.
      AnyChatApplyAction(
        captureNoteAction,
        requiresSubject: false,
        systemImage: "note.text.badge.plus"
      ) { [weak self] plan in
        plan.notes.map { note in
          let originalEditableText = note.editableReviewText()
          return ChatApplyReviewItem(
            title: note.title,
            summary: note.rendered(),
            editableTitle: "Note",
            editableText: originalEditableText,
            commitTitle: captureNoteAction.commitTitle,
            committingTitle: captureNoteAction.committingTitle,
            committedTitle: captureNoteAction.committedTitle,
            commit: { editedText in
              let approved = editedText == originalEditableText
                ? note
                : note.applyingEditableReviewText(editedText)
              try self?.commitCapturedNote(approved)
            }
          )
        }
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

  func commitMakeAheadText(_ text: String) throws {
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

  func commitChefItUpText(_ text: String) throws {
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

  private func commitCapturedNote(_ note: HarvestedNote) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid

    let text = note.rendered().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw RecipeDetailError.emptyCapturedNote
    }
    try database.write { db in
      _ = try RecipeRepository.appendRecipeNote(
        recipeID: recipeID,
        text: text,
        noteType: .general,
        in: db,
        now: now,
        uuid: { uuid() }
      )
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

  func commitServeWithText(_ text: String) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid

    let plan = ServeWithPlan().applyingEditableReviewText(text)
    guard !plan.items.isEmpty else {
      throw RecipeDetailError.emptyServeWithPlan
    }

    try database.write { db in
      try RecipeRepository.replaceServeWithPlan(
        plan,
        recipeID: recipeID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  func clearServeWithButtonTapped() {
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    do {
      try database.write { db in
        try RecipeRepository.clearServeWith(recipeID: recipeID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

}

private enum RecipeDetailError: Error, CustomStringConvertible, LocalizedError {
  case emptyMakeAheadPlan
  case emptyChefItUpPlan
  case emptyServeWithPlan
  case emptyCapturedNote
  case missingRecipeForAdjustment

  var description: String {
    switch self {
    case .emptyMakeAheadPlan:
      "The assistant did not find a make-ahead plan to save."
    case .emptyChefItUpPlan:
      "The assistant did not find a Chef It Up plan to save."
    case .emptyServeWithPlan:
      "The assistant did not find any accompaniments to save."
    case .emptyCapturedNote:
      "The assistant did not find a note to capture."
    case .missingRecipeForAdjustment:
      "The recipe could not be loaded for adjustment."
    }
  }

  var errorDescription: String? { description }
}
