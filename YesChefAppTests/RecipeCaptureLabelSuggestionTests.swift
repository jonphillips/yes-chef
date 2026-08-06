import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct RecipeCaptureLabelSuggestionTests {
  /// `RecipeCaptureModel.init` mints its reader-feedback capture ID eagerly, so *constructing* one
  /// resolves `uuid` — these label tests never touch a UUID themselves but still need the scope.
  private func withCaptureDependencies(_ operation: () throws -> Void) rethrows {
    try withDependencies {
      $0.uuid = .incrementing
    } operation: {
      try operation()
    }
  }

  private func draftedModel(page: ParsedRecipePage) -> RecipeCaptureModel {
    let model = RecipeCaptureModel()
    model.draft = WebRecipeCaptureDraft(page: page)
    return model
  }

  // Finding 1: the confirm action must apply the suggestion even though SwiftUI writes the `item:`
  // binding to nil *before* the action runs. A model test is where this lives — Core tests never drive
  // the binding, which is exactly why the same ADR-0030 defect survived three reviews.
  @Test
  func confirmingANamespaceSurvivesTheDialogDismissalAndKeepsTheFacetProposalTyped() {
    withCaptureDependencies {
      let model = draftedModel(page: ParsedRecipePage(title: "Summer Corn"))
      let suggestion = SuggestedLabel.namespace(.init(facetName: "Season", firstValueName: "Summer"))
      model.suggestedLabels = [suggestion]

      model.namespaceSuggestionTapped(suggestion)
      guard case .confirmNamespace? = model.destination else {
        Issue.record("Tapping the namespace suggestion should stage the confirmation.")
        return
      }

      // Reproduce the dismissal ordering: the destination is already gone by the time confirm fires.
      model.destination = nil
      model.confirmNamespaceSuggestion(suggestion)

      #expect(model.isSuggestedLabelAccepted(suggestion))
      #expect(model.destination == nil)
      // Finding 3 re-pointed: accepting creates a Facet plus its first value at commit, rather than
      // encoding a parent-child path string for the old tree model.
      expectNoDifference(model.acceptedLabelSuggestions, [suggestion])
    }
  }

  // Re-extract stickiness: accepting is pure selection until commit, so the harvested page is never
  // mutated and a re-extraction can't turn an accepted chip into a sticky harvested-looking label.
  @Test
  func acceptingASuggestionStaysPureSelectionAndOnlyMergesAtCommit() {
    withCaptureDependencies {
      let model = draftedModel(page: ParsedRecipePage(title: "Soup", categoryNames: ["Cuisine > Thai"]))
      let loose = SuggestedLabel.loose("weeknight")
      model.suggestedLabels = [loose]

      model.suggestedLabelTapped(loose)
      #expect(model.isSuggestedLabelAccepted(loose))
      // The harvested label is untouched and the accepted suggestion has not leaked into the page.
      expectNoDifference(model.draft?.page.categoryNames, ["Cuisine > Thai"])
      expectNoDifference(model.acceptedLabelSuggestions, [loose])

      // The import page stays untouched; typed suggestions are supplied to the repository separately
      // at commit, where it remains the sole writer of category, facet, and join rows.
      expectNoDifference(model.draft?.page.categoryNames, ["Cuisine > Thai"])

      // Un-accepting drops it back out entirely.
      model.suggestedLabelTapped(loose)
      #expect(model.acceptedLabelSuggestions.isEmpty)
    }
  }

  // Thread C1: the harvested (verbatim publisher) categories & tags are editable before commit.
  // Renames land on the live draft page and reach the importer through `curatedDraftForCommit()`.
  @Test
  func editsToHarvestedCategoriesAndTagsReachCommit() {
    withCaptureDependencies {
      let model = draftedModel(
        page: ParsedRecipePage(
          title: "Spanish Style Garlic Shrimp",
          tagNames: ["weeknight", "seafood"],
          categoryNames: ["Dinner", "Tapas"]
        )
      )

      model.updateReviewCategoryName("Small Plates", at: 1)
      model.removeReviewTags(atOffsets: IndexSet(integer: 0))

      let commit = model.curatedDraftForCommit()
      expectNoDifference(commit?.draft.page.categoryNames, ["Dinner", "Small Plates"])
      expectNoDifference(commit?.draft.page.tagNames, ["seafood"])
    }
  }

  // Commit re-normalizes hand-edited labels: trim, drop rows emptied by a rename, and collapse
  // case-insensitive duplicates (first-seen order and casing win) — the builder's parse-time pass
  // does not run over edits, so `curatedDraftForCommit()` has to.
  @Test
  func commitNormalizesRenamedHarvestedLabels() {
    withCaptureDependencies {
      let model = draftedModel(
        page: ParsedRecipePage(
          title: "Pork Bites",
          tagNames: ["quick"],
          categoryNames: ["Dinner", "Mains", "Tapas"]
        )
      )

      // Rename to a case-variant duplicate, empty one out, and pad another with whitespace.
      model.updateReviewCategoryName("dinner", at: 1)
      model.updateReviewCategoryName("   ", at: 2)
      model.updateReviewTagName("  Quick  ", at: 0)

      let commit = model.curatedDraftForCommit()
      expectNoDifference(commit?.draft.page.categoryNames, ["Dinner"])
      expectNoDifference(commit?.draft.page.tagNames, ["Quick"])
    }
  }

  @Test
  func doesNotSurfaceSuggestionsAlreadyHarvestedAsCategoriesOrTags() {
    withCaptureDependencies {
      let model = draftedModel(page: ParsedRecipePage(title: "Pasta"))

      let visible = model.filteringHarvestedLabels(
        from: [.loose("Italian"), .loose("weeknight"), .loose("party")],
        in: ParsedRecipePage(title: "Pasta", tagNames: ["Weeknight"], categoryNames: ["italian"])
      )

      expectNoDifference(visible, [.loose("party")])
    }
  }
}
