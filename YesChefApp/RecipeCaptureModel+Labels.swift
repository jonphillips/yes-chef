import Foundation
import YesChefCore

extension RecipeCaptureModel {
  func suggestedLabelTapped(_ suggestion: SuggestedLabel) {
    guard var draft else { return }
    if acceptedSuggestedLabelIDs.contains(suggestion.id) {
      acceptedSuggestedLabelIDs.remove(suggestion.id)
      draft.page.categoryNames.removeAll {
        $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
      }
    } else {
      acceptedSuggestedLabelIDs.insert(suggestion.id)
      if !draft.page.categoryNames.contains(where: {
        $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
      }) {
        draft.page.categoryNames.append(suggestion.categoryName)
      }
    }
    self.draft = draft
  }

  func isSuggestedLabelAccepted(_ suggestion: SuggestedLabel) -> Bool {
    acceptedSuggestedLabelIDs.contains(suggestion.id)
  }

  func suggestLabelsAfterCapture(for draft: WebRecipeCaptureDraft) {
    suggestedLabels = []
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
          try CategoryRepository.effectiveCategorySet(in: db).categories
        }
        let suggestions = try await labelProposer(
          recipe: proposedForPage.labelProposalRecipe,
          existingTree: categories
        )
        guard self.labelSuggestionGeneration == generation else { return }
        // Publisher-harvested labels are already part of this draft. They are not a model proposal to
        // approve or remove, even when the model correctly recognizes the same category.
        suggestedLabels = suggestions.filter { suggestion in
          !proposedForPage.categoryNames.contains {
            $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
          }
            && !proposedForPage.tagNames.contains {
              $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
            }
        }
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
