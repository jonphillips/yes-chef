import CustomDump
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct RecipeCaptureLabelSuggestionTests {
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

  // Re-extract stickiness: accepting is pure selection until commit, so the harvested page is never
  // mutated and a re-extraction can't turn an accepted chip into a sticky harvested-looking label.
  @Test
  func acceptingASuggestionStaysPureSelectionAndOnlyMergesAtCommit() {
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

  @Test
  func doesNotSurfaceSuggestionsAlreadyHarvestedAsCategoriesOrTags() {
    let model = draftedModel(page: ParsedRecipePage(title: "Pasta"))

    let visible = model.filteringHarvestedLabels(
      from: [.loose("Italian"), .loose("weeknight"), .loose("party")],
      in: ParsedRecipePage(title: "Pasta", categoryNames: ["italian"], tagNames: ["Weeknight"])
    )

    expectNoDifference(visible, [.loose("party")])
  }
}
