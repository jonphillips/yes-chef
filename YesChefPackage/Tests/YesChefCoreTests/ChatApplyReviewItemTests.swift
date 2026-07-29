import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct ChatApplyReviewItemTests {
    @Test
    func unmodifiedApprovedTextMatchesEachPresentation() {
      let sheetItem = ChatApplyReviewItem(
        title: "Review",
        summary: "Rendered summary",
        editableText: "Editable source",
        commitTitle: "Save",
        committingTitle: "Saving",
        committedTitle: "Saved",
        commit: {}
      )
      let inlineItem = ChatApplyReviewItem(
        title: "Review",
        summary: "Rendered summary",
        presentation: .inline,
        editableText: "Editable source",
        commitTitle: "Save",
        committingTitle: "Saving",
        committedTitle: "Saved",
        commit: {}
      )

      expectNoDifference(sheetItem.unmodifiedApprovedText, "Editable source")
      expectNoDifference(inlineItem.unmodifiedApprovedText, "Rendered summary")
    }

    /// Accept All commits in bulk with `usingSecondaryCommit: false`, so an unedited approval must
    /// reach the primary destination carrying the presentation's own unmodified text — never the
    /// alternate destination, which is a deliberate per-item choice (ADR-0023) and must not be
    /// selectable in bulk.
    ///
    /// This does *not* assert that the individual and bulk paths agree; both of those live in the
    /// app layer, and what keeps them in step is that each reads `unmodifiedApprovedText`, pinned
    /// by `unmodifiedApprovedTextMatchesEachPresentation` above.
    @Test
    @MainActor
    func uneditedPrimaryCommitSendsUnmodifiedTextAndSkipsSecondaryDestination() async throws {
      let expectedTextByPresentation: [(ChatApplyReviewPresentation, String)] = [
        (.sheet, "Editable source"),
        (.inline, "Rendered summary"),
      ]

      for (presentation, expectedText) in expectedTextByPresentation {
        var primaryCommitTexts: [String] = []
        var secondaryCommitTexts: [String] = []
        let item = ChatApplyReviewItem(
          title: "Review",
          summary: "Rendered summary",
          presentation: presentation,
          editableText: "Editable source",
          commitTitle: "Save",
          committingTitle: "Saving",
          committedTitle: "Saved",
          secondaryCommit: ChatApplyReviewSecondaryCommit(title: "Alternate") { text in
            secondaryCommitTexts.append(text)
          },
          commit: { text in
            primaryCommitTexts.append(text)
          }
        )

        try await item.commit(item.unmodifiedApprovedText, usingSecondaryCommit: false)

        expectNoDifference(primaryCommitTexts, [expectedText])
        expectNoDifference(secondaryCommitTexts, [])
      }
    }

    @Test
    @MainActor
    func editableReviewItemCommitsApprovedText() async throws {
      var committedText: String?
      let action = ChatApplyAction<MakeAheadPlan>(
        title: "Create Make-ahead",
        extractingTitle: "Summarizing make-ahead...",
        reviewTitle: "Review make-ahead",
        commitTitle: "Commit to Make-ahead",
        committingTitle: "Saving make-ahead...",
        committedTitle: "Saved to Make-ahead",
        extract: { _, _ in
          MakeAheadPlan(
            steps: [
              MakeAheadStep(when: "Day before", task: "Make the sauce.")
            ]
          )
        },
        commit: { _ in }
      )
      let erased = AnyChatApplyAction(action, editableSummary: { plan in
        plan.rendered()
      }, commitEditedSummary: { _, editedSummary in
        committedText = editedSummary
      })

      let items = try await erased.run("", [])

      expectNoDifference(items.map(\.editableText), ["Day before: Make the sauce."])
      try await items[0].commit("Day before: Make the sauce and grate the cheese.")
      expectNoDifference(committedText, "Day before: Make the sauce and grate the cheese.")
    }
  }
}
