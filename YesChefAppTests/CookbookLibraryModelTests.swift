import CloudKit
import Dependencies
import Foundation
import GRDB
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

  @Test func subsequentFetchUpdatesTheSameObservableMirrorAndUsesProfileName() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.uuid = .incrementing
    } operation: {
      let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "zone-owner-id")
      let recipeID = UUID()
      let now = Date(timeIntervalSince1970: 1_000)
      let firstRecipe = Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now)
      let updatedRecipe = Recipe(id: recipeID, title: "Updated soup", dateCreated: now, dateModified: now)
      let profile = CookbookPublishProfile(
        displayName: "Jon", recipeCount: 1, payloadVersion: RecipeBundleCoding.currentVersion, publishedAt: now
      )
      let stub = CookbookLibraryPageStub(zone: zone, pages: [
        CookbookFetchedPage(
          records: [
            .recipe(name: recipeID.uuidString, payload: try CookbookPayload.encodedPayload(.init(recipe: firstRecipe)),
              version: RecipeBundleCoding.currentVersion),
            .profile(profile),
          ], deletions: [], changeToken: Data("first".utf8), moreComing: false
        ),
        CookbookFetchedPage(
          records: [.recipe(name: recipeID.uuidString, payload: try CookbookPayload.encodedPayload(.init(recipe: updatedRecipe)),
            version: RecipeBundleCoding.currentVersion)],
          deletions: [], changeToken: Data("second".utf8), moreComing: false
        ),
      ], holdFirstPage: true)
      let model = CookbookLibraryModel(fetchClient: stub.client(), directory: directory)
      defer { model.contexts.forEach { try? $0.mirror.deleteMirror() } }

      let initialFetch = Task { await model.fetchCookbooks() }
      await stub.waitUntilFirstRequest()
      #expect(model.contexts.first?.ownerName == "Family cookbook")
      #expect(model.contexts.first?.ownerName != zone.ownerName)
      await stub.releaseFirstPage()
      await initialFetch.value
      let firstContext = try #require(model.contexts.first)
      #expect(firstContext.ownerName == "Jon")
      #expect(firstContext.zoneOwnerName == zone.ownerName)
      var titles = ValueObservation.tracking { try Recipe.find(recipeID).fetchOne($0)?.title }
        .values(in: firstContext.mirror.database).makeAsyncIterator()
      #expect(try await titles.next() == "Soup")

      await model.fetchCookbooks()
      let updatedContext = try #require(model.contexts.first)
      #expect(updatedContext.mirror === firstContext.mirror)
      #expect(try await titles.next() == "Updated soup")
      #expect(await stub.requestedTokens == [nil, Data("first".utf8)])
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

private actor CookbookLibraryPageStub {
  private let zone: CKRecordZone.ID
  private var pages: [CookbookFetchedPage]
  private let holdFirstPage: Bool
  private var didHoldFirstPage = false
  private var firstRequestContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private(set) var requestedTokens: [Data?] = []

  init(zone: CKRecordZone.ID, pages: [CookbookFetchedPage], holdFirstPage: Bool = false) {
    self.zone = zone
    self.pages = pages
    self.holdFirstPage = holdFirstPage
  }

  nonisolated func client() -> CookbookFetchClient {
    CookbookFetchClient(
      sharedZones: { [zone = self.zone] in [zone] },
      fetchPage: { [weak self] _, token in
        guard let self else { throw CKError(.internalError) }
        return try await self.next(token: token)
      },
      fetchDisplayImage: { _, _ in Data() }
    )
  }

  private func next(token: Data?) async throws -> CookbookFetchedPage {
    requestedTokens.append(token)
    if holdFirstPage, !didHoldFirstPage {
      didHoldFirstPage = true
      firstRequestContinuation?.resume()
      firstRequestContinuation = nil
      await withCheckedContinuation { releaseContinuation = $0 }
    }
    guard !pages.isEmpty else { throw CKError(.internalError) }
    return pages.removeFirst()
  }

  func waitUntilFirstRequest() async {
    if didHoldFirstPage { return }
    await withCheckedContinuation { firstRequestContinuation = $0 }
  }

  func releaseFirstPage() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}
