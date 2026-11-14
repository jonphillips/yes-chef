import CloudKit
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite(.serialized)
@MainActor
struct CookbookPublishModelTests {
  @Test func sharePublishesAndRefreshesPublishedStatus() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let fake = CookbookPublishFake()
      let model = CookbookPublishModel(client: fake.client())
      model.displayName = "Jon"
      await model.shareMyRecipes()
      #expect(model.hasShare)
      #expect(model.publishedProfile?.displayName == "Jon")
      #expect(model.errorMessage == nil)
      #expect(await fake.profileSaveCount == 1)
    }
  }

  @Test func partialSaveFailureRemainsVisible() async throws {
    let now = Date(timeIntervalSince1970: 500)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      }
      let fake = CookbookPublishFake(saveFailure: "CKError quotaExceeded")
      let model = CookbookPublishModel(client: fake.client())
      model.displayName = "Jon"
      await model.shareMyRecipes()
      #expect(model.errorMessage?.contains("CKError quotaExceeded") == true)
      #expect(model.publishedProfile == nil)
    }
  }

  @Test func launchWithNoCookbookZoneDoesNotPublish() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let fake = CookbookPublishFake(hasShare: false)
      let model = CookbookPublishModel(client: fake.client())
      await model.checkZoneAndPublishIfNeeded()
      #expect(!model.hasShare)
      #expect(await fake.profileSaveCount == 0)
      #expect(await fake.saveCallCount == 0)
    }
  }

  @Test func triggersDuringPublishCauseOneFollowUpRun() async throws {
    let now = Date(timeIntervalSince1970: 700)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      }
      let fake = CookbookPublishFake(holdFirstSave: true)
      let model = CookbookPublishModel(client: fake.client())
      model.displayName = "Jon"
      let firstRun = Task { await model.shareMyRecipes() }
      await fake.waitUntilFirstSaveStarts()
      await model.publishNow()
      await model.publishNow()
      await fake.releaseFirstSave()
      await firstRun.value
      await fake.waitUntilSaveCount(2)
      #expect(await fake.saveCallCount == 2)
    }
  }
}

private actor CookbookPublishFake {
  private(set) var profileSaveCount = 0
  private(set) var saveCallCount = 0
  private var profile: CookbookPublishProfile?
  private var hasShare: Bool
  private let saveFailure: String?
  private var holdFirstSave: Bool
  private var firstSaveContinuation: CheckedContinuation<Void, Never>?
  private var firstSaveStarted: CheckedContinuation<Void, Never>?
  private var saveCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(hasShare: Bool = true, saveFailure: String? = nil, holdFirstSave: Bool = false) {
    self.hasShare = hasShare
    self.saveFailure = saveFailure
    self.holdFirstSave = holdFirstSave
  }

  nonisolated func client() -> CookbookPublishClient {
    CookbookPublishClient(
      fetchRecipeHashes: { [:] },
      saveRecipes: { [weak self] recipes, progress in
        guard let self else { return }
        try await self.save(recipes, progress: progress)
      },
      deleteRecipes: { _ in },
      fetchProfile: { await self.currentProfile() },
      saveProfile: { await self.storeProfile($0) },
      fetchShare: { await self.shareIfAvailable() },
      createOrFetchShare: { [weak self] _ in
        await self?.setHasShare(true)
        return CKShare(recordZoneID: CookbookCloudKitClientFactory.zoneID)
      },
      deleteCookbook: { await self.setHasShare(false) }
    )
  }

  private func save(_ recipes: [CookbookPublishRecipe], progress: @Sendable (Int) -> Void) async throws {
    saveCallCount += 1
    if saveCallCount == 1, holdFirstSave {
      holdFirstSave = false
      firstSaveStarted?.resume()
      firstSaveStarted = nil
      await withCheckedContinuation { firstSaveContinuation = $0 }
    }
    let ready = saveCountWaiters.filter { saveCallCount >= $0.0 }
    saveCountWaiters.removeAll { saveCallCount >= $0.0 }
    ready.forEach { $0.1.resume() }
    if let saveFailure { throw NSError(domain: saveFailure, code: 1) }
    progress(recipes.count)
  }

  private func currentProfile() -> CookbookPublishProfile? { profile }
  private func storeProfile(_ profile: CookbookPublishProfile) { self.profile = profile; profileSaveCount += 1 }
  private func shareIfAvailable() -> CKShare? {
    hasShare ? CKShare(recordZoneID: CookbookCloudKitClientFactory.zoneID) : nil
  }
  private func setHasShare(_ value: Bool) { hasShare = value }

  func waitUntilFirstSaveStarts() async {
    if saveCallCount > 0 { return }
    await withCheckedContinuation { firstSaveStarted = $0 }
  }

  func releaseFirstSave() {
    firstSaveContinuation?.resume()
    firstSaveContinuation = nil
  }

  func waitUntilSaveCount(_ count: Int) async {
    if saveCallCount >= count { return }
    await withCheckedContinuation { saveCountWaiters.append((count, $0)) }
  }
}
