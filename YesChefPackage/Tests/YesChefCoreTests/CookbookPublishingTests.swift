import CloudKit
import Foundation
import Testing
import YesChefCore

struct CookbookPublishingTests {
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

private actor ImageLoadCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}
