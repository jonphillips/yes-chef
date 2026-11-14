import CloudKit
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite(.serialized)
@MainActor
struct CookbookLibraryModelTests {
  @Test func fetchesAreSerializedAndAConcurrentTriggerGetsOneFollowUp() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.uuid = .incrementing
    } operation: {
      let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "owner")
      let stub = CookbookLibraryFetchStub(zones: [zone])
      let model = CookbookLibraryModel(fetchClient: await stub.client(), directory: directory)
      defer { model.contexts.forEach { try? $0.mirror.deleteMirror() } }
      let firstFetch = Task { await model.fetchCookbooks() }
      try await Task.sleep(for: .milliseconds(10))
      await model.fetchCookbooks()
      await firstFetch.value
      let stats = await stub.stats()
      #expect(stats.pageCalls == 2)
      #expect(stats.maximumConcurrentPages == 1)
    }
  }

  @Test func vanishedZoneDeletesItsMirrorButFetchErrorsClearOnlyAfterSuccess() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.uuid = .incrementing
    } operation: {
      let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "owner")
      let stub = CookbookLibraryFetchStub(zones: [zone])
      let model = CookbookLibraryModel(fetchClient: await stub.client(), directory: directory)
      defer { model.contexts.forEach { try? $0.mirror.deleteMirror() } }
      await stub.failNextPage()
      await model.fetchCookbooks()
      #expect(model.errorMessage != nil)
      await model.fetchCookbooks()
      #expect(model.errorMessage == nil)
      #expect(model.contexts.count == 1)
      let mirrorURL = try #require(model.contexts.first?.mirror.fileURL)
      await stub.setZones([])
      await model.fetchCookbooks()
      #expect(model.contexts.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: mirrorURL.path))
    }
  }
}

private actor CookbookLibraryFetchStub {
  private var zones: [CKRecordZone.ID]
  private var shouldFailNextPage = false
  private var pageCalls = 0
  private var activePages = 0
  private var maximumConcurrentPages = 0

  init(zones: [CKRecordZone.ID]) { self.zones = zones }

  func client() -> CookbookFetchClient {
    CookbookFetchClient(
      sharedZones: { await self.currentZones() },
      fetchPage: { _, _ in try await self.fetchPage() },
      fetchDisplayImage: { _, _ in Data() }
    )
  }

  func currentZones() -> [CKRecordZone.ID] { zones }

  func setZones(_ zones: [CKRecordZone.ID]) { self.zones = zones }

  func failNextPage() { shouldFailNextPage = true }

  func stats() -> (pageCalls: Int, maximumConcurrentPages: Int) {
    (pageCalls, maximumConcurrentPages)
  }

  func fetchPage() async throws -> CookbookFetchedPage {
    activePages += 1
    maximumConcurrentPages = max(maximumConcurrentPages, activePages)
    defer { activePages -= 1 }
    try await Task.sleep(for: .milliseconds(100))
    pageCalls += 1
    if shouldFailNextPage {
      shouldFailNextPage = false
      throw CKError(.quotaExceeded)
    }
    return CookbookFetchedPage(records: [], deletions: [], changeToken: Data("\(pageCalls)".utf8), moreComing: false)
  }
}
