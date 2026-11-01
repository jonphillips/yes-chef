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
    func deletingMergedCategoryRepointsLensQueriesWhenFacetMatches() throws {
      @Dependency(\.defaultDatabase) var database
      let facetID = SampleUUIDSequence.uuid(82_502)
      let sourceID = SampleUUIDSequence.uuid(82_521)
      let targetID = SampleUUIDSequence.uuid(82_522)
      let lensID = SampleUUIDSequence.uuid(82_523)
      let shelfID = SampleUUIDSequence.uuid(82_524)
      let now = Date(timeIntervalSinceReferenceDate: 82_500_000)
      let baseQuery = RecipeBrowserQuery(facetSelections: [
        .init(facetID: facetID, categoryIDs: [sourceID])
      ])
      let shelfQuery = RecipeBrowserQuery(facetSelections: [
        .init(facetID: facetID, categoryIDs: [sourceID])
      ])

      try database.write { db in
        try Facet.insert { Facet(id: facetID, name: "Merge facet", sortOrder: 901, dateCreated: now) }
          .execute(db)
        try YesChefCore.Category.insert {
          YesChefCore.Category(id: sourceID, name: "Source", facetID: facetID, sortOrder: 0, dateCreated: now)
          YesChefCore.Category(id: targetID, name: "Target", facetID: facetID, sortOrder: 1, dateCreated: now)
        }.execute(db)
        let lens = RecipeLens(
          id: lensID, name: "Merge lens", baseQuery: try RecipeLensQueryCodec.encode(baseQuery),
          sortOrder: 0, dateCreated: now, dateModified: now
        )
        let shelf = RecipeLensShelf(
          id: shelfID, lensID: lensID, title: "Merge shelf",
          query: try RecipeLensQueryCodec.encode(shelfQuery), sortOrder: 0
        )
        try RecipeLens.insert { lens }.execute(db)
        try RecipeLensShelf.insert { shelf }.execute(db)

        _ = try CategoryRepository.moveRecipes(
          fromCategoryID: sourceID, toCategoryID: targetID, deletingSource: true, in: db
        )

        let updatedLensRecord = try RecipeLens.find(lensID).fetchOne(db)
        let updatedShelfRecord = try RecipeLensShelf.find(shelfID).fetchOne(db)
        let updatedLens = try #require(updatedLensRecord)
        let updatedShelf = try #require(updatedShelfRecord)
        #expect(try RecipeLensQueryCodec.decode(updatedLens.baseQuery) == RecipeBrowserQuery(
          facetSelections: [.init(facetID: facetID, categoryIDs: [targetID])]
        ))
        // A loose-label query does not use the source's facet namespace and stays unresolved.
        #expect(try RecipeLensQueryCodec.decode(updatedShelf.query) == RecipeBrowserQuery(
          facetSelections: [.init(facetID: facetID, categoryIDs: [targetID])]
        ))
      }
    }

    @Test
    func deletingMergedCategoryLeavesDifferentFacetReferencesUnresolved() throws {
      @Dependency(\.defaultDatabase) var database
      let lensID = SampleUUIDSequence.uuid(82_531)
      let now = Date(timeIntervalSinceReferenceDate: 82_500_000)
      let originalQuery = RecipeBrowserQuery(looseLabelIDs: [looseSaladID])

      try database.write { db in
        try seedRetagTaxonomy(in: db)
        let lens = RecipeLens(
          id: lensID, name: "Unresolved merge", baseQuery: try RecipeLensQueryCodec.encode(originalQuery),
          sortOrder: 0, dateCreated: now, dateModified: now
        )
        try RecipeLens.insert { lens }.execute(db)

        _ = try CategoryRepository.moveRecipes(
          fromCategoryID: looseSaladID, toCategoryID: dishTypeSaladID, deletingSource: true, in: db
        )

        let updatedRecord = try RecipeLens.find(lensID).fetchOne(db)
        let updated = try #require(updatedRecord)
        #expect(try RecipeLensQueryCodec.decode(updated.baseQuery) == originalQuery)
        #expect(try YesChefCore.Category.find(looseSaladID).fetchCount(db) == 0)
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
