import Observation
import YesChefCore

@Observable
@MainActor
final class RecipeLabelState {
  var suggestions: [SuggestedLabel] = []
  var acceptedIDs: Set<SuggestedLabel.ID> = []
  var isSuggesting = false
}

extension RecipeDetailModel {
  var hasAcceptedSuggestedLabels: Bool {
    !labelState.acceptedIDs.isEmpty
  }

  func suggestLabelsButtonTapped() {
    guard let detail else { return }
    labelState.suggestions = []
    labelState.acceptedIDs = []
    labelState.isSuggesting = true
    destination = .labelSuggestions

    Task { [weak self] in
      guard let self else { return }
      do {
        let vocabulary = try await database.read { db in
          LabelVocabulary(
            facets: try Facet.fetchAll(db),
            categories: try Category.fetchAll(db)
          )
        }
        let proposal = try await labelProposer(recipe: detail.labelProposalRecipe, vocabulary: vocabulary)
        labelState.suggestions = proposal.accepted
      } catch is CancellationError {
      } catch {
        errorMessage = error.localizedDescription
        isShowingError = true
      }
      labelState.isSuggesting = false
    }
  }

  func suggestedLabelTapped(_ suggestion: SuggestedLabel) {
    if labelState.acceptedIDs.contains(suggestion.id) {
      labelState.acceptedIDs.remove(suggestion.id)
    } else {
      labelState.acceptedIDs.insert(suggestion.id)
    }
  }

  func isSuggestedLabelAccepted(_ suggestion: SuggestedLabel) -> Bool {
    labelState.acceptedIDs.contains(suggestion.id)
  }

  func saveSuggestedLabelsButtonTapped() async -> Bool {
    let accepted = labelState.suggestions.filter { labelState.acceptedIDs.contains($0.id) }
    guard !accepted.isEmpty else { return false }
    do {
      let currentNow = now
      let makeUUID = uuid
      try await database.write { db in
        try RecipeRepository.reconcileSuggestedLabels(
          accepted,
          recipeID: recipeID,
          in: db,
          now: currentNow,
          uuid: { makeUUID() }
        )
      }
      labelState.suggestions = []
      labelState.acceptedIDs = []
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func addTagButtonTapped(_ categoryID: Category.ID) async -> Bool {
    await updatingAssignedCategoryIDs(adding: categoryID)
  }

  func deleteTagButtonTapped(_ categoryID: Category.ID) async -> Bool {
    await updatingAssignedCategoryIDs(removing: categoryID)
  }

  private func updatingAssignedCategoryIDs(
    adding categoryIDToAdd: Category.ID? = nil,
    removing categoryIDToRemove: Category.ID? = nil
  ) async -> Bool {
    do {
      let makeUUID = uuid
      try await database.write { db in
        var categoryIDs = Set(
          try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db).map(\.categoryID)
        )
        if let categoryIDToAdd {
          categoryIDs.insert(categoryIDToAdd)
        }
        if let categoryIDToRemove {
          categoryIDs.remove(categoryIDToRemove)
        }
        try RecipeRepository.reconcileCategoryIDs(
          Array(categoryIDs),
          recipeID: recipeID,
          in: db,
          uuid: { makeUUID() }
        )
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }
}
