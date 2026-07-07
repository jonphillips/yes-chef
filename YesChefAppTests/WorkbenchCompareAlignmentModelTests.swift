import Dependencies
import DependenciesTestSupport
import LLMClientKit
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
struct WorkbenchCompareAlignmentModelTests {
  @Test
  func alignmentKeyIdentityIsStableWhileContentSignatureTracksText() {
    let working = detail(recipeID: uuid("11111111-1111-1111-1111-111111111111"), lineText: "1 cup onions")
    let candidate = detail(recipeID: uuid("22222222-2222-2222-2222-222222222222"), lineText: "2 cups onions")

    let baseline = CompareAlignmentKey(working: working, candidates: [candidate])
    let editedText = CompareAlignmentKey(
      working: detail(recipeID: working.recipe.id, lineText: "9 cups onions"),
      candidates: [candidate]
    )

    // Editing ingredient text keeps the same cache slot (identity) but changes the content fingerprint.
    #expect(baseline.identity == editedText.identity)
    #expect(baseline.contentSignature != editedText.contentSignature)
  }

  @Test
  func alignmentModelFallsBackToDeterministicWhenAlignerThrows() async {
    let working = detail(recipeID: uuid("55555555-5555-5555-5555-555555555555"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("66666666-6666-6666-6666-666666666666"), lineText: "2 cups tomatoes")
    let key = CompareAlignmentKey(working: working, candidates: [candidate])

    let state = await withDependencies {
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        throw TestError.failure
      }
    } operation: {
      let model = await MainActor.run { WorkbenchCompareAlignmentModel() }
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      return await MainActor.run {
        (
          model.cachedOutcome(for: key),
          model.currentOutcome,
          model.isAligning,
          model.showsBasicViewAffordance
        )
      }
    }

    #expect(state.0 == nil)
    #expect(state.1 == nil)
    #expect(state.2 == false)
    #expect(state.3 == true)
  }

  @Test
  func fallbackOutcomeSetsAndKeepsBasicViewAffordanceFromCache() async {
    let working = detail(recipeID: uuid("77777777-7777-7777-7777-777777777777"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("88888888-8888-8888-8888-888888888888"), lineText: "2 cups tomatoes")
    let key = CompareAlignmentKey(working: working, candidates: [candidate])
    let deterministic = WorkbenchCompare.ingredientComparison(working: working, candidates: [candidate])

    let state = await withDependencies {
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        WorkbenchAlignedComparison(
          comparison: deterministic,
          source: .fallback(.malformed)
        )
      }
    } operation: {
      let model = await MainActor.run { WorkbenchCompareAlignmentModel() }
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      return await MainActor.run {
        (
          model.cachedOutcome(for: key),
          model.currentOutcome,
          model.isAligning,
          model.showsBasicViewAffordance
        )
      }
    }

    #expect(state.0?.source == .fallback(.malformed))
    #expect(state.0?.comparison == deterministic)
    #expect(state.1?.source == .fallback(.malformed))
    #expect(state.2 == false)
    #expect(state.3 == true)
  }

  @Test
  func diskHitSkipsLLMAndSeedsMemoryCache() async {
    let working = detail(recipeID: uuid("99999999-9999-9999-9999-999999999999"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"), lineText: "2 cups tomatoes")
    let key = CompareAlignmentKey(working: working, candidates: [candidate])
    let harness = CacheHarness()
    let cached = alignedOutcome(working: working, candidate: candidate, label: "Cached Tomato")
    await harness.seed(record(cached, contentSignature: key.contentSignature), for: key.identity)
    let alignerCalls = LockedCounter()

    let state = await withDependencies {
      $0.compareAlignmentCache = harness.client()
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        await alignerCalls.increment()
        return alignedOutcome(working: working, candidate: candidate, label: "Fresh Tomato")
      }
    } operation: {
      let model = await MainActor.run { WorkbenchCompareAlignmentModel() }
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      return await MainActor.run {
        (
          model.cachedOutcome(for: key),
          model.currentOutcome,
          model.isStale
        )
      }
    }

    #expect(await alignerCalls.value == 0)
    #expect(state.0 == cached)
    #expect(state.1 == cached)
    #expect(state.2 == false)
  }

  @Test
  func staleDiskHitShowsCachedOutcomeAndFlagsStaleWithoutRealigning() async {
    let working = detail(recipeID: uuid("12121212-1212-1212-1212-121212121212"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("34343434-3434-3434-3434-343434343434"), lineText: "2 cups tomatoes")
    let key = CompareAlignmentKey(working: working, candidates: [candidate])
    let harness = CacheHarness()
    let stale = alignedOutcome(working: working, candidate: candidate, label: "Stale Tomato")
    // Seed a record aligned against *older* text — the content signature no longer matches.
    await harness.seed(record(stale, contentSignature: "content-v1-outdated"), for: key.identity)
    let alignerCalls = LockedCounter()

    let state = await withDependencies {
      $0.compareAlignmentCache = harness.client()
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        await alignerCalls.increment()
        return alignedOutcome(working: working, candidate: candidate, label: "Fresh Tomato")
      }
    } operation: {
      let model = await MainActor.run { WorkbenchCompareAlignmentModel() }
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      return await MainActor.run {
        (
          model.currentOutcome,
          model.isStale
        )
      }
    }

    // Content drifted, but we show the cached alignment and flag it stale — no automatic LLM call.
    #expect(await alignerCalls.value == 0)
    #expect(state.0 == stale)
    #expect(state.1 == true)
  }

  @Test
  func fallbackIsKeptInMemoryButNotPersistedAcrossColdStart() async {
    let working = detail(recipeID: uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("cccccccc-cccc-cccc-cccc-cccccccccccc"), lineText: "2 cups tomatoes")
    let harness = CacheHarness()
    let alignerCalls = LockedCounter()
    let deterministic = WorkbenchCompare.ingredientComparison(working: working, candidates: [candidate])
    let fallback = WorkbenchAlignedComparison(comparison: deterministic, source: .fallback(.malformed))

    await withDependencies {
      $0.compareAlignmentCache = harness.client()
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        await alignerCalls.increment()
        return fallback
      }
    } operation: {
      let firstModel = await MainActor.run { WorkbenchCompareAlignmentModel() }
      let secondModel = await MainActor.run { WorkbenchCompareAlignmentModel() }
      await firstModel.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      await secondModel.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
    }

    #expect(await alignerCalls.value == 2)
    #expect(await harness.saveCallCount == 0)
  }

  @Test
  func refreshBypassesCachesAndOverwritesPersistedAlignedOutcome() async {
    let working = detail(recipeID: uuid("dddddddd-dddd-dddd-dddd-dddddddddddd"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"), lineText: "2 cups tomatoes")
    let key = CompareAlignmentKey(working: working, candidates: [candidate])
    let harness = CacheHarness()
    let cached = alignedOutcome(working: working, candidate: candidate, label: "Cached Tomato")
    let refreshed = alignedOutcome(working: working, candidate: candidate, label: "Refreshed Tomato")
    await harness.seed(record(cached, contentSignature: key.contentSignature), for: key.identity)
    let alignerCalls = LockedCounter()

    let state = await withDependencies {
      $0.compareAlignmentCache = harness.client()
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        await alignerCalls.increment()
        return refreshed
      }
    } operation: {
      let model = await MainActor.run { WorkbenchCompareAlignmentModel() }
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
      await model.refreshButtonTapped(working: working, candidates: [candidate], tier: .frontier(.openai))
      return await MainActor.run {
        (
          model.cachedOutcome(for: key),
          model.currentOutcome
        )
      }
    }

    #expect(await alignerCalls.value == 1)
    #expect(await harness.loadCallCount == 1)
    #expect(await harness.savedRecord(for: key.identity)?.outcome == refreshed)
    #expect(state.0 == refreshed)
    #expect(state.1 == refreshed)
  }
}

private enum TestError: Error {
  case failure
}

private actor CacheHarness {
  private var entries: [String: CachedCompareAlignment] = [:]
  private(set) var loadCallCount = 0
  private(set) var saveCallCount = 0

  nonisolated func client() -> CompareAlignmentCacheClient {
    CompareAlignmentCacheClient(
      load: { identity in await self.load(identity) },
      save: { identity, record in await self.save(record, for: identity) }
    )
  }

  func seed(_ record: CachedCompareAlignment, for identity: String) {
    entries[identity] = record
  }

  func load(_ identity: String) -> CachedCompareAlignment? {
    loadCallCount += 1
    return entries[identity]
  }

  func save(_ record: CachedCompareAlignment, for identity: String) {
    saveCallCount += 1
    entries[identity] = record
  }

  func savedRecord(for identity: String) -> CachedCompareAlignment? {
    entries[identity]
  }
}

private actor LockedCounter {
  private var rawValue = 0

  func increment() {
    rawValue += 1
  }

  var value: Int { rawValue }
}

private func record(
  _ outcome: WorkbenchAlignedComparison,
  contentSignature: String
) -> CachedCompareAlignment {
  CachedCompareAlignment(contentSignature: contentSignature, outcome: outcome)
}

private func alignedOutcome(
  working: RecipeDetailData,
  candidate: RecipeDetailData,
  label: String
) -> WorkbenchAlignedComparison {
  WorkbenchAlignedComparison(
    comparison: IngredientComparison(
      columns: [
        IngredientMatrixColumn(id: working.recipe.id, title: working.recipe.title, role: .working),
        IngredientMatrixColumn(id: candidate.recipe.id, title: candidate.recipe.title, role: .candidate),
      ],
      rows: [
        IngredientMatrixRow(
          id: label.lowercased(),
          label: label,
          cells: [working.ingredientLines.first?.originalText, candidate.ingredientLines.first?.originalText]
        )
      ]
    ),
    source: .aligned
  )
}

private func detail(recipeID: UUID, lineText: String) -> RecipeDetailData {
  let prefix = String(recipeID.uuidString.prefix(8))
  let sectionID = uuid("\(prefix)-0000-0000-0000-000000000000")
  return RecipeDetailData(
    recipe: Recipe(
      id: recipeID,
      title: recipeID.uuidString,
      dateCreated: Date(timeIntervalSinceReferenceDate: 0),
      dateModified: Date(timeIntervalSinceReferenceDate: 0)
    ),
    ingredientSections: [
      IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
    ],
    ingredientLines: [
      IngredientLine(
        id: uuid("\(prefix)-1111-1111-1111-111111111111"),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: lineText,
        sortOrder: 0
      )
    ]
  )
}

private func uuid(_ string: String) -> UUID {
  guard let uuid = UUID(uuidString: string) else {
    fatalError("Invalid UUID string: \(string)")
  }
  return uuid
}
