import SwiftUI
import YesChefCore

@MainActor
struct RecipeCollectionReviewSheet: View {
  let items: [ChatApplyReviewItem]
  let committingItemID: ChatApplyReviewItem.ID?
  let commit: @MainActor (ChatApplyReviewItem, String) async -> Bool
  let discard: @MainActor (ChatApplyReviewItem) -> Void
  let discardAll: @MainActor () -> Void
  let onEmpty: @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var presentedReviewItem: ChatApplyReviewItem?
  @State private var localCommittingItemID: ChatApplyReviewItem.ID?
  @State private var isShowingDiscardAllConfirmation = false
  @State private var committedSummary: CollectionReviewCommitSummary?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let committedSummary {
            CollectionReviewCommitConfirmation(summary: committedSummary)
          }

          Text(items.count == 1 ? "Review the assistant's proposal before saving it." : "Review each assistant proposal before saving it.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          ForEach(items) { item in
            switch item.presentation {
            case .inline:
              CollectionReviewLaunchRow(
                item: item,
                isCommitting: activeCommittingItemID == item.id,
                review: { launchReview(for: item) },
                discard: { discard(item) }
              )
            case .sheet:
              ChatApplyReviewRow(
                item: item,
                isCommitting: activeCommittingItemID == item.id,
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
          Button("Discard All", role: .destructive) {
            isShowingDiscardAllConfirmation = true
          }
          .disabled(items.isEmpty || activeCommittingItemID != nil)
        }
      }
    }
    .sheet(item: $presentedReviewItem) { item in
      ChatApplyReviewSheet(
        item: item,
        isCommitting: activeCommittingItemID == item.id,
        commit: { approvedText in
          let didCommit = await commitItem(item, approvedText: approvedText)
          if didCommit {
            committedSummary = CollectionReviewCommitSummary(
              title: item.committedTitle,
              text: approvedText
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

    guard items.count == 1,
          let item = items.first,
          item.presentation == .sheet
    else { return }

    presentedReviewItem = item
  }

  private func launchReview(for item: ChatApplyReviewItem) {
    Task {
      let didCommit = await commitItem(item, approvedText: item.summary)
      if didCommit {
        committedSummary = CollectionReviewCommitSummary(
          title: item.committedTitle,
          text: item.summary
        )
      }
    }
  }

  private var activeCommittingItemID: ChatApplyReviewItem.ID? {
    localCommittingItemID ?? committingItemID
  }

  private func commitItem(_ item: ChatApplyReviewItem, approvedText: String) async -> Bool {
    localCommittingItemID = item.id
    defer { localCommittingItemID = nil }
    return await commit(item, approvedText)
  }
}

private struct CollectionReviewCommitSummary: Equatable {
  let title: String
  let text: String
}

private struct CollectionReviewCommitConfirmation: View {
  let summary: CollectionReviewCommitSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(summary.title, systemImage: "checkmark.circle")
        .font(.caption.bold())
        .foregroundStyle(.green)
      Text(summary.text)
        .font(.callout)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct CollectionReviewLaunchRow: View {
  let item: ChatApplyReviewItem
  let isCommitting: Bool
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
        .disabled(isCommitting)

        Spacer(minLength: 8)

        Button(action: review) {
          Label(
            isCommitting ? item.committingTitle : item.commitTitle,
            systemImage: isCommitting ? "hourglass" : "arrow.right"
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(isCommitting)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
  }
}
