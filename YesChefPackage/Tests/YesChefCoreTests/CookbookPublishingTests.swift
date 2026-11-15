import CloudKit
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing
import YesChefCore

struct CookbookPublishingTests {
  @Test func fetcherAppliesEveryPageAndCommitsTheFullSweepWithItsToken() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 1_000)
    let first = Recipe(id: UUID(), title: "First", dateCreated: now, dateModified: now)
    let second = Recipe(id: UUID(), title: "Second", dateCreated: now, dateModified: now)
    let stale = Recipe(id: UUID(), title: "Stale", dateCreated: now, dateModified: now)
    let profile = CookbookPublishProfile(displayName: "Jon", recipeCount: 2, payloadVersion: 2, publishedAt: now)
    let firstPayload = try CookbookPayload.encodedPayload(.init(recipe: first))
    let secondPayload = try CookbookPayload.encodedPayload(.init(recipe: second))
    let stub = CookbookFetchPageStub(pages: [
      CookbookFetchedPage(
        records: [.recipe(name: first.id.uuidString, payload: firstPayload, version: 2), .profile(profile)],
        deletions: [], changeToken: Data("one".utf8), moreComing: true
      ),
      CookbookFetchedPage(
        records: [.recipe(name: second.id.uuidString, payload: secondPayload, version: 2)],
        deletions: [], changeToken: Data("two".utf8), moreComing: false
      ),
    ])
    let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "family-owner")
    let client = CookbookFetchClient(
      sharedZones: { [zone] },
      fetchPage: { _, _ in try await stub.next() },
      fetchDisplayImage: { _, _ in Data() }
    )
    try await withDependencies { $0.context = .live; $0.date.now = now } operation: {
      try mirror.apply(upserting: [.init(recipe: stale)], deleting: [])
      try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: client)
      let ids = try await mirror.database.read { try Recipe.fetchAll($0).map(\.id) }
      #expect(Set(ids) == Set([first.id, second.id]))
      #expect(try mirror.fetchState().displayName == "Jon")
      #expect(try mirror.fetchState().changeToken == Data("two".utf8))
      #expect(!(try mirror.fetchState().fullFetchActive))
    }
  }

  @Test func newerPayloadVersionResetsTokenForFullFetchAndIncrementalUpdatesStayUncounted() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "family-owner")
    let now = Date(timeIntervalSince1970: 1_000)
    let recipe = Recipe(id: UUID(), title: "Readable again", dateCreated: now, dateModified: now)
    let payload = try CookbookPayload.encodedPayload(.init(recipe: recipe))
    let requests = CookbookFetchRequestRecorder()
    let progress = CookbookFetchProgressRecorder()
    let pages = CookbookFetchPageStub(pages: [
      CookbookFetchedPage(
        records: [
          .recipe(name: recipe.id.uuidString, payload: payload, version: RecipeBundleCoding.currentVersion),
          .profile(.init(displayName: "Jon", recipeCount: 1, payloadVersion: RecipeBundleCoding.currentVersion, publishedAt: now)),
          .ignored,
        ], deletions: [], changeToken: Data("fresh".utf8), moreComing: false
      ),
      CookbookFetchedPage(records: [.ignored], deletions: [], changeToken: Data("incremental".utf8), moreComing: false),
    ])
    let client = CookbookFetchClient(
      sharedZones: { [zone] },
      fetchPage: { _, token in
        await requests.append(token)
        return try await pages.next()
      },
      fetchDisplayImage: { _, _ in Data() }
    )
    try await withDependencies { $0.context = .live; $0.date.now = now } operation: {
      try mirror.apply(page: CookbookMirrorPage(
        changeToken: Data("stale".utf8), payloadVersion: RecipeBundleCoding.currentVersion - 1
      ))
      try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: client) { await progress.append($0) }
      #expect(await requests.values == [nil])
      #expect(await progress.values.map(\.isFullFetch) == [true])
      #expect(try mirror.fetchState().changeToken == Data("fresh".utf8))
      #expect(try mirror.skippedRecordCount() == 0)

      await progress.reset()
      try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: client) { await progress.append($0) }
      #expect(await requests.values == [nil, Data("fresh".utf8)])
      #expect(await progress.values.map(\.isFullFetch) == [false])
      #expect(try mirror.fetchState().changeToken == Data("incremental".utf8))
      #expect(try mirror.fetchState().changeToken == Data("incremental".utf8))
    }
  }

  @Test func newerLensIsCountedButMalformedSupportedLensFailsItsPage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "family-owner")
    let lenses = CookbookLensBundle(lenses: [], shelves: [], categories: [], facets: [])
    let payload = try lenses.encodedPayload()
    let future = CookbookFetchPageStub(pages: [
      CookbookFetchedPage(records: [.lenses(name: "lenses", payload: payload, version: CookbookLensBundle.currentVersion + 1)],
        deletions: [], changeToken: Data("future".utf8), moreComing: false),
    ])
    let futureClient = CookbookFetchClient(
      sharedZones: { [zone] }, fetchPage: { _, _ in try await future.next() }, fetchDisplayImage: { _, _ in Data() }
    )
    try await withDependencies { $0.context = .live } operation: {
      try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: futureClient)
      #expect(try mirror.skippedRecordCount() == 1)

      let corrupt = CookbookFetchPageStub(pages: [
        CookbookFetchedPage(records: [.lenses(name: "lenses", payload: Data("{".utf8), version: CookbookLensBundle.currentVersion)],
          deletions: [], changeToken: Data("corrupt".utf8), moreComing: false),
      ])
      let corruptClient = CookbookFetchClient(
        sharedZones: { [zone] }, fetchPage: { _, _ in try await corrupt.next() }, fetchDisplayImage: { _, _ in Data() }
      )
      await #expect(throws: (any Error).self) {
        try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: corruptClient)
      }
      #expect(try mirror.fetchState().changeToken == Data("future".utf8))
      #expect(try mirror.skippedRecordCount() == 1)
    }
  }

  @Test func fullFetchReportsTheProfileBeforeTheFirstPage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 1_000)
    let profile = CookbookPublishProfile(displayName: "Jon", recipeCount: 2_190, payloadVersion: 2, publishedAt: now)
    let progress = CookbookFetchProgressRecorder()
    let pages = CookbookFetchPageStub(pages: [
      CookbookFetchedPage(records: [], deletions: [], changeToken: Data("full-1".utf8), moreComing: true),
      CookbookFetchedPage(records: [.profile(profile)], deletions: [], changeToken: Data("full-2".utf8), moreComing: false),
      CookbookFetchedPage(records: [], deletions: [], changeToken: Data("incremental".utf8), moreComing: false),
    ])
    let zone = CKRecordZone.ID(zoneName: "Cookbook", ownerName: "family-owner")
    let client = CookbookFetchClient(
      sharedZones: { [zone] },
      fetchPage: { _, _ in try await pages.next() },
      fetchDisplayImage: { _, _ in Data() },
      fetchProfile: { _ in profile }
    )
    try await withDependencies { $0.context = .live; $0.date.now = now } operation: {
      try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: client) { await progress.append($0) }
      let first = try #require(await progress.values.first)
      #expect(first.fetched == 0)
      #expect(first.total == 2_190)
      #expect(first.displayName == "Jon")
      #expect(first.isFullFetch)

      await progress.reset()
      try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: client) { await progress.append($0) }
      #expect(await progress.values.map(\.isFullFetch) == [false])
    }
  }

  @Test func publishPlanAddsChangesAndDeletesStaleAndSpikeRecords() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let id = UUID()
    let recipe = Recipe(id: id, title: "Soup", dateCreated: now, dateModified: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion, recipe: recipe)
    let hash = try CookbookPayload.contentHash(bundle)
    let same = try CookbookPublishPlan.make(bundles: [bundle], existingHashes: [id.uuidString: hash])
    #expect(same.recipesToSave.isEmpty)
    #expect(same.recordNamesToDelete.isEmpty)

    let changedBundle = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion,
      recipe: Recipe(id: id, title: "Updated soup", dateCreated: now, dateModified: now))
    let changed = try CookbookPublishPlan.make(
      bundles: [changedBundle], existingHashes: [id.uuidString: hash, "deleted-recipe": "old", "spike-leftover": "old"]
    )
    #expect(changed.recipesToSave.map(\.recordName) == [id.uuidString])
    #expect(changed.recordNamesToDelete == ["deleted-recipe", "spike-leftover"])
    #expect(try JSONDecoder().decode(RecipeBundleCoding.RecipeBundle.self, from: changed.recipesToSave[0].payload) == changedBundle)
  }

  @Test func planMapsCoverOrFirstPhotoAsSeparateDisplayImage() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let recipeID = UUID()
    let firstID = UUID()
    let coverID = UUID()
    let first = RecipePhoto(id: firstID, recipeID: recipeID, imageDataReference: "first", sortOrder: 0, dateCreated: now)
    let cover = RecipePhoto(id: coverID, recipeID: recipeID, imageDataReference: "cover", sortOrder: 1, dateCreated: now)
    let recipe = Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now, coverPhotoID: coverID)
    let bundle = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion, recipe: recipe, photos: [cover, first])
    let plan = try CookbookPublishPlan.make(bundles: [bundle], existingHashes: [:])
    #expect(plan.recipesToSave.first?.displayPhotoID == coverID)

    let fallbackRecipe = Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now)
    let fallback = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion, recipe: fallbackRecipe, photos: [cover, first])
    let fallbackPlan = try CookbookPublishPlan.make(bundles: [fallback], existingHashes: [:])
    #expect(fallbackPlan.recipesToSave.first?.displayPhotoID == firstID)
    let noPhotoBundle = RecipeBundleCoding.RecipeBundle(
      version: RecipeBundleCoding.currentVersion,
      recipe: Recipe(id: UUID(), title: "Plain soup", dateCreated: now, dateModified: now)
    )
    let noPhotoPlan = try CookbookPublishPlan.make(bundles: [noPhotoBundle], existingHashes: [:])
    #expect(noPhotoPlan.recipesToSave.first?.displayPhotoID == nil)
    #expect(try CookbookPayload.contentHash(try CookbookPayload.encodedPayload(bundle)) == CookbookPayload.contentHash(bundle))
  }

  @Test func publishPlanHashesLensesSeparatelyAndNeverDeletesTheLensRecord() throws {
    let bundle = CookbookLensBundle(lenses: [], shelves: [], categories: [], facets: [])
    let payload = try bundle.encodedPayload()
    let hash = CookbookPayload.contentHash(payload)
    let plan = try CookbookPublishPlan.make(bundles: [], existingHashes: ["lenses": "old"], lenses: bundle)
    #expect(plan.lensesToSave?.contentHash == hash)
    #expect(plan.recordNamesToDelete.isEmpty)

    let unchanged = try CookbookPublishPlan.make(bundles: [], existingHashes: ["lenses": hash], lenses: bundle)
    #expect(unchanged.lensesToSave == nil)
    #expect(unchanged.recordNamesToDelete.isEmpty)
  }

  @Test func participantStatusesAndPermissionsUseWords() {
    #expect(CookbookParticipantRow.invitationStatus(.pending) == "invited")
    #expect(CookbookParticipantRow.invitationStatus(.accepted) == "accepted")
    #expect(CookbookParticipantRow.invitationStatus(.removed) == "removed")
    #expect(CookbookParticipantRow.permission(.none) == "no access")
    #expect(CookbookParticipantRow.permission(.readOnly) == "read-only")
    #expect(CookbookParticipantRow.permission(.readWrite) == "read-write")
  }

  @Test func recordFailureNamesTheCauseNotTheBatchRejections() {
    let batch = CKError(.batchRequestFailed)
    let failure = CookbookPublishFailure.records([batch, CKError(.quotaExceeded), batch], fallbackCount: 400)
    guard case let .failedRecords(count, cause) = failure else { return }
    #expect(count == 3)
    #expect(cause.hasPrefix("CKError quotaExceeded"))
    #expect(cause.hasSuffix("the other 2 were rejected with it"))

    let onlyBatch = CookbookPublishFailure.records([batch], fallbackCount: 1)
    #expect(onlyBatch.errorDescription?.contains("CKError batchRequestFailed") == true)
    #expect(CookbookPublishFailure.records([], fallbackCount: 7) == .failedRecords(count: 7, firstError: "Unknown CloudKit error"))
  }

  @Test func retryWaitsOnlyWhenCloudKitSaysTo() {
    let limited = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 29.5])
    #expect(CookbookRetry.delay(for: limited) == 29.5)
    #expect(CookbookRetry.delay(for: CKError(.zoneBusy)) == 5)
    #expect(CookbookRetry.delay(for: CKError(.quotaExceeded)) == nil)
    #expect(CookbookRetry.delay(for: CKError(.batchRequestFailed)) == nil)
    #expect(CookbookRetry.delay(forRecordFailures: [CKError(.batchRequestFailed), limited]) == 29.5)
    #expect(CookbookRetry.delay(forRecordFailures: [limited, CKError(.quotaExceeded)]) == nil)
    #expect(CookbookRetry.delay(forRecordFailures: [CKError(.batchRequestFailed)]) == nil)
  }

  @Test func unchangedPublishLeavesTheProfileAlone() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion, recipe: recipe)
    let hash = try CookbookPayload.contentHash(bundle)
    let profileSaves = ImageLoadCounter()
    let client = CookbookPublishClient(
      fetchRecipeHashes: { [recipe.id.uuidString: hash] },
      saveRecipes: { _, _ in Issue.record("unchanged recipes should not be saved") },
      deleteRecipes: { _ in },
      fetchProfile: { nil },
      saveProfile: { _ in await profileSaves.increment() },
      fetchShare: { nil },
      createOrFetchShare: { _ in CKShare(recordZoneID: CookbookCloudKitClientFactory.zoneID) },
      deleteCookbook: {}
    )
    let current = CookbookPublishProfile(
      displayName: "Jon", recipeCount: 1, payloadVersion: RecipeBundleCoding.currentVersion, publishedAt: now
    )
    let unchanged = try await CookbookPublisher.publish(
      bundles: [bundle], displayName: "Jon", currentProfile: current, client: client, progress: { _, _ in }
    )
    #expect(unchanged == .unchanged)
    #expect(await profileSaves.count == 0)

    let renamed = try await CookbookPublisher.publish(
      bundles: [bundle], displayName: "Jonathan", currentProfile: current, client: client, progress: { _, _ in }
    )
    #expect(renamed == .published)
    #expect(await profileSaves.count == 1)
  }

  @Test func noOpPublishDoesNotLoadDisplayImageBytes() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let recipeID = UUID()
    let photo = RecipePhoto(id: UUID(), recipeID: recipeID, imageDataReference: "cover", sortOrder: 0, dateCreated: now)
    let recipe = Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now, coverPhotoID: photo.id)
    let bundle = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion, recipe: recipe, photos: [photo])
    let hash = try CookbookPayload.contentHash(bundle)
    let imageLoader = ImageLoadCounter()
    let client = CookbookPublishClient(
      fetchRecipeHashes: { [recipe.id.uuidString: hash] },
      saveRecipes: { _, _ in Issue.record("unchanged recipes should not be saved") },
      deleteRecipes: { _ in },
      fetchProfile: { nil },
      saveProfile: { _ in },
      fetchShare: { nil },
      createOrFetchShare: { _ in CKShare(recordZoneID: CookbookCloudKitClientFactory.zoneID) },
      deleteCookbook: {}
    )
    let result = try await CookbookPublisher.publish(
      bundles: [bundle], displayName: "Jon", client: client,
      loadDisplayImages: { _ in await imageLoader.increment(); return [:] },
      progress: { _, _ in }
    )
    #expect(result == .published)
    #expect(await imageLoader.count == 0)
  }
}

private actor CookbookFetchPageStub {
  private var pages: [CookbookFetchedPage]

  init(pages: [CookbookFetchedPage]) { self.pages = pages }

  func next() throws -> CookbookFetchedPage {
    guard !pages.isEmpty else { throw CKError(.internalError) }
    let page = pages.removeFirst()
    return page
  }
}

private actor ImageLoadCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private actor CookbookFetchRequestRecorder {
  private(set) var values: [Data?] = []
  func append(_ value: Data?) { values.append(value) }
}

private actor CookbookFetchProgressRecorder {
  private(set) var values: [CookbookFetchProgress] = []
  func append(_ value: CookbookFetchProgress) { values.append(value) }
  func reset() { values = [] }
}
