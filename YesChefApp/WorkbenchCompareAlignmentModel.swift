import Dependencies
import Foundation
import LLMClientKit
import Observation
import YesChefCore

@Observable
@MainActor
final class WorkbenchCompareAlignmentModel {
  @ObservationIgnored @Dependency(\.workbenchCompareAligner) private var aligner
  @ObservationIgnored @Dependency(\.compareAlignmentCache) private var cacheClient

  /// Keyed by `CompareAlignmentKey.identity` (the recipe *set*), so an ingredient-text edit reuses the
  /// same slot and the stored `contentSignature` reveals whether it has gone stale.
  private var cache: [String: CachedCompareAlignment] = [:]
  private var loadToken = 0

  var currentKey: CompareAlignmentKey?
  var currentOutcome: WorkbenchAlignedComparison?
  var isAligning = false
  var showsBasicViewAffordance = false
  /// The displayed alignment was computed against older ingredient text. We keep showing it and offer a
  /// manual **Refresh** rather than silently spending an LLM call on every edit (ADR-0022 open-Q4).
  var isStale = false

  func cachedOutcome(for key: CompareAlignmentKey) -> WorkbenchAlignedComparison? {
    cache[key.identity]?.outcome
  }

  func prefetchDiskIfNeeded(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData]
  ) async {
    let key = CompareAlignmentKey(working: working, candidates: candidates)
    guard cache[key.identity] == nil else { return }
    if let record = try? await cacheClient.load(key.identity) {
      cache[key.identity] = record
    }
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
    let previousKey = currentKey
    currentKey = key

    // A cache hit (memory or disk) never re-aligns: we show the stored alignment and, if the recipe
    // text has since changed, flag it stale for a manual refresh. Only a genuine miss — a recipe set
    // never aligned before — or an explicit refresh spends an LLM call.
    if !refresh {
      if let record = cache[key.identity] {
        present(record, for: key, token: token)
        return
      }
    }

    if previousKey?.identity != key.identity {
      currentOutcome = nil
      isStale = false
    }

    isAligning = true
    if !refresh {
      showsBasicViewAffordance = false

      do {
        if let record = try await cacheClient.load(key.identity) {
          try Task.checkCancellation()
          guard token == loadToken else { return }
          cache[key.identity] = record
          present(record, for: key, token: token)
          return
        }
      } catch is CancellationError {
        guard token == loadToken else { return }
        isAligning = false
        return
      } catch {
        // Advisory cache I/O should quietly fall through to a fresh alignment attempt.
      }
    }

    do {
      let outcome = try await aligner(working: working, candidates: candidates, tier: tier)
      try Task.checkCancellation()
      guard token == loadToken else { return }
      let record = CachedCompareAlignment(contentSignature: key.contentSignature, outcome: outcome)
      if outcome.source == .aligned {
        try? await cacheClient.save(key.identity, record)
      }
      cache[key.identity] = record
      currentOutcome = outcome
      isAligning = false
      isStale = false
      showsBasicViewAffordance = outcome.source.isFallback
    } catch is CancellationError {
      guard token == loadToken else { return }
      isAligning = false
    } catch {
      guard token == loadToken else { return }
      isAligning = false
      showsBasicViewAffordance = currentOutcome == nil
    }
  }

  /// Surface an already-computed alignment, marking it stale if the recipe text has drifted from the
  /// content it was aligned against.
  private func present(_ record: CachedCompareAlignment, for key: CompareAlignmentKey, token: Int) {
    guard token == loadToken else { return }
    currentOutcome = record.outcome
    isAligning = false
    isStale = record.contentSignature != key.contentSignature
    showsBasicViewAffordance = record.outcome.source.isFallback
  }

  private func nextLoadToken() -> Int {
    loadToken += 1
    return loadToken
  }
}
