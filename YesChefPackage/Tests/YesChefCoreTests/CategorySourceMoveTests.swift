import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CategorySourceMoveTests {
    @Test
    func movesIntoEmptyFieldsWithOneNewSourceAndRemovesOnlyThoseTags() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_001)
      var uuids = SampleUUIDSequence(start: 81_900)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try tag(recipe.id, zuniID, in: db)
        try tag(recipe.id, rodgersID, in: db)
        try tag(recipe.id, looseID, in: db)

        let report = try RecipeRepository.applyCategorySourceMove(publicationNames: [], in: db, uuid: { uuids.next() })

        expectNoDifference(report.moveCount, 2)
        expectNoDifference(report.problems, [])
        let sources = try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchAll(db)
        expectNoDifference(sources.map(\.bookTitle), ["Zuni Cafe Cookbook"])
        expectNoDifference(sources.map(\.author), ["Judy Rodgers"])
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
          [looseID]
        )
      }
    }

    @Test
    func preservesExistingSourceRecordAndOtherFields() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_002)
      let source = RecipeSource(
        id: SampleUUIDSequence.uuid(81_102),
        recipeID: recipe.id,
        name: "Zuni",
        url: "https://example.com",
        pageNumber: "212"
      )

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try RecipeSource.insert { source }.execute(db)
        try tag(recipe.id, zuniID, in: db)

        _ = try RecipeRepository.applyCategorySourceMove(publicationNames: [], in: db, uuid: { Issue.record("new source"); return UUID() })

        var expected = source
        expected.bookTitle = "Zuni Cafe Cookbook"
        expectNoDifference(try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [expected])
      }
    }

    @Test
    func differentExistingValueIsReportedAndLeavesTagAndField() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_003)
      let source = RecipeSource(id: SampleUUIDSequence.uuid(81_103), recipeID: recipe.id, author: "Someone Else")

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try RecipeSource.insert { source }.execute(db)
        try tag(recipe.id, rodgersID, in: db)

        let report = try RecipeRepository.applyCategorySourceMove(publicationNames: [], in: db, uuid: { UUID() })

        expectNoDifference(report.problems.map(\.outcome), [.fieldHasDifferentValue(existing: "Someone Else")])
        expectNoDifference(try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [source])
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
          [rodgersID]
        )
      }
    }

    @Test
    func matchingExistingValueOnlyRemovesTag() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_004)
      let source = RecipeSource(id: SampleUUIDSequence.uuid(81_104), recipeID: recipe.id, author: " judy rodgers ")

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try RecipeSource.insert { source }.execute(db)
        try tag(recipe.id, rodgersID, in: db)

        let report = try RecipeRepository.applyCategorySourceMove(publicationNames: [], in: db, uuid: { UUID() })

        expectNoDifference(report.alreadySetCount, 1)
        expectNoDifference(try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [source])
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [])
      }
    }

    @Test
    func multipleCategoriesInGroupAreReportedAndKept() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_005)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try tag(recipe.id, zuniID, in: db)
        try tag(recipe.id, chezPanisseID, in: db)

        let report = try RecipeRepository.applyCategorySourceMove(publicationNames: [], in: db, uuid: { UUID() })

        expectNoDifference(report.problems.map(\.outcome), [.multipleValues])
        expectNoDifference(try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [])
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchCount(db), 2)
      }
    }

    @Test
    func planDoesNotWrite() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_006)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try tag(recipe.id, zuniID, in: db)

        let report = try RecipeRepository.planCategorySourceMove(publicationNames: [], in: db)

        expectNoDifference(report.moveCount, 1)
        expectNoDifference(try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [])
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchCount(db), 1)
      }
    }

    @Test
    func publicationValuesMoveToPublicationAlongsideABook() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_007)
      var uuids = SampleUUIDSequence(start: 81_950)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try tag(recipe.id, zuniID, in: db)
        try tag(recipe.id, milkStreetID, in: db)

        let report = try RecipeRepository.applyCategorySourceMove(
          publicationNames: ["milk street"], in: db, uuid: { uuids.next() }
        )

        expectNoDifference(report.moveCount, 2)
        expectNoDifference(report.cookbookValues, ["Milk Street", "Zuni Cafe Cookbook"])
        let source = try #require(try RecipeSource.where { $0.recipeID.eq(recipe.id) }.fetchOne(db))
        expectNoDifference(source.publicationName, "Milk Street")
        expectNoDifference(source.bookTitle, "Zuni Cafe Cookbook")
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchCount(db), 0)
      }
    }

    @Test
    func publicationNotChosenGoesToBookTitle() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_008)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try tag(recipe.id, milkStreetID, in: db)

        let report = try RecipeRepository.planCategorySourceMove(publicationNames: [], in: db)
        expectNoDifference(report.entries.map(\.field), [.bookTitle])
      }
    }

    @Test
    func knownPublicationsMatchIgnoringPunctuation() {
      #expect(CategorySourceMoveReport.isKnownPublication("Cooks Illustrated"))
      #expect(CategorySourceMoveReport.isKnownPublication(" new york times "))
      #expect(!CategorySourceMoveReport.isKnownPublication("Milk Street Tuesday Nights"))
    }

    @Test
    func reportsMissingGroups() throws {
      @Dependency(\.defaultDatabase) var database

      try database.write { db in
        let report = try RecipeRepository.planCategorySourceMove(publicationNames: [], in: db)
        expectNoDifference(report.missingGroups, [.cookbook, .chef])
      }
    }
  }
}

private let cookbookFacetID = SampleUUIDSequence.uuid(81_501)
private let chefFacetID = SampleUUIDSequence.uuid(81_502)
private let zuniID = SampleUUIDSequence.uuid(81_511)
private let chezPanisseID = SampleUUIDSequence.uuid(81_512)
private let rodgersID = SampleUUIDSequence.uuid(81_521)
private let looseID = SampleUUIDSequence.uuid(81_531)
private let milkStreetID = SampleUUIDSequence.uuid(81_513)

private func moveRecipe(_ id: Int) -> Recipe {
  Recipe(
    id: SampleUUIDSequence.uuid(id),
    title: "Move \(id)",
    dateCreated: .distantPast,
    dateModified: .distantPast
  )
}

private func seedMoveTaxonomy(in db: Database) throws {
  try Facet.insert {
    Facet(id: cookbookFacetID, name: "Cookbook", sortOrder: 900, dateCreated: .distantPast)
    Facet(id: chefFacetID, name: "Chef", sortOrder: 901, dateCreated: .distantPast)
  }
  .execute(db)
  try YesChefCore.Category.insert {
    YesChefCore.Category(id: zuniID, name: "Zuni Cafe Cookbook", facetID: cookbookFacetID, sortOrder: 0, dateCreated: .distantPast)
    YesChefCore.Category(id: chezPanisseID, name: "Chez Panisse", facetID: cookbookFacetID, sortOrder: 1, dateCreated: .distantPast)
    YesChefCore.Category(id: milkStreetID, name: "Milk Street", facetID: cookbookFacetID, sortOrder: 2, dateCreated: .distantPast)
    YesChefCore.Category(id: rodgersID, name: "Judy Rodgers", facetID: chefFacetID, sortOrder: 0, dateCreated: .distantPast)
    YesChefCore.Category(id: looseID, name: "Weeknight", sortOrder: 0, dateCreated: .distantPast)
  }
  .execute(db)
}

private func tag(_ recipeID: Recipe.ID, _ categoryID: YesChefCore.Category.ID, in db: Database) throws {
  try RecipeCategory.insert {
    RecipeCategory(
      id: DeterministicID.recipeCategory(recipeID: recipeID, categoryID: categoryID),
      recipeID: recipeID,
      categoryID: categoryID
    )
  }
  .execute(db)
}

extension RecipeCoreTests {
  @Suite
  struct CategorySourceGroupCleanupTests {
    @Test
    func deletesUnusedCategoriesAndEmptyGroupsButKeepsTaggedOnes() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = moveRecipe(81_101)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try Recipe.insert { recipe }.execute(db)
        try tag(recipe.id, zuniID, in: db)
        try tag(recipe.id, looseID, in: db)

        let report = try RecipeRepository.deleteUnusedCategorySourceGroups(in: db)

        expectNoDifference(report.deletedGroups, [.chef])
        expectNoDifference(report.deletedCategoryCount, 3)
        expectNoDifference(report.remaining, [.init(group: .cookbook, categoryName: "Zuni Cafe Cookbook", recipeCount: 1)])
        expectNoDifference(try Facet.find(chefFacetID).fetchOne(db), nil)
        expectNoDifference(try Facet.find(cookbookFacetID).fetchCount(db), 1)
        expectNoDifference(try YesChefCore.Category.find(looseID).fetchCount(db), 1)
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchCount(db), 2)
      }
    }

    @Test
    func deletesEmptiedParentAfterItsChild() throws {
      @Dependency(\.defaultDatabase) var database
      let childID = SampleUUIDSequence.uuid(81_514)

      try database.write { db in
        try seedMoveTaxonomy(in: db)
        try YesChefCore.Category.insert {
          YesChefCore.Category(
            id: childID, name: "Zuni Desserts", facetID: cookbookFacetID, parentCategoryID: zuniID,
            sortOrder: 3, dateCreated: .distantPast
          )
        }
        .execute(db)

        let report = try RecipeRepository.deleteUnusedCategorySourceGroups(in: db)

        expectNoDifference(report.deletedGroups, [.cookbook, .chef])
        expectNoDifference(report.remaining, [])
      }
    }
  }
}
