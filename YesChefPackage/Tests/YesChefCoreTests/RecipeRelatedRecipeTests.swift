import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeRelatedRecipeTests {
    @Test
    func linkIsSymmetricIdempotentAndDisplaysRelatedRecipesByName() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 902_000_000)
      let firstID = SampleUUIDSequence.uuid(92_001)
      let secondID = SampleUUIDSequence.uuid(92_002)
      let thirdID = SampleUUIDSequence.uuid(92_003)
      var uuids = SampleUUIDSequence(start: 92_100)

      try database.write { db in
        for recipe in [
          Recipe(id: firstID, title: "Zucchini Gratin", dateCreated: now, dateModified: now),
          Recipe(id: secondID, title: "Brussels Sprouts", dateCreated: now, dateModified: now),
          Recipe(id: thirdID, title: "Carrot Salad", dateCreated: now, dateModified: now),
        ] {
          try Recipe.insert { recipe }.execute(db)
        }
        try RecipeRepository.linkRelatedRecipes(
          firstID, secondID, in: db, now: now, uuid: { uuids.next() }
        )
        try RecipeRepository.linkRelatedRecipes(
          thirdID, firstID, in: db, now: now, uuid: { uuids.next() }
        )
        try RecipeRepository.linkRelatedRecipes(
          secondID, firstID, in: db, now: now, uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let first = try #require(try RecipeRepository.fetchDetail(recipeID: firstID, in: db))
        let second = try #require(try RecipeRepository.fetchDetail(recipeID: secondID, in: db))
        expectNoDifference(first.relatedRecipes.map(\.title), ["Brussels Sprouts", "Carrot Salad"])
        expectNoDifference(second.relatedRecipes.map(\.title), ["Zucchini Gratin"])
        expectNoDifference(try RecipeRelatedRecipe.fetchAll(db).count, 2)
      }
    }

    @Test
    func linkConvergesOfflineDuplicatesAndUnlinkRemovesEveryCopy() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 902_100_000)
      let firstID = SampleUUIDSequence.uuid(92_201)
      let secondID = SampleUUIDSequence.uuid(92_202)
      let survivorID = SampleUUIDSequence.uuid(92_210)
      let duplicateID = SampleUUIDSequence.uuid(92_211)

      try database.write { db in
        for recipe in [
          Recipe(id: firstID, title: "First", dateCreated: now, dateModified: now),
          Recipe(id: secondID, title: "Second", dateCreated: now, dateModified: now),
        ] {
          try Recipe.insert { recipe }.execute(db)
        }
        try RecipeRelatedRecipe.insert {
          RecipeRelatedRecipe(
            id: survivorID,
            recipeID: firstID,
            relatedRecipeID: secondID,
            dateCreated: now
          )
        }
        .execute(db)
        try RecipeRelatedRecipe.insert {
          RecipeRelatedRecipe(
            id: duplicateID,
            recipeID: secondID,
            relatedRecipeID: firstID,
            dateCreated: now
          )
        }
        .execute(db)

        try RecipeRepository.linkRelatedRecipes(
          firstID,
          secondID,
          in: db,
          now: now,
          uuid: { SampleUUIDSequence.uuid(92_220) }
        )
        expectNoDifference(try RecipeRelatedRecipe.fetchAll(db).map(\.id), [survivorID])

        try RecipeRepository.unlinkRelatedRecipes(firstID, secondID, in: db)
        expectNoDifference(try RecipeRelatedRecipe.fetchAll(db), [])
      }
    }

    @Test
    func splittingOffAVariationLinksTheNewRecipeToItsFormerBase() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 902_200_000)
      let recipeID = SampleUUIDSequence.uuid(92_301)
      let variationID = SampleUUIDSequence.uuid(92_302)
      var uuids = SampleUUIDSequence(start: 92_400)

      let standaloneID = try database.write { db in
        let base = Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now)
        try Recipe.insert { base }.execute(db)
        let variation = RecipeVariation(
          id: variationID,
          recipeID: recipeID,
          name: "Lime Pasta",
          sortIndex: 0,
          dateCreated: now,
          dateModified: now
        )
        try RecipeVariation.insert { variation }.execute(db)
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        return try RecipeRepository.splitVariationOff(
          variationID,
          resolvedDetail: detail,
          name: variation.name,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let base = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let standalone = try #require(try RecipeRepository.fetchDetail(recipeID: standaloneID, in: db))
        expectNoDifference(base.relatedRecipes.map(\.id), [standaloneID])
        expectNoDifference(standalone.relatedRecipes.map(\.id), [recipeID])
      }
    }
  }
}
