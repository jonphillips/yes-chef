import Foundation
import Testing
@testable import YesChefCore

@Suite
struct CompareAlignmentCacheStoreTests {
  @Test
  func persistsAcrossColdStart() async throws {
    let fileURL = temporaryCacheFile()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    let writer = CompareAlignmentCacheStore(fileURL: fileURL, maxEntries: 50)
    try await writer.save(record("beef"), identity: "set-1")

    // A fresh store instance over the same file is the "cold start" — it must rehydrate from disk.
    let reader = CompareAlignmentCacheStore(fileURL: fileURL, maxEntries: 50)
    let loaded = try await reader.load(identity: "set-1")

    #expect(loaded == record("beef"))
  }

  @Test
  func evictsLeastRecentlyUsedBeyondBudget() async throws {
    let fileURL = temporaryCacheFile()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    let store = CompareAlignmentCacheStore(fileURL: fileURL, maxEntries: 2)
    try await store.save(record("a"), identity: "a")
    try await store.save(record("b"), identity: "b")
    try await store.save(record("c"), identity: "c") // over budget → evicts "a" (least recent)

    _ = try await store.load(identity: "b")            // touch "b" so "c" is now least recent
    try await store.save(record("d"), identity: "d")   // over budget → evicts "c"

    #expect(try await store.load(identity: "a") == nil)
    #expect(try await store.load(identity: "c") == nil)
    #expect(try await store.load(identity: "b") == record("b"))
    #expect(try await store.load(identity: "d") == record("d"))
  }

  @Test
  func evictionSurvivesColdStart() async throws {
    let fileURL = temporaryCacheFile()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    let writer = CompareAlignmentCacheStore(fileURL: fileURL, maxEntries: 2)
    try await writer.save(record("a"), identity: "a")
    try await writer.save(record("b"), identity: "b")
    try await writer.save(record("c"), identity: "c") // "a" evicted before persist

    let reader = CompareAlignmentCacheStore(fileURL: fileURL, maxEntries: 2)
    #expect(try await reader.load(identity: "a") == nil)
    #expect(try await reader.load(identity: "b") == record("b"))
    #expect(try await reader.load(identity: "c") == record("c"))
  }
}

private func temporaryCacheFile() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("compare-alignment-store-tests-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("cache.json", isDirectory: false)
}

private func record(_ label: String) -> CachedCompareAlignment {
  CachedCompareAlignment(
    contentSignature: "content-v1-\(label)",
    outcome: WorkbenchAlignedComparison(
      comparison: IngredientComparison(
        columns: [],
        rows: [IngredientMatrixRow(id: label, label: label, cells: [])]
      ),
      source: .aligned
    )
  )
}
