import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct CategorySourceMoveModelTests {
  @Test
  func previewThenApplyRoutesBookAndKnownPublication() throws {
    let facetID = UUID(uuidString: "00000000-0000-0000-0000-000000008201")!
    let categoryID = UUID(uuidString: "00000000-0000-0000-0000-000000008202")!
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000008203")!
    let milkStreetID = UUID(uuidString: "00000000-0000-0000-0000-000000008204")!

    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try Facet.insert { Facet(id: facetID, name: "Cookbook", sortOrder: 900, dateCreated: .distantPast) }
          .execute(db)
        try YesChefCore.Category.insert {
          YesChefCore.Category(
            id: categoryID, name: "Zuni Cafe Cookbook", facetID: facetID, sortOrder: 0, dateCreated: .distantPast
          )
          YesChefCore.Category(
            id: milkStreetID, name: "Milk Street", facetID: facetID, sortOrder: 1, dateCreated: .distantPast
          )
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: recipeID, title: "Roast Chicken", dateCreated: .distantPast, dateModified: .distantPast)
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(
            id: DeterministicID.recipeCategory(recipeID: recipeID, categoryID: categoryID),
            recipeID: recipeID,
            categoryID: categoryID
          )
          RecipeCategory(
            id: DeterministicID.recipeCategory(recipeID: recipeID, categoryID: milkStreetID),
            recipeID: recipeID,
            categoryID: milkStreetID
          )
        }
        .execute(db)
      }

      let model = CategorySourceMoveModel()
      model.task()
      expectNoDifference(model.report?.moveCount, 2)
      expectNoDifference(model.publicationNames, ["Milk Street"])
      expectNoDifference(model.hasApplied, false)

      model.applyButtonTapped()
      model.confirmApplyButtonTapped()

      expectNoDifference(model.hasApplied, true)
      expectNoDifference(model.errorMessage, nil)
      let source = try database.read { db in
        try RecipeSource.where { $0.recipeID.eq(recipeID) }.fetchOne(db)
      }
      expectNoDifference(source?.bookTitle, "Zuni Cafe Cookbook")
      expectNoDifference(source?.publicationName, "Milk Street")
      expectNoDifference(
        try database.read { db in try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchCount(db) },
        0
      )
    }
  }
}
