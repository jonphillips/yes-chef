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
    let plan = try CookbookPublishPlan.make(bundles: [bundle], existingHashes: [:], displayImages: [firstID: Data([1]), coverID: Data([2])])
    #expect(plan.recipesToSave.first?.displayImage == Data([2]))

    let fallbackRecipe = Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now)
    let fallback = RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion, recipe: fallbackRecipe, photos: [cover, first])
    let fallbackPlan = try CookbookPublishPlan.make(bundles: [fallback], existingHashes: [:], displayImages: [firstID: Data([1]), coverID: Data([2])])
    #expect(fallbackPlan.recipesToSave.first?.displayImage == Data([1]))
    let noPhotoBundle = RecipeBundleCoding.RecipeBundle(
      version: RecipeBundleCoding.currentVersion,
      recipe: Recipe(id: UUID(), title: "Plain soup", dateCreated: now, dateModified: now)
    )
    let noPhotoPlan = try CookbookPublishPlan.make(bundles: [noPhotoBundle], existingHashes: [:])
    #expect(noPhotoPlan.recipesToSave.first?.displayImage == nil)
  }
}
