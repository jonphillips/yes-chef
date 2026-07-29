import SwiftUI
import YesChefCore

@MainActor
struct RecipeCollectionReviewSheet: View {
  let items: [ChatApplyReviewItem]
  let committingItemID: ChatApplyReviewItem.ID?
  let commit: @MainActor (ChatApplyReviewItem, String, Bool) async -> Bool
  let discard: @MainActor (ChatApplyReviewItem) -> Void
  let discardAll: @MainActor () -> Void
  let onEmpty: @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var presentedReviewItem: ChatApplyReviewItem?
  @State private var localCommittingItemID: ChatApplyReviewItem.ID?
  @State private var isShowingDiscardAllConfirmation = false
  @State private var committedSummary: CollectionReviewCommitSummary?
  @State private var isAcceptingAll = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let committedSummary {
            CollectionReviewCommitConfirmation(summary: committedSummary)
          }

          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(items.count == 1 ? "Review the assistant's proposal before saving it." : "Review each assistant proposal before saving it.")
              .font(.subheadline)
              .foregroundStyle(.secondary)

            Button("Discard All", role: .destructive) {
              isShowingDiscardAllConfirmation = true
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .disabled(items.isEmpty || activeCommittingItemID != nil || isAcceptingAll)
          }

          ForEach(items) { item in
            switch item.presentation {
            case .inline:
              CollectionReviewLaunchRow(
                item: item,
                isCommitting: activeCommittingItemID == item.id,
                isBulkCommitting: isAcceptingAll,
                review: { launchReview(for: item) },
                discard: { discard(item) }
              )
            case .sheet:
              ChatApplyReviewRow(
                item: item,
                isCommitting: activeCommittingItemID == item.id,
                isBulkCommitting: isAcceptingAll,
                review: { presentedReviewItem = item },
                discard: { discard(item) }
              )
            }
          }
        }
        .padding()
      }
      .navigationTitle("Review Proposals")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Accept All") {
            Task {
              await acceptAll()
            }
          }
          .disabled(items.isEmpty || activeCommittingItemID != nil || isAcceptingAll)
        }
      }
    }
    .sheet(item: $presentedReviewItem) { item in
      ChatApplyReviewSheet(
        item: item,
        isCommitting: activeCommittingItemID == item.id,
        commit: { approvedText, usingSecondaryCommit in
          let didCommit = await commitItem(
            item,
            approvedText: approvedText,
            usingSecondaryCommit: usingSecondaryCommit
          )
          if didCommit {
            committedSummary = CollectionReviewCommitSummary(
              item: item,
              approvedText: approvedText
            )
            presentedReviewItem = nil
          }
        },
        discard: {
          discard(item)
          presentedReviewItem = nil
        }
      )
    }
    .confirmationDialog(
      "Discard all proposals?",
      isPresented: $isShowingDiscardAllConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard All", role: .destructive) {
        discardAll()
      }
      Button("Keep Reviewing", role: .cancel) {}
    } message: {
      Text("All proposals in this review will be removed.")
    }
    .presentationDetents([.medium, .large])
    .onAppear {
      reconcilePresentedItem()
    }
    .onChange(of: items.count) { _, _ in
      reconcilePresentedItem()
    }
    .onChange(of: items.isEmpty) { _, isEmpty in
      if isEmpty {
        onEmpty()
      }
    }
  }

  private func reconcilePresentedItem() {
    guard !items.isEmpty else {
      presentedReviewItem = nil
      onEmpty()
      return
    }

    if let presentedReviewItem,
       !items.contains(where: { $0.id == presentedReviewItem.id })
    {
      self.presentedReviewItem = nil
    }

    guard !isAcceptingAll,
          items.count == 1,
          let item = items.first,
          item.presentation == .sheet
    else { return }

    presentedReviewItem = item
  }

  private func launchReview(for item: ChatApplyReviewItem) {
    Task {
      let didCommit = await commitItem(
        item,
        approvedText: item.unmodifiedApprovedText,
        usingSecondaryCommit: false
      )
      if didCommit {
        committedSummary = CollectionReviewCommitSummary(
          item: item,
          approvedText: item.unmodifiedApprovedText
        )
      }
    }
  }

  private func acceptAll() async {
    isAcceptingAll = true
    defer { isAcceptingAll = false }

    // `items` is the snapshot captured when this Task was formed, and the failure count below
    // depends on that: committing drains the caller's live list, so only the snapshot still knows
    // how many proposals this pass set out to save.
    var committedCount = 0
    var didFail = false
    for item in items {
      let didCommit = await commitItem(
        item,
        approvedText: item.unmodifiedApprovedText,
        usingSecondaryCommit: false
      )
      guard didCommit else {
        didFail = true
        break
      }
      committedCount += 1
    }

    if committedCount > 0 || didFail {
      committedSummary = CollectionReviewCommitSummary(
        committedCount: committedCount,
        failedItemCount: didFail ? items.count - committedCount : 0
      )
    }
  }

  private var activeCommittingItemID: ChatApplyReviewItem.ID? {
    localCommittingItemID ?? committingItemID
  }

  private func commitItem(
    _ item: ChatApplyReviewItem,
    approvedText: String,
    usingSecondaryCommit: Bool
  ) async -> Bool {
    localCommittingItemID = item.id
    defer { localCommittingItemID = nil }
    return await commit(item, approvedText, usingSecondaryCommit)
  }
}

private struct CollectionReviewCommitSummary: Equatable {
  let committedCount: Int
  let failedItemCount: Int
  var title: String?
  var text: String?

  init(item: ChatApplyReviewItem, approvedText: String) {
    committedCount = 1
    failedItemCount = 0
    title = item.committedTitle
    text = approvedText
  }

  init(committedCount: Int, failedItemCount: Int = 0) {
    self.committedCount = committedCount
    self.failedItemCount = failedItemCount
    title = nil
    text = nil
  }
}

private struct CollectionReviewCommitConfirmation: View {
  let summary: CollectionReviewCommitSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(confirmationTitle, systemImage: confirmationImage)
        .font(.caption.bold())
        .foregroundStyle(confirmationTint)
      if let text = summary.text {
        Text(text)
          .font(.callout)
      } else if summary.failedItemCount > 0 {
        Text("Could not save the remaining \(summary.failedItemCount) \(proposalNoun); they are still available to review.")
          .font(.callout)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(confirmationTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }

  private var confirmationTitle: String {
    if summary.failedItemCount > 0, summary.committedCount == 0 {
      return "Could Not Save Proposals"
    }
    guard summary.committedCount != 1 else {
      return summary.title ?? "Saved proposal"
    }
    return "Saved \(summary.committedCount) proposals"
  }

  private var proposalNoun: String {
    summary.failedItemCount == 1 ? "proposal" : "proposals"
  }

  private var confirmationImage: String {
    summary.failedItemCount > 0 ? "exclamationmark.triangle" : "checkmark.circle"
  }

  private var confirmationTint: Color {
    summary.failedItemCount > 0 ? .orange : .green
  }
}

private struct CollectionReviewLaunchRow: View {
  let item: ChatApplyReviewItem
  let isCommitting: Bool
  /// Set while a bulk accept is walking the list, so rows this pass has not reached yet cannot be
  /// discarded or reviewed out from under it.
  var isBulkCommitting: Bool = false
  let review: () -> Void
  let discard: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(item.title, systemImage: "arrow.triangle.branch")
        .font(.caption.bold())
      Text(item.summary)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Button(role: .cancel, action: discard) {
          Label("Discard", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(isCommitting || isBulkCommitting)

        Spacer(minLength: 8)

        Button(action: review) {
          Label(
            isCommitting ? item.committingTitle : item.commitTitle,
            systemImage: isCommitting ? "hourglass" : "arrow.right"
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(isCommitting || isBulkCommitting)
      }
    }
    .attentionCard()
  }
}
