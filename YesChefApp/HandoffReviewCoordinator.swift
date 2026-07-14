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

  var review: AIHandoffMenuPrepPlanReview?
  var errorMessage: String?
  var isShowingError = false

  func present(_ review: AIHandoffMenuPrepPlanReview) {
    self.review = review
  }

  func reviewItems(for review: AIHandoffMenuPrepPlanReview) -> [ChatApplyReviewItem] {
    var items: [ChatApplyReviewItem] = []
    if !review.plan.steps.isEmpty {
      items.append(
        ChatApplyReviewItem(
          id: review.handoffID,
          title: "Review prep plan",
          summary: review.plan.editableReviewText(),
          presentation: .sheet,
          editableTitle: "Prep plan",
          editableText: review.plan.editableReviewText(),
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

  func commitPrepPlan(_ review: AIHandoffMenuPrepPlanReview, approvedText: String) throws {
    let plan = review.plan.applyingEditableReviewText(approvedText)
    guard !plan.steps.isEmpty else { throw AIHandoffMenuPrepPlanImportError.emptyPlan }
    try database.write { db in
      try MenuRepository.applyPrepPlan(plan, to: review.menuID, in: db, now: now)
    }
  }

  func commitLearnings(_ review: AIHandoffMenuPrepPlanReview, approvedText: String) throws {
    let learnings = AIHandoffReturn.learningBullets(from: approvedText)
    guard !learnings.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }
    try database.write { db in
      for text in learnings {
        try LearningRepository.create(
          Learning(
            id: uuid(),
            sourceType: .menu,
            sourceID: review.menuID,
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

  func discard(_ review: AIHandoffMenuPrepPlanReview) {
    guard self.review?.handoffID == review.handoffID else { return }
    self.review = nil
  }

  func discardAll() {
    review = nil
  }
}

struct HandoffReviewSheet: View {
  let coordinator: HandoffReviewCoordinator
  let review: AIHandoffMenuPrepPlanReview
  @State private var items: [ChatApplyReviewItem]

  init(coordinator: HandoffReviewCoordinator, review: AIHandoffMenuPrepPlanReview) {
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
    .alert("Could Not Save Prep Plan", isPresented: $coordinator.isShowingError) {
      Button("OK") {}
    } message: {
      Text(coordinator.errorMessage ?? "")
    }
  }
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
