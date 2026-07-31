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
  func confirmingANamespaceSurvivesTheDialogDismissalAndFilesTheRecipeUnderTheChild() {
    let model = draftedModel(page: ParsedRecipePage(title: "Summer Corn"))
    let suggestion = SuggestedLabel(kind: .namespace, path: ["Season", "Summer"])
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
    // Finding 3: accepting a namespace files the recipe under `Dimension > Value`, not a bare root.
    expectNoDifference(model.acceptedSuggestionCategoryNames, ["Season > Summer"])
  }

  // Re-extract stickiness: accepting is pure selection until commit, so the harvested page is never
  // mutated and a re-extraction can't turn an accepted chip into a sticky harvested-looking label.
  @Test
  func acceptingASuggestionStaysPureSelectionAndOnlyMergesAtCommit() {
    let model = draftedModel(page: ParsedRecipePage(title: "Soup", categoryNames: ["Cuisine > Thai"]))
    let loose = SuggestedLabel(kind: .loose, path: ["weeknight"])
    model.suggestedLabels = [loose]

    model.suggestedLabelTapped(loose)
    #expect(model.isSuggestedLabelAccepted(loose))
    // The harvested label is untouched and the accepted suggestion has not leaked into the page.
    expectNoDifference(model.draft?.page.categoryNames, ["Cuisine > Thai"])
    expectNoDifference(model.acceptedSuggestionCategoryNames, ["weeknight"])

    var page = model.draft!.page
    model.mergingAcceptedSuggestions(into: &page)
    expectNoDifference(page.categoryNames, ["Cuisine > Thai", "weeknight"])

    // Un-accepting drops it back out entirely.
    model.suggestedLabelTapped(loose)
    #expect(model.acceptedSuggestionCategoryNames.isEmpty)
  }
}
