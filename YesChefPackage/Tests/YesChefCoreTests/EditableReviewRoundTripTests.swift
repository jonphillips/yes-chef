import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct EditableReviewRoundTripTests {
    @Test
    func serveWithPlanRoundTripsEditableReviewText() {
      let plan = ServeWithPlan(
        items: [
          ServeWithSuggestion(title: "Cilantro-scallion rice", note: "Stir in butter right before serving."),
          ServeWithSuggestion(title: "Cucumber salad"),
        ]
      )

      let edited = plan.applyingEditableReviewText(
        """
        - Cilantro rice: Finish with lime.
        2. Charred cucumber salad
        """
      )

      expectNoDifference(
        edited,
        ServeWithPlan(
          items: [
            ServeWithSuggestion(title: "Cilantro rice", note: "Finish with lime."),
            ServeWithSuggestion(title: "Charred cucumber salad"),
          ]
        )
      )
    }

    @Test
    func serveWithParserIsAmbiguousForColonTitles() {
      let plan = ServeWithPlan(
        items: [
          ServeWithSuggestion(title: "2:1 rice")
        ]
      )

      let reparsed = plan.applyingEditableReviewText(plan.editableReviewText())

      #expect(reparsed != plan)
      expectNoDifference(
        reparsed,
        ServeWithPlan(
          items: [
            ServeWithSuggestion(title: "2", note: "1 rice")
          ]
        )
      )
    }

    @Test
    @MainActor
    func unchangedEditableSummaryCommitsOriginalPayloadWithoutReparsing() async throws {
      let plan = ServeWithPlan(
        items: [
          ServeWithSuggestion(title: "2:1 rice")
        ]
      )
      var committedPlan: ServeWithPlan?
      var reparsedPlan: ServeWithPlan?
      let action = ChatApplyAction<ServeWithPlan>(
        title: "Suggest Dishes",
        extractingTitle: "Finding accompaniments...",
        reviewTitle: "Review Serve With",
        commitTitle: "Add to Serve With",
        committingTitle: "Saving Serve With...",
        committedTitle: "Saved to Serve With",
        extract: { _, _ in plan },
        commit: { payload in
          committedPlan = payload
        }
      )
      let erased = AnyChatApplyAction(action, editableSummary: { payload in
        payload.editableReviewText()
      }, commitEditedSummary: { payload, editedText in
        reparsedPlan = payload.applyingEditableReviewText(editedText)
      })

      let item = try #require(try await erased.run("", []).first)
      try await item.commit(item.editableText ?? item.summary)

      expectNoDifference(committedPlan, plan)
      expectNoDifference(reparsedPlan, nil)
    }

    @Test
    func workbenchDraftRecipeRoundTripsEditableProseFieldsOnly() {
      let draft = WorkbenchDraftRecipe(
        title: "Weeknight Birria",
        summary: "Chile-forward and practical.",
        servingsText: "6 servings",
        ingredientSectionName: "Birria",
        ingredientLines: ["3 lb chuck roast"],
        instructionLines: ["Braise beef until tender."],
        notes: ["Variation: hotter salsa on the side."],
        rationale: "Borrows Candidate A's chile paste."
      )

      let edited = draft.applyingEditableProseReviewText(
        """
        Rationale: Borrows Candidate A's chile paste and Candidate B's oven braise.
        Title: Weeknight Beef Birria
        Subtitle: Chile-braised tacos
        Summary: Deep chile flavor without a weekend project.
        Servings: 8 servings
        Yield: 16 tacos
        Cuisine: Mexican-inspired
        Course: Dinner
        Ingredient section: Birria filling
        Notes:
        - Keep a hotter salsa on the side.
        - Save broth for dipping.
        """
      )

      expectNoDifference(edited.title, "Weeknight Beef Birria")
      expectNoDifference(edited.subtitle, "Chile-braised tacos")
      expectNoDifference(edited.summary, "Deep chile flavor without a weekend project.")
      expectNoDifference(edited.servingsText, "8 servings")
      expectNoDifference(edited.yieldText, "16 tacos")
      expectNoDifference(edited.cuisine, "Mexican-inspired")
      expectNoDifference(edited.course, "Dinner")
      expectNoDifference(edited.ingredientSectionName, "Birria filling")
      expectNoDifference(
        edited.notes,
        [
          "Keep a hotter salsa on the side.",
          "Save broth for dipping.",
        ]
      )
      expectNoDifference(edited.ingredientLines, draft.ingredientLines)
      expectNoDifference(edited.instructionLines, draft.instructionLines)
    }

    @Test
    func workbenchDraftRecipeEditableProseTextDoesNotInventEmptyNotePlaceholder() {
      let draft = WorkbenchDraftRecipe(
        title: "Weeknight Birria",
        ingredientLines: ["3 lb chuck roast"],
        instructionLines: ["Braise beef until tender."],
        rationale: "Borrows Candidate A's chile paste."
      )

      let edited = draft.applyingEditableProseReviewText(draft.editableProseReviewText())

      expectNoDifference(edited.notes, [])
    }
  }
}
