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

  private var cache: [CompareAlignmentKey: WorkbenchAlignedComparison] = [:]
  private var loadToken = 0

  var currentKey: CompareAlignmentKey?
  var currentOutcome: WorkbenchAlignedComparison?
  var isAligning = false
  var showsBasicViewAffordance = false

  func cachedOutcome(for key: CompareAlignmentKey) -> WorkbenchAlignedComparison? {
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
      currentOutcome = cached
      isAligning = false
      showsBasicViewAffordance = cached.source.isFallback
      return
    }

    if refresh {
      cache.removeValue(forKey: key)
    }

    currentOutcome = nil
    isAligning = true
    showsBasicViewAffordance = false

    do {
      let outcome = try await aligner(working: working, candidates: candidates, tier: tier)
      try Task.checkCancellation()
      guard token == loadToken else { return }
      cache[key] = outcome
      currentOutcome = outcome
      isAligning = false
      showsBasicViewAffordance = outcome.source.isFallback
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
