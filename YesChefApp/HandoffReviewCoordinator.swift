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

  var review: AIHandoffMenuPrepPlanReview?
  var errorMessage: String?
  var isShowingError = false

  func present(_ review: AIHandoffMenuPrepPlanReview) {
    self.review = review
  }

  func reviewItem(for review: AIHandoffMenuPrepPlanReview) -> ChatApplyReviewItem {
    ChatApplyReviewItem(
      title: "Review prep plan",
      summary: review.plan.editableReviewText(),
      presentation: .sheet,
      editableTitle: "Prep plan",
      editableText: review.plan.editableReviewText(),
      commitTitle: "Save Prep Plan",
      committingTitle: "Saving Prep Plan…",
      committedTitle: "Saved Prep Plan",
      commit: { [weak self] approvedText in
        try self?.commit(review, approvedText: approvedText)
      }
    )
  }

  func commit(_ review: AIHandoffMenuPrepPlanReview, approvedText: String) throws {
    let plan = review.plan.applyingEditableReviewText(approvedText)
    guard !plan.steps.isEmpty else { throw AIHandoffMenuPrepPlanImportError.emptyPlan }
    try database.write { db in
      try MenuRepository.applyPrepPlan(plan, to: review.menuID, in: db, now: now)
    }
    self.review = nil
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

  var body: some View {
    @Bindable var coordinator = coordinator

    RecipeCollectionReviewSheet(
      items: [coordinator.reviewItem(for: review)],
      committingItemID: nil,
      commit: { _, approvedText in
        do {
          try coordinator.commit(review, approvedText: approvedText)
          return true
        } catch {
          coordinator.errorMessage = String(describing: error)
          coordinator.isShowingError = true
          return false
        }
      },
      discard: { _ in
        coordinator.discard(review)
      },
      discardAll: coordinator.discardAll,
      onEmpty: coordinator.discardAll
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
