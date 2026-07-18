import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeEnrichmentTests {
    @Test
    func replacingServeWithPlanPreservesUnchangedItemIDs() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 826_000_000)
      let updatedAt = createdAt.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(36_400)
      let unchangedItemID = SampleUUIDSequence.uuid(36_401)
      let removedItemID = SampleUUIDSequence.uuid(36_402)
      let addedItemID = SampleUUIDSequence.uuid(36_403)

      try database.write { db in
        let existingItems = [
          ServeWithItem(id: unchangedItemID, title: "Lime crema", note: "Spoon over each bowl."),
          ServeWithItem(id: removedItemID, title: "Skillet cornbread"),
        ]
        let existingData = try ServeWithCoding.encode(existingItems)
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Chili",
            dateCreated: createdAt,
            dateModified: createdAt,
            serveWith: existingData
          )
        }
        .execute(db)

        try RecipeRepository.replaceServeWithPlan(
          ServeWithPlan(
            items: [
              ServeWithSuggestion(title: "Lime crema", note: "Spoon over each bowl."),
              ServeWithSuggestion(title: "Cabbage slaw"),
            ]
          ),
          recipeID: recipeID,
          in: db,
          now: updatedAt,
          uuid: { addedItemID }
        )
      }

      try database.read { db in
        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(
          ServeWithCoding.decode(recipe.serveWith),
          [
            ServeWithItem(id: unchangedItemID, title: "Lime crema", note: "Spoon over each bowl."),
            ServeWithItem(id: addedItemID, title: "Cabbage slaw"),
          ]
        )
        expectNoDifference(recipe.dateModified, updatedAt)
      }
    }
  }
}
