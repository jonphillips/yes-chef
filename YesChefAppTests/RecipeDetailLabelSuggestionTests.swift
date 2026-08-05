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
