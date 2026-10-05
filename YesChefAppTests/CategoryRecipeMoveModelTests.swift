import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct CategoryRecipeMoveModelTests {
  @Test
  func moveRetagsRecipesDeletesSourceAndReports() async throws {
    let facetID = UUID(uuidString: "00000000-0000-0000-0000-000000008301")!
    let looseSaladID = UUID(uuidString: "00000000-0000-0000-0000-000000008302")!
    let dishTypeSaladID = UUID(uuidString: "00000000-0000-0000-0000-000000008303")!
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000008304")!

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Facet.insert { Facet(id: facetID, name: "Dish Type", sortOrder: 900, dateCreated: .distantPast) }
          .execute(db)
        try YesChefCore.Category.insert {
          YesChefCore.Category(id: looseSaladID, name: "Salad", sortOrder: 0, dateCreated: .distantPast)
          YesChefCore.Category(
            id: dishTypeSaladID, name: "Salad", facetID: facetID, sortOrder: 0, dateCreated: .distantPast
          )
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: recipeID, title: "Caesar", dateCreated: .distantPast, dateModified: .distantPast)
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(
            id: DeterministicID.recipeCategory(recipeID: recipeID, categoryID: looseSaladID),
            recipeID: recipeID,
            categoryID: looseSaladID
          )
        }
        .execute(db)
      }

      let model = CategoryManagementModel()
      try await model.$categories.load()
      try await model.$facets.load()

      model.moveRecipesButtonTapped(categoryID: looseSaladID)
      let move = try #require(model.recipeMove)
      expectNoDifference(move.recipeCount, 1)
      expectNoDifference(move.deletesSource, true)
      expectNoDifference(
        model.recipeMoveTargetSections(excluding: looseSaladID).flatMap(\.options).map(\.title),
        ["Dish Type > Salad"]
      )

      move.targetID = dishTypeSaladID
      #expect(model.confirmRecipeMoveButtonTapped())

      expectNoDifference(model.recipeMove == nil, true)
      expectNoDifference(model.recipeMoveResultMessage, "1 recipe now tagged Dish Type > Salad. Deleted Salad.")
      try await database.read { db in
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db).map(\.categoryID),
          [dishTypeSaladID]
        )
        expectNoDifference(try YesChefCore.Category.find(looseSaladID).fetchCount(db), 0)
      }
    }
  }
}
