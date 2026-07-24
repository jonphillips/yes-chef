import Dependencies
import Foundation
import LLMClientKit
import Observation
import SQLiteData
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class HandoffReviewCoordinator {
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  var review: AIHandoffReview?
  var adjustmentReview: RecipeAdjustmentReviewState?
  var errorMessage: String?
  var errorTitle = "Could Not Save Handoff"
  var isShowingError = false

  func present(_ review: AIHandoffReview) {
    self.review = review
  }

  func reviewItems(for review: AIHandoffReview) -> [ChatApplyReviewItem] {
    switch review {
    case let .menuPrepPlan(review):
      menuPrepPlanReviewItems(for: review)
    case let .recipeMakeAhead(review):
      recipeMakeAheadReviewItems(for: review)
    case let .recipeChefItUp(review):
      recipeChefItUpReviewItems(for: review)
    case let .recipeServeWith(review):
      recipeServeWithReviewItems(for: review)
    case .recipeAdjustmentBrief:
      []
    case let .mealPlanMakeAhead(review):
      mealPlanMakeAheadReviewItems(for: review)
    case let .workbenchCompare(review):
      workbenchCompareReviewItems(for: review)
    case .workbenchExperiments:
      []
    }
  }

  private func menuPrepPlanReviewItems(
    for review: AIHandoffMenuPrepPlanReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.plan.steps.isEmpty || !review.unparsedPlanLines.isEmpty {
      let editableText = reviewEditablePrepPlanText(review)
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review prep plan",
          summary: editableText,
          presentation: .sheet,
          editableTitle: "Prep plan",
          editableText: editableText,
          supportingEvidenceTitle: review.unparsedPlanLines.isEmpty
            ? nil
            : "Couldn't parse — fix or remove these lines before saving",
          supportingEvidenceRows: review.unparsedPlanLines,
          commitTitle: "Save Prep Plan",
          committingTitle: "Saving Prep Plan…",
          committedTitle: "Saved Prep Plan",
          commit: { [weak self] approvedText in
            try self?.commitPrepPlan(review, approvedText: approvedText)
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      let editableText = review.learnings.map { "- \($0)" }.joined(separator: "\n")
      items.append(
        ChatApplyReviewItem(
          title: "Review learnings",
          summary: editableText,
          presentation: .sheet,
          editableTitle: "Learnings",
          editableText: editableText,
          commitTitle: "Save Learnings",
          committingTitle: "Saving Learnings…",
          committedTitle: "Saved Learnings",
          commit: { [weak self] approvedText in
            try self?.commitLearnings(review, approvedText: approvedText)
          }
        )
      )
    }
    return items
  }

  private func recipeMakeAheadReviewItems(
    for review: AIHandoffRecipeMakeAheadReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.makeAhead.isEmpty {
      let currentMakeAhead = review.currentMakeAhead.flatMap(Self.nonEmpty)
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review make-ahead",
          summary: review.makeAhead,
          presentation: .sheet,
          editableTitle: "Make-ahead",
          editableText: review.makeAhead,
          supportingEvidenceTitle: currentMakeAhead == nil ? nil : "Currently saved",
          supportingEvidenceRows: currentMakeAhead.map { [$0] } ?? [],
          commitTitle: currentMakeAhead == nil ? "Save Make-ahead" : "Replace",
          committingTitle: "Saving Make-ahead…",
          committedTitle: "Saved Make-ahead",
          secondaryCommit: currentMakeAhead.map { currentMakeAhead in
            ChatApplyReviewSecondaryCommit(title: "Append") { [weak self] approvedText in
              try self?.commitRecipeMakeAhead(
                review,
                approvedText: Self.appending(approvedText, to: currentMakeAhead)
              )
            }
          },
          commit: { [weak self] approvedText in
            try self?.commitRecipeMakeAhead(review, approvedText: approvedText)
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      items.append(
        learningsReviewItem(
          sourceType: .recipe,
          sourceID: review.recipeID,
          learnings: review.learnings
        )
      )
    }
    return items
  }

  private func recipeChefItUpReviewItems(
    for review: AIHandoffRecipeSectionReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.text.isEmpty {
      let currentChefItUp = review.currentText.flatMap(Self.nonEmpty)
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review Chef It Up",
          summary: review.text,
          presentation: .sheet,
          editableTitle: "Chef It Up",
          editableText: review.text,
          supportingEvidenceTitle: currentChefItUp == nil ? nil : "Currently saved",
          supportingEvidenceRows: currentChefItUp.map { [$0] } ?? [],
          commitTitle: currentChefItUp == nil ? "Save Chef It Up" : "Replace",
          committingTitle: "Saving Chef It Up…",
          committedTitle: "Saved Chef It Up",
          secondaryCommit: currentChefItUp.map { currentChefItUp in
            ChatApplyReviewSecondaryCommit(title: "Append") { [weak self] approvedText in
              try self?.commitRecipeChefItUp(
                review,
                approvedText: Self.appending(approvedText, to: currentChefItUp)
              )
            }
          },
          commit: { [weak self] approvedText in
            try self?.commitRecipeChefItUp(review, approvedText: approvedText)
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      items.append(learningsReviewItem(
        sourceType: .recipe,
        sourceID: review.recipeID,
        learnings: review.learnings
      ))
    }
    return items
  }

  private func recipeServeWithReviewItems(
    for review: AIHandoffRecipeSectionReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.text.isEmpty {
      let currentPlan = ServeWithPlan(
        items: review.currentServeWith.map { ServeWithSuggestion(title: $0.title, note: $0.note) }
      )
      let returnedPlan = ServeWithPlan().applyingEditableReviewText(review.text)
      let editableText = currentPlan.unioning(returnedPlan).editableReviewText()
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review Serve With",
          summary: review.text,
          presentation: .sheet,
          editableTitle: "Serve With",
          editableText: editableText,
          supportingEvidenceTitle: currentPlan.items.isEmpty ? nil : "Currently saved",
          supportingEvidenceRows: currentPlan.items.isEmpty ? [] : [currentPlan.editableReviewText()],
          commitTitle: "Save Serve With",
          committingTitle: "Saving Serve With…",
          committedTitle: "Saved Serve With",
          commit: { [weak self] approvedText in
            try self?.commitRecipeServeWith(review, approvedText: approvedText)
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      items.append(learningsReviewItem(
        sourceType: .recipe,
        sourceID: review.recipeID,
        learnings: review.learnings
      ))
    }
    return items
  }

  private func mealPlanMakeAheadReviewItems(
    for review: AIHandoffMealPlanMakeAheadReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.strategy.steps.isEmpty || !review.unparsedStrategyLines.isEmpty {
      let editableText = [
        review.strategy.editableReviewText(),
        review.unparsedStrategyLines.joined(separator: "\n"),
      ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review make-ahead strategy",
          summary: editableText,
          presentation: .sheet,
          editableTitle: "Make-ahead strategy",
          editableText: editableText,
          supportingEvidenceTitle: review.unparsedStrategyLines.isEmpty
            ? nil
            : "Couldn't parse — fix or remove these lines before saving",
          supportingEvidenceRows: review.unparsedStrategyLines,
          commitTitle: "Add Strategy Note",
          committingTitle: "Adding Strategy Note…",
          committedTitle: "Added Strategy Note",
          commit: { [weak self] approvedText in
            try self?.commitMealPlanMakeAhead(review, approvedText: approvedText)
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      items.append(learningsReviewItem(
        sourceType: .mealPlan,
        sourceID: review.mealPlanItemID,
        learnings: review.learnings
      ))
    }
    return items
  }

  private func workbenchCompareReviewItems(
    for review: AIHandoffWorkbenchCompareReview
  ) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.comparison.isEmpty {
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review comparison",
          summary: review.comparison,
          presentation: .sheet,
          editableTitle: "Comparison",
          editableText: review.comparison,
          commitTitle: "Save to Workbench Log",
          committingTitle: "Saving comparison…",
          committedTitle: "Saved to Workbench Log",
          commit: { [weak self] approvedText in
            try self?.commitWorkbenchObservation(
              workbenchID: review.workbenchID,
              text: approvedText
            )
          }
        )
      )
    }
    if !review.learnings.isEmpty {
      let editableText = review.learnings.map { "- \($0)" }.joined(separator: "\n")
      items.append(
        ChatApplyReviewItem(
          title: "Review learnings",
          summary: editableText,
          presentation: .sheet,
          editableTitle: "Learnings",
          editableText: editableText,
          commitTitle: "Save to Workbench Log",
          committingTitle: "Saving learnings…",
          committedTitle: "Saved to Workbench Log",
          commit: { [weak self] approvedText in
            try self?.commitWorkbenchObservation(
              workbenchID: review.workbenchID,
              text: "Learnings:\n\(approvedText)"
            )
          }
        )
      )
    }
    return items
  }

  private func reviewEditablePrepPlanText(_ review: AIHandoffMenuPrepPlanReview) -> String {
    [review.plan.editableReviewText(), review.unparsedPlanLines.joined(separator: "\n")]
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  func commitPrepPlan(_ review: AIHandoffMenuPrepPlanReview, approvedText: String) throws {
    let parsed = review.plan.parsingEditableReviewText(approvedText)
    guard parsed.unparsedLines.isEmpty else {
      throw AIHandoffMenuPrepPlanImportError.unparsedPlanText(parsed.unparsedLines)
    }
    let plan = parsed.plan
    guard !plan.steps.isEmpty else { throw AIHandoffMenuPrepPlanImportError.emptyPlan }
    try database.write { db in
      try MenuRepository.applyPrepPlan(plan, to: review.menuID, in: db, now: now, uuid: { uuid() })
    }
  }

  func commitLearnings(_ review: AIHandoffMenuPrepPlanReview, approvedText: String) throws {
    try commitLearnings(
      sourceType: .menu,
      sourceID: review.menuID,
      approvedText: approvedText
    )
  }

  private func learningsReviewItem(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    learnings: [String]
  ) -> ChatApplyReviewItem {
    let editableText = learnings.map { "- \($0)" }.joined(separator: "\n")
    return ChatApplyReviewItem(
      title: "Review learnings",
      summary: editableText,
      presentation: .sheet,
      editableTitle: "Learnings",
      editableText: editableText,
      commitTitle: "Save Learnings",
      committingTitle: "Saving Learnings…",
      committedTitle: "Saved Learnings",
      commit: { [weak self] approvedText in
        try self?.commitLearnings(sourceType: sourceType, sourceID: sourceID, approvedText: approvedText)
      }
    )
  }

  private func commitRecipeMakeAhead(
    _ review: AIHandoffRecipeMakeAheadReview,
    approvedText: String
  ) throws {
    let makeAhead = approvedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !makeAhead.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    try database.write { db in
      try RecipeRepository.updateMakeAhead(makeAhead, recipeID: review.recipeID, in: db, now: now)
    }
  }

  private func commitRecipeChefItUp(
    _ review: AIHandoffRecipeSectionReview,
    approvedText: String
  ) throws {
    let chefItUp = approvedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !chefItUp.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    try database.write { db in
      try RecipeRepository.updateChefItUp(chefItUp, recipeID: review.recipeID, in: db, now: now)
    }
  }

  private func commitRecipeServeWith(
    _ review: AIHandoffRecipeSectionReview,
    approvedText: String
  ) throws {
    let plan = ServeWithPlan().applyingEditableReviewText(approvedText)
    guard !plan.items.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    try database.write { db in
      try RecipeRepository.replaceServeWithPlan(
        plan,
        recipeID: review.recipeID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  private static func appending(_ returnedText: String, to currentText: String) -> String {
    [currentText, returnedText].joined(separator: "\n\n")
  }

  private static func nonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func commitMealPlanMakeAhead(
    _ review: AIHandoffMealPlanMakeAheadReview,
    approvedText: String
  ) throws {
    let parsed = MealPlanMakeAheadStrategy.parsingEditableReviewText(approvedText)
    guard parsed.unparsedLines.isEmpty else {
      throw HandoffReviewError.unparsedStrategyText(parsed.unparsedLines)
    }
    guard !parsed.strategy.steps.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    _ = try database.write { db in
      try MealCalendarRepository.addMakeAheadStrategyNote(
        parsed.strategy,
        on: review.scheduledDate,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  private func commitLearnings(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    approvedText: String
  ) throws {
    let learnings = AIHandoffReturn.learningBullets(from: approvedText)
    guard !learnings.isEmpty else { throw HandoffReviewError.emptyLearnings }
    _ = try database.write { db in
      // Exact-dedup on ingest against what's already stored (ADR-0038 Amd 4). All-duplicate commits
      // insert nothing and succeed — the review item is still consumed.
      try LearningRepository.insertNew(
        texts: learnings,
        sourceType: sourceType,
        sourceID: sourceID,
        provenance: .externalHandoff,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  private func commitWorkbenchObservation(
    workbenchID: Workbench.ID,
    text: String
  ) throws {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    _ = try database.write { db in
      try WorkbenchRepository.addLogEntry(
        WorkbenchLogEntryDraft(kind: .observation, body: body),
        to: workbenchID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  func commitWorkbenchExperiment(
    _ experiment: WorkbenchExperiment,
    to workbenchID: Workbench.ID
  ) throws {
    _ = try database.write { db in
      try WorkbenchRepository.addLogEntry(
        WorkbenchLogEntryDraft(
          kind: .experiment,
          body: "",
          hypothesis: experiment.hypothesis,
          change: experiment.change,
          rationale: experiment.rationale
        ),
        to: workbenchID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  func draftRecipeAdjustment(
    _ review: AIHandoffRecipeAdjustmentBriefReview,
    brief: String
  ) async throws -> RecipeAdjustmentReviewState {
    @Dependency(\.recipeAdjustmentClient) var recipeAdjustmentClient
    @Dependency(\.apiKeyStore) var apiKeyStore
    @Dependency(\.recipeChatProviderPreference) var providerPreference

    let trimmedBrief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBrief.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    guard let detail = try await database.read({ db in
      try RecipeDetailRequest(recipeID: review.recipeID).fetch(db)
    }) else {
      throw RecipeAdjustmentError.missingRecipe(review.recipeID)
    }

    let availableProviders = FrontierProvider.allCases.filter { apiKeyStore.key($0) != nil }
    let tier: ModelTier
    if let preferredProvider = providerPreference.current(), availableProviders.contains(preferredProvider) {
      tier = .frontier(preferredProvider)
    } else if let provider = availableProviders.first {
      tier = .frontier(provider)
    } else {
      tier = .onDevice
    }

    let proposal = try await recipeAdjustmentClient(
      selection: "",
      messages: [RecipeChatMessage(role: .user, text: trimmedBrief)],
      detail: detail,
      tier: tier,
      tierResolution: .preferredProviderOrFirstAvailable
    )
    let adjustmentReview = RecipeAdjustmentReviewState(
      currentDetail: detail,
      proposedDetail: try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { uuid() }),
      proposal: proposal,
      deliberationBody: brief
    )
    return adjustmentReview
  }

  func presentAdjustmentReview(_ adjustmentReview: RecipeAdjustmentReviewState) {
    self.adjustmentReview = adjustmentReview
  }

  func overwriteAdjustmentButtonTapped(_ review: RecipeAdjustmentReviewState) -> Bool {
    do {
      try database.write { db in
        _ = try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          review.proposal,
          recipeID: review.currentDetail.recipe.id,
          deliberationBody: review.deliberationBody,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      adjustmentReview = nil
      return true
    } catch {
      errorTitle = "Could Not Overwrite Recipe"
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
          recipeID: review.currentDetail.recipe.id,
          name: name,
          deliberationBody: review.deliberationBody,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      adjustmentReview = nil
      return true
    } catch {
      errorTitle = "Could Not Keep Variation"
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func commitRecipeAdjustmentLearnings(
    _ review: AIHandoffRecipeAdjustmentBriefReview,
    approvedText: String
  ) throws {
    guard !approvedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    try commitLearnings(sourceType: .recipe, sourceID: review.recipeID, approvedText: approvedText)
  }

  func discard(_ review: AIHandoffReview) {
    guard self.review?.handoffID == review.handoffID else { return }
    self.review = nil
  }

  func discardAll() {
    review = nil
  }
}

struct HandoffReviewSheet: View {
  let coordinator: HandoffReviewCoordinator
  let review: AIHandoffReview
  @State private var items: [ChatApplyReviewItem]

  init(coordinator: HandoffReviewCoordinator, review: AIHandoffReview) {
    self.coordinator = coordinator
    self.review = review
    _items = State(initialValue: coordinator.reviewItems(for: review))
  }

  var body: some View {
    switch review {
    case let .workbenchExperiments(experimentsReview):
      WorkbenchExperimentsReviewSheet(
        coordinator: coordinator,
        review: experimentsReview,
        originalReview: review
      )
    case let .recipeAdjustmentBrief(briefReview):
      RecipeAdjustmentBriefReviewSheet(
        coordinator: coordinator,
        review: briefReview,
        originalReview: review
      )
    case .menuPrepPlan, .recipeMakeAhead, .recipeChefItUp, .recipeServeWith, .mealPlanMakeAhead,
         .workbenchCompare:
      standardReviewSheet
    }
  }

  private var standardReviewSheet: some View {
    @Bindable var coordinator = coordinator

    return RecipeCollectionReviewSheet(
      items: items,
      committingItemID: nil,
      commit: { item, approvedText, usingSecondaryCommit in
        do {
          try await item.commit(approvedText, usingSecondaryCommit: usingSecondaryCommit)
          items.removeAll { $0.id == item.id }
          return true
        } catch {
          coordinator.errorTitle = "Could Not \(item.commitTitle)"
          coordinator.errorMessage = String(describing: error)
          coordinator.isShowingError = true
          return false
        }
      },
      discard: { item in
        items.removeAll { $0.id == item.id }
      },
      discardAll: {
        items = []
      },
      onEmpty: {
        coordinator.discard(review)
      }
    )
    .alert(coordinator.errorTitle, isPresented: $coordinator.isShowingError) {
      Button("OK") {}
    } message: {
      Text(coordinator.errorMessage ?? "")
    }
  }
}

private struct RecipeAdjustmentBriefReviewSheet: View {
  let coordinator: HandoffReviewCoordinator
  let review: AIHandoffRecipeAdjustmentBriefReview
  let originalReview: AIHandoffReview

  @Environment(\.dismiss) private var dismiss
  @State private var brief: String
  @State private var learnings: String
  @State private var isDrafting = false

  init(
    coordinator: HandoffReviewCoordinator,
    review: AIHandoffRecipeAdjustmentBriefReview,
    originalReview: AIHandoffReview
  ) {
    self.coordinator = coordinator
    self.review = review
    self.originalReview = originalReview
    _brief = State(initialValue: review.brief)
    _learnings = State(initialValue: review.learnings.map { "- \($0)" }.joined(separator: "\n"))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("This brief is based on the base recipe. It does not revise an active variation.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Section("Revision Brief") {
          TextEditor(text: $brief)
            .textInputAutocapitalization(.sentences)
            .frame(minHeight: 180)
        }

        Section("Learnings") {
          TextEditor(text: $learnings)
            .textInputAutocapitalization(.sentences)
            .frame(minHeight: 120)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Review Revision Brief")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Discard", role: .destructive) {
            coordinator.discard(originalReview)
            dismiss()
          }
          .disabled(isDrafting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Draft the Revision") {
            Task { await draftRevision() }
          }
          .disabled(isDrafting || brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  @MainActor
  private func draftRevision() async {
    isDrafting = true
    defer { isDrafting = false }
    do {
      let adjustmentReview = try await coordinator.draftRecipeAdjustment(review, brief: brief)
      try coordinator.commitRecipeAdjustmentLearnings(review, approvedText: learnings)
      coordinator.discard(originalReview)
      dismiss()
      await Task.yield()
      coordinator.presentAdjustmentReview(adjustmentReview)
    } catch {
      coordinator.errorTitle = "Could Not Draft Revision"
      coordinator.errorMessage = error.localizedDescription
      coordinator.isShowingError = true
    }
  }
}

private struct WorkbenchExperimentsReviewSheet: View {
  let coordinator: HandoffReviewCoordinator
  let review: AIHandoffWorkbenchExperimentsReview
  let originalReview: AIHandoffReview

  @Environment(\.dismiss) private var dismiss
  @State private var experiments: [WorkbenchExperiment]
  @State private var savingExperimentID: WorkbenchExperiment.ID?
  @State private var isShowingDiscardAllConfirmation = false

  init(
    coordinator: HandoffReviewCoordinator,
    review: AIHandoffWorkbenchExperimentsReview,
    originalReview: AIHandoffReview
  ) {
    self.coordinator = coordinator
    self.review = review
    self.originalReview = originalReview
    _experiments = State(initialValue: review.experiments)
  }

  var body: some View {
    @Bindable var coordinator = coordinator

    NavigationStack {
      Form {
        Section {
          Text("Review each experiment before saving it to the workbench log. The fields stay separate so an outcome can be added after it is tried.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        ForEach($experiments) { $experiment in
          Section("Experiment") {
            TextField("Hypothesis", text: $experiment.hypothesis, axis: .vertical)
            TextField("Change", text: $experiment.change, axis: .vertical)
            TextField("Rationale", text: $experiment.rationale, axis: .vertical)

            Button {
              saveButtonTapped(experiment)
            } label: {
              if savingExperimentID == experiment.id {
                ProgressView()
              } else {
                Text("Save Experiment")
              }
            }
            .disabled(savingExperimentID != nil || !experimentIsComplete(experiment))

            Button("Discard", role: .destructive) {
              experiments.removeAll { $0.id == experiment.id }
            }
            .disabled(savingExperimentID != nil)
          }
        }
      }
      .navigationTitle("Review Experiments")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Discard All", role: .destructive) {
            isShowingDiscardAllConfirmation = true
          }
          .disabled(experiments.isEmpty || savingExperimentID != nil)
        }
      }
    }
    .alert(coordinator.errorTitle, isPresented: $coordinator.isShowingError) {
      Button("OK") {}
    } message: {
      Text(coordinator.errorMessage ?? "")
    }
    .confirmationDialog(
      "Discard all experiments?",
      isPresented: $isShowingDiscardAllConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard All", role: .destructive) {
        experiments = []
      }
      Button("Keep Reviewing", role: .cancel) {}
    }
    .onChange(of: experiments.isEmpty) { _, isEmpty in
      if isEmpty {
        coordinator.discard(originalReview)
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func experimentIsComplete(_ experiment: WorkbenchExperiment) -> Bool {
    !experiment.hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !experiment.change.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !experiment.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func saveButtonTapped(_ experiment: WorkbenchExperiment) {
    savingExperimentID = experiment.id
    defer { savingExperimentID = nil }
    do {
      try coordinator.commitWorkbenchExperiment(experiment, to: review.workbenchID)
      experiments.removeAll { $0.id == experiment.id }
    } catch {
      coordinator.errorTitle = "Could Not Save Experiment"
      coordinator.errorMessage = String(describing: error)
      coordinator.isShowingError = true
    }
  }
}

private enum HandoffReviewError: LocalizedError, CustomStringConvertible {
  case emptyLearnings
  case emptyDeliverable
  case unparsedStrategyText([String])

  var errorDescription: String? {
    switch self {
    case .emptyLearnings:
      "Add at least one bulleted learning before saving."
    case .emptyDeliverable:
      "Add at least one make-ahead item before saving."
    case let .unparsedStrategyText(lines):
      "Could not save these make-ahead strategy lines: \(lines.joined(separator: " | "))"
    }
  }

  var description: String { errorDescription ?? "The Learnings could not be saved." }
}

extension HandoffReviewCoordinator: DependencyKey {
  nonisolated static var liveValue: HandoffReviewCoordinator {
    MainActor.assumeIsolated { HandoffReviewCoordinator() }
  }
}

extension DependencyValues {
  var handoffReviewCoordinator: HandoffReviewCoordinator {
    get { self[HandoffReviewCoordinator.self] }
    set { self[HandoffReviewCoordinator.self] = newValue }
  }
}
