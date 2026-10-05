import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CategoryRecipeMoveTests {
    @Test
    func retagsRecipesAndSkipsOnesAlreadyTagged() throws {
      @Dependency(\.defaultDatabase) var database
      let first = retagRecipe(82_001)
      let second = retagRecipe(82_002)

      try database.write { db in
        try seedRetagTaxonomy(in: db)
        try Recipe.insert { first; second }.execute(db)
        try retag(first.id, looseSaladID, in: db)
        try retag(second.id, looseSaladID, in: db)
        try retag(second.id, dishTypeSaladID, in: db)

        let report = try CategoryRepository.moveRecipes(
          fromCategoryID: looseSaladID, toCategoryID: dishTypeSaladID, deletingSource: false, in: db
        )

        expectNoDifference(report, CategoryRecipeMoveReport(movedCount: 1, alreadyTaggedCount: 1))
        for recipe in [first, second] {
          expectNoDifference(
            try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
            [dishTypeSaladID]
          )
        }
        expectNoDifference(try YesChefCore.Category.find(looseSaladID).fetchCount(db), 1)
      }
    }

    @Test
    func deletesSourceWhenAsked() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = retagRecipe(82_003)

      try database.write { db in
        try seedRetagTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try retag(recipe.id, looseSaladID, in: db)

        let report = try CategoryRepository.moveRecipes(
          fromCategoryID: looseSaladID, toCategoryID: dishTypeSaladID, deletingSource: true, in: db
        )

        expectNoDifference(report.deletedSource, true)
        expectNoDifference(try YesChefCore.Category.find(looseSaladID).fetchCount(db), 0)
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
          [dishTypeSaladID]
        )
      }
    }

    @Test
    func refusesMovingOntoItself() throws {
      @Dependency(\.defaultDatabase) var database

      try database.write { db in
        try seedRetagTaxonomy(in: db)
        #expect(throws: CategoryRecipeMoveError.sameCategory) {
          try CategoryRepository.moveRecipes(
            fromCategoryID: looseSaladID, toCategoryID: looseSaladID, deletingSource: true, in: db
          )
        }
      }
    }
  }
}

private let dishTypeFacetID = SampleUUIDSequence.uuid(82_501)
private let looseSaladID = SampleUUIDSequence.uuid(82_511)
private let dishTypeSaladID = SampleUUIDSequence.uuid(82_512)

private func retagRecipe(_ id: Int) -> Recipe {
  Recipe(id: SampleUUIDSequence.uuid(id), title: "Retag \(id)", dateCreated: .distantPast, dateModified: .distantPast)
}

private func seedRetagTaxonomy(in db: Database) throws {
  try Facet.insert { Facet(id: dishTypeFacetID, name: "Retag Dish Type", sortOrder: 900, dateCreated: .distantPast) }
    .execute(db)
  try YesChefCore.Category.insert {
    YesChefCore.Category(id: looseSaladID, name: "Salad", sortOrder: 0, dateCreated: .distantPast)
    YesChefCore.Category(
      id: dishTypeSaladID, name: "Salad", facetID: dishTypeFacetID, sortOrder: 0, dateCreated: .distantPast
    )
  }
  .execute(db)
}

private func retag(_ recipeID: Recipe.ID, _ categoryID: YesChefCore.Category.ID, in db: Database) throws {
  try RecipeCategory.insert {
    RecipeCategory(
      id: DeterministicID.recipeCategory(recipeID: recipeID, categoryID: categoryID),
      recipeID: recipeID,
      categoryID: categoryID
    )
  }
  .execute(db)
}
