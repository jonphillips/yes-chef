import LLMClientKit
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
    destination = .labelSuggestions
    refreshLabelSuggestions()
  }

  func tagEditorAppeared() {
    guard labelState.suggestions.isEmpty else { return }
    refreshLabelSuggestions()
  }

  func acceptSuggestedLabelButtonTapped(_ suggestion: SuggestedLabel) async -> Bool {
    guard !labelState.acceptedIDs.contains(suggestion.id) else { return false }
    labelState.acceptedIDs.insert(suggestion.id)
    do {
      let currentNow = now
      let makeUUID = uuid
      try await database.write { db in
        try RecipeRepository.reconcileSuggestedLabels(
          [suggestion],
          recipeID: recipeID,
          in: db,
          now: currentNow,
          uuid: { makeUUID() }
        )
      }
      return true
    } catch {
      labelState.acceptedIDs.remove(suggestion.id)
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  private func refreshLabelSuggestions() {
    guard let detail, !labelState.isSuggesting else { return }
    labelState.suggestions = []
    labelState.acceptedIDs = []
    labelState.isSuggesting = true

    Task { [weak self] in
      guard let self else { return }
      do {
        let vocabulary = try await database.read { db in
          LabelVocabulary(
            facets: try Facet.fetchAll(db),
            categories: try Category.fetchAll(db)
          )
        }
        // This is a user-tapped action on an existing recipe — the cook taps Suggest and waits, so
        // it can afford the better tier for the "name the cuisine" judgment the on-device model is
        // weakest at ([[personal-app-latency-tolerance]]). Resolve from the same AI-settings
        // preferences the chat uses; `.onDeviceCompatible` degrades to on-device when no frontier
        // key is configured or the cook has chosen on-device, so nothing changes for those users.
        let availableProviders = FrontierProvider.allCases.filter { apiKeyStore.key($0) != nil }
        let resolvedTier = try resolveTier(
          useFrontier: labelTierPreference.current(),
          preferredProvider: labelProviderPreference.current(),
          availableProviders: availableProviders,
          requirement: .onDeviceCompatible
        )
        let proposal = try await labelProposer(
          recipe: detail.labelProposalRecipe,
          vocabulary: vocabulary,
          tier: resolvedTier.tier
        )
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
