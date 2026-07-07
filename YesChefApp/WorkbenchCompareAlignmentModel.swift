import Dependencies
import Foundation
import LLMClientKit
import Observation
import YesChefCore

struct CompareAlignmentKey: Hashable, Sendable {
  var orderedRecipeIDs: [UUID]

  init(working: RecipeDetailData?, candidates: [RecipeDetailData]) {
    orderedRecipeIDs = (working.map { [$0.recipe.id] } ?? []) + candidates.map(\.recipe.id)
  }
}

@Observable
@MainActor
final class WorkbenchCompareAlignmentModel {
  @ObservationIgnored @Dependency(\.workbenchCompareAligner) private var aligner

  private var cache: [CompareAlignmentKey: IngredientComparison] = [:]
  private var loadToken = 0

  var currentKey: CompareAlignmentKey?
  var currentComparison: IngredientComparison?
  var isAligning = false
  var showsBasicViewAffordance = false

  func cachedComparison(for key: CompareAlignmentKey) -> IngredientComparison? {
    cache[key]
  }

  func ingredientsSegmentAppeared(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData],
    tier: ModelTier
  ) async {
    await load(working: working, candidates: candidates, tier: tier, refresh: false)
  }

  func refreshButtonTapped(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData],
    tier: ModelTier
  ) async {
    await load(working: working, candidates: candidates, tier: tier, refresh: true)
  }

  private func load(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData],
    tier: ModelTier,
    refresh: Bool
  ) async {
    let key = CompareAlignmentKey(working: working, candidates: candidates)
    let token = nextLoadToken()
    currentKey = key

    if !refresh, let cached = cache[key] {
      currentComparison = cached
      isAligning = false
      showsBasicViewAffordance = false
      return
    }

    if refresh {
      cache.removeValue(forKey: key)
    }

    currentComparison = nil
    isAligning = true
    showsBasicViewAffordance = false

    do {
      let comparison = try await aligner(working: working, candidates: candidates, tier: tier)
      try Task.checkCancellation()
      guard token == loadToken else { return }
      cache[key] = comparison
      currentComparison = comparison
      isAligning = false
      showsBasicViewAffordance = false
    } catch is CancellationError {
      guard token == loadToken else { return }
      isAligning = false
    } catch {
      guard token == loadToken else { return }
      isAligning = false
      showsBasicViewAffordance = true
    }
  }

  private func nextLoadToken() -> Int {
    loadToken += 1
    return loadToken
  }
}
