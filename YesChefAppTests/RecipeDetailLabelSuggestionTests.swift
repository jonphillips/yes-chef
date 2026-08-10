import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct RecipeDetailLabelSuggestionTests {
  @Test
  func menuDetailCanReadAnArchivedRecipe() async throws {
    let recipeID = SampleUUIDSequence.uuid(61_000)
    let now = Date(timeIntervalSinceReferenceDate: 840_999_000)

    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Archived Menu Recipe",
            archived: true,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      let libraryModel = RecipeDetailModel(recipeID: recipeID)
      try await libraryModel.$detail.load()
      #expect(libraryModel.detail == nil)

      let menuModel = RecipeDetailModel(recipeID: recipeID, includingArchivedRecipe: true)
      try await menuModel.$detail.load()
      expectNoDifference(menuModel.detail?.recipe.id, recipeID)
    }
  }

  @Test
  func acceptingASuggestionPersistsItImmediately() async throws {
    let recipeID = SampleUUIDSequence.uuid(61_001)
    let categoryID = SampleUUIDSequence.uuid(61_002)
    let now = Date(timeIntervalSinceReferenceDate: 841_000_000)
    let category = Category(id: categoryID, name: "Weeknight", sortOrder: 0, dateCreated: now)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Tomato Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Category.insert { category }.execute(db)
      }

      let model = RecipeDetailModel(recipeID: recipeID)
      let suggestion = SuggestedLabel.existingCategory(category)
      model.labelState.suggestions = [suggestion]

      #expect(await model.acceptSuggestedLabelButtonTapped(suggestion))
      #expect(model.isSuggestedLabelAccepted(suggestion))

      let assignedCategoryIDs = try await database.read { db in
        try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db).map(\.categoryID)
      }
      expectNoDifference(assignedCategoryIDs, [categoryID])
    }
  }
}
