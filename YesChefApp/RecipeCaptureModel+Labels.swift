import Foundation
import YesChefCore

extension RecipeCaptureModel {
  func suggestedLabelTapped(_ suggestion: SuggestedLabel) {
    guard suggestion.kind != .namespace else {
      namespaceSuggestionTapped(suggestion)
      return
    }
    toggleSuggestedLabel(suggestion)
  }

  var chipSuggestions: [SuggestedLabel] {
    suggestedLabels.filter { $0.kind != .namespace }
  }

  var namespaceSuggestions: [SuggestedLabel] {
    suggestedLabels.filter { $0.kind == .namespace }
  }

  func namespaceSuggestionTapped(_ suggestion: SuggestedLabel) {
    if isSuggestedLabelAccepted(suggestion) {
      toggleSuggestedLabel(suggestion)
    } else {
      destination = .confirmNamespace(suggestion)
    }
  }

  /// Takes the suggestion as a parameter so it survives the confirmation dialog's dismissal. SwiftUI
  /// writes the `item:` binding to nil *before* this button action runs, so reading the payload back
  /// from `destination` here would find nothing — the exact ADR-0030 defect this branch reintroduced.
  /// See [[alert-ispresented-destructive-setter]].
  func confirmNamespaceSuggestion(_ suggestion: SuggestedLabel) {
    toggleSuggestedLabel(suggestion)
    destination = nil
  }

  private func toggleSuggestedLabel(_ suggestion: SuggestedLabel) {
    // Accepting is pure selection state until commit; the draft's `categoryNames` is not touched here.
    guard draft != nil else { return }
    if acceptedSuggestedLabelIDs.contains(suggestion.id) {
      acceptedSuggestedLabelIDs.remove(suggestion.id)
    } else {
      acceptedSuggestedLabelIDs.insert(suggestion.id)
    }
  }

  func isSuggestedLabelAccepted(_ suggestion: SuggestedLabel) -> Bool {
    acceptedSuggestedLabelIDs.contains(suggestion.id)
  }

  /// The category names accepted from suggestions. For a `.namespace` this is the full `Dimension > Value`
  /// path, so accepting files the recipe under the new child rather than a bare dimension root.
  var acceptedSuggestionCategoryNames: [String] {
    suggestedLabels
      .filter { acceptedSuggestedLabelIDs.contains($0.id) }
      .map(\.categoryName)
  }

  /// Merges accepted suggestions into a page at commit time, de-duplicating against harvested labels.
  func mergingAcceptedSuggestions(into page: inout ParsedRecipePage) {
    for name in acceptedSuggestionCategoryNames
    where !page.categoryNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
      page.categoryNames.append(name)
    }
  }

  func suggestLabelsAfterCapture(for draft: WebRecipeCaptureDraft) {
    suggestedLabels = []
    rejectedLabelSuggestions = []
    acceptedSuggestedLabelIDs = []
    labelProposalError = nil
    isSuggestingLabels = true
    let proposedForPage = draft.page
    labelSuggestionGeneration += 1
    let generation = labelSuggestionGeneration

    Task { [weak self] in
      guard let self else { return }
      do {
        let categories = try await database.read { db in
          try Category.fetchAll(db)
        }
        let proposal = try await labelProposer(
          recipe: proposedForPage.labelProposalRecipe,
          existingTree: categories
        )
        guard self.labelSuggestionGeneration == generation else { return }
        // Publisher-harvested labels are already part of this draft. They are not a model proposal to
        // approve or remove, even when the model correctly recognizes the same category.
        suggestedLabels = proposal.accepted.filter { suggestion in
          !proposedForPage.categoryNames.contains {
            $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
          }
            && !proposedForPage.tagNames.contains {
              $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
            }
        }
        rejectedLabelSuggestions = proposal.rejected
      } catch is CancellationError {
      } catch {
        guard self.labelSuggestionGeneration == generation else { return }
        labelProposalError = RecipeChatErrorText.describe(error)
      }
      if self.labelSuggestionGeneration == generation {
        isSuggestingLabels = false
      }
    }
  }
}
