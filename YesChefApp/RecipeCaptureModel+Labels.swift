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

  func curatedDraftForCommit() -> (draft: WebRecipeCaptureDraft, acceptedLabelSuggestions: [SuggestedLabel])? {
    guard var draft else { return nil }
    draft.page.editorialBlocks = draft.page.editorialBlocks
      .map { ParsedRecipeEditorialBlock(label: $0.label, text: $0.text) }
      .filter { !$0.text.isEmpty }
    draft.page.readerFeedbackBlocks = draft.page.readerFeedbackBlocks
      .map { ParsedRecipeReaderFeedbackBlock(text: $0.text) }
      .filter { !$0.text.isEmpty }
    // Re-normalize the harvested labels the cook may have renamed at capture time: trim, drop
    // rows emptied by a rename, and collapse case-insensitive duplicates (preserving order and the
    // first-seen casing). The builder normalizes on parse; hand-edits need the same pass before commit.
    draft.page.categoryNames = Self.normalizedLabelNames(draft.page.categoryNames)
    draft.page.tagNames = Self.normalizedLabelNames(draft.page.tagNames)
    self.draft = draft
    // Selection stays pure until commit, so re-extraction cannot turn an accepted chip into a
    // harvested-looking label. The repository receives typed suggestions alongside the imported
    // page and remains the sole writer of categories, facets, and joins.
    return (draft, acceptedLabelSuggestions)
  }

  /// Accepted suggestions stay typed through commit. Strings remain only in the model-response
  /// boundary; the repository receives facet and category identities where they already exist.
  var acceptedLabelSuggestions: [SuggestedLabel] {
    suggestedLabels
      .filter { acceptedSuggestedLabelIDs.contains($0.id) }
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
        let vocabulary = try await database.read { db in
          LabelVocabulary(
            facets: try Facet.fetchAll(db),
            categories: try Category.fetchAll(db)
          )
        }
        let proposal = try await labelProposer(
          recipe: proposedForPage.labelProposalRecipe,
          vocabulary: vocabulary
        )
        guard self.labelSuggestionGeneration == generation else { return }
        // Publisher-harvested labels are already part of this draft. They are not a model proposal to
        // approve or remove, even when the model correctly recognizes the same category.
        suggestedLabels = filteringHarvestedLabels(from: proposal.accepted, in: proposedForPage)
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

  static func normalizedLabelNames(_ names: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for name in names {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let key = trimmed.lowercased()
      guard seen.insert(key).inserted else { continue }
      result.append(trimmed)
    }
    return result
  }

  func filteringHarvestedLabels(
    from suggestions: [SuggestedLabel],
    in page: ParsedRecipePage
  ) -> [SuggestedLabel] {
    suggestions.filter { suggestion in
      !page.categoryNames.contains {
        $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
      }
        && !page.tagNames.contains {
          $0.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
        }
    }
  }
}
