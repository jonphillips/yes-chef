import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct ChatApplyReviewItemTests {
    @Test
    @MainActor
    func editableReviewItemCommitsApprovedText() async throws {
      var committedText: String?
      let action = ChatApplyAction<MakeAheadPlan>(
        title: "Create Prep Plan",
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
