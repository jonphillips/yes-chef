import Dependencies
import LLMClientKit
import YesChefCore

extension HandoffReviewCoordinator {
  func draftRecipeAdjustment(
    _ review: AIHandoffRecipeAdjustmentBriefReview,
    brief: String
  ) async throws -> RecipeAdjustmentReviewState {
    @Dependency(\.recipeAdjustmentClient) var recipeAdjustmentClient
    @Dependency(\.apiKeyStore) var apiKeyStore
    @Dependency(\.recipeChatProviderPreference) var providerPreference
    @Dependency(\.recipeChatTierPreference) var tierPreference

    let trimmedBrief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBrief.isEmpty else { throw HandoffReviewError.emptyDeliverable }
    guard let baseDetail = try await database.read({ db in
      try RecipeDetailRequest(recipeID: review.recipeID).fetch(db)
    }) else {
      throw RecipeAdjustmentError.missingRecipe(review.recipeID)
    }

    let scopedVariation = review.variationID.flatMap { id in
      baseDetail.variations.first { $0.id == id }
    }
    if review.variationID != nil, scopedVariation == nil {
      throw RecipeAdjustmentError.missingVariation(review.variationID!)
    }
    let detail = try scopedVariation.map { try baseDetail.resolved(applying: $0) } ?? baseDetail

    let availableProviders = FrontierProvider.allCases.filter { apiKeyStore.key($0) != nil }
    let resolvedTier = try resolveTier(
      useFrontier: tierPreference.current(),
      preferredProvider: providerPreference.current(),
      availableProviders: availableProviders,
      requirement: .frontierRequired
    )

    let proposal = try await recipeAdjustmentClient(
      selection: "",
      messages: [RecipeChatMessage(role: .user, text: trimmedBrief)],
      detail: detail,
      tier: resolvedTier.tier,
      tierResolution: resolvedTier.resolution
    )
    return RecipeAdjustmentReviewState(
      currentDetail: detail,
      proposedDetail: try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { uuid() }),
      proposal: proposal,
      deliberationBody: brief,
      variationID: scopedVariation?.id,
      variationName: scopedVariation?.name,
      variationNote: scopedVariation?.note
    )
  }
}
