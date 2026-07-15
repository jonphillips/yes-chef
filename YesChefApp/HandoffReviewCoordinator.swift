import Dependencies
import Foundation
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
    case let .mealPlanMakeAhead(review):
      mealPlanMakeAheadReviewItems(for: review)
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
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review make-ahead",
          summary: review.makeAhead,
          presentation: .sheet,
          editableTitle: "Make-ahead",
          editableText: review.makeAhead,
          commitTitle: "Save Make-ahead",
          committingTitle: "Saving Make-ahead…",
          committedTitle: "Saved Make-ahead",
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

  private func commitMealPlanMakeAhead(
    _ review: AIHandoffMealPlanMakeAheadReview,
    approvedText: String
  ) throws {
    let parsed = MealPlanMakeAheadStrategy.parsingEditableReviewText(approvedText)
    guard parsed.unparsedLines.isEmpty else {
      throw HandoffReviewError.unparsedStrategyText(parsed.unparsedLines)
    }
    guard !parsed.strategy.steps.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    try database.write { db in
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
    try database.write { db in
      for text in learnings {
        try LearningRepository.create(
          Learning(
            id: uuid(),
            sourceType: sourceType,
            sourceID: sourceID,
            text: text,
            provenance: .externalHandoff,
            dateCreated: now,
            dateModified: now
          ),
          in: db
        )
      }
    }
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
    @Bindable var coordinator = coordinator

    RecipeCollectionReviewSheet(
      items: items,
      committingItemID: nil,
      commit: { item, approvedText in
        do {
          try await item.commit(approvedText)
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
