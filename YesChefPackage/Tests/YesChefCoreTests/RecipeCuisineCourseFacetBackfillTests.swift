import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeCuisineCourseFacetBackfillTests {
    @Test
    func matchedCuisineAssignmentClearsSourceColumn() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_001), cuisine: "Thai")

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        let report = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(report.assignedCount, 1)
        expectNoDifference(report.clearedCount, 1)
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
          [thaiCategoryID]
        )
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "")
      }
    }

    @Test
    func normalizesCuisineBeforeMatching() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_002), cuisine: "  thaï ")

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        _ = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
          [thaiCategoryID]
        )
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "")
      }
    }

    @Test
    func unmatchedCuisineDoesNotChangeTaxonomy() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_003), cuisine: "Cajun")

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)
        let categoriesBefore = try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }

        let report = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(report.unmatchedValues, [
          .init(recipeID: recipe.id, field: .cuisine, rawValue: "Cajun")
        ])
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [])
        expectNoDifference(
          try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString },
          categoriesBefore
        )
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "Cajun")
      }
    }

    @Test
    func removedCuisineAssignmentStaysRemovedAfterRerun() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_004), cuisine: "Thai")

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        _ = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        let assignment = try #require(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchOne(db))
        try RecipeCategory.find(assignment.id).delete().execute(db)

        let report = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(report, RecipeCuisineCourseFacetBackfillReport())
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [])
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "")
      }
    }

    @Test
    func assignmentIDIsDeterministicAndSecondRunIsANoop() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: deterministicRecipeID, cuisine: "Thai")

      expectNoDifference(
        DeterministicID.recipeCategory(recipeID: recipe.id, categoryID: thaiCategoryID),
        deterministicThaiAssignmentID
      )

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        _ = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        let first = try #require(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchOne(db))
        expectNoDifference(first.id, deterministicThaiAssignmentID)
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "")

        let second = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(second, RecipeCuisineCourseFacetBackfillReport())
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [first])
      }
    }

    @Test
    func priorCuisineClassificationWinsOverFreeText() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_005), cuisine: "Thai")
      let mexicanAssignment = RecipeCategory(
        id: SampleUUIDSequence.uuid(80_006),
        recipeID: recipe.id,
        categoryID: mexicanCategoryID
      )

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)
        try RecipeCategory.insert { mexicanAssignment }.execute(db)

        let report = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(report.alreadyClassifiedCount, 1)
        expectNoDifference(report.clearedCount, 1)
        expectNoDifference(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db), [mexicanAssignment])
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "")
      }
    }

    @Test
    func matchedCourseAssignmentClearsSourceColumn() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_007), course: "Dinner")

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        let report = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(report.assignedCount, 1)
        expectNoDifference(report.clearedCount, 1)
        expectNoDifference(
          try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID),
          [dinnerCategoryID]
        )
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.course, "")
      }
    }

    @Test
    func cuisineAndCourseResolveIndependentlyWhileRetainingUnmatchedCourse() throws {
      @Dependency(\.defaultDatabase) var database
      let recipe = backfillRecipe(id: SampleUUIDSequence.uuid(80_008), cuisine: "Thai", course: "Cajun")

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        let report = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        expectNoDifference(report.assignedCount, 1)
        expectNoDifference(report.clearedCount, 1)
        expectNoDifference(report.unmatchedValues, [
          .init(recipeID: recipe.id, field: .course, rawValue: "Cajun")
        ])
        expectNoDifference(
          Set(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID)),
          [thaiCategoryID]
        )
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.cuisine, "")
        expectNoDifference(try Recipe.find(recipe.id).fetchOne(db)?.course, "Cajun")
      }
    }

    @Test
    func preservesOriginalSnapshotWhenMovingMatchedCuisine() throws {
      @Dependency(\.defaultDatabase) var database
      let originalSnapshot = Data("{\"cuisine\":\"Thai\"}".utf8)
      let recipe = backfillRecipe(
        id: SampleUUIDSequence.uuid(80_009),
        cuisine: "Thai",
        originalSnapshot: originalSnapshot
      )

      try database.write { db in
        try seedStarterFacets(in: db)
        try Recipe.insert { recipe }.execute(db)

        _ = try RecipeRepository.backfillCuisineCourseFacets(in: db)
        let stored = try #require(try Recipe.find(recipe.id).fetchOne(db))
        expectNoDifference(stored.cuisine, "")
        expectNoDifference(stored.originalSnapshot, originalSnapshot)
      }
    }
  }
}

private let thaiCategoryID = UUID(uuidString: "A4D90002-0000-4000-8000-00000000000B")!
private let mexicanCategoryID = UUID(uuidString: "A4D90002-0000-4000-8000-00000000000A")!
private let dinnerCategoryID = UUID(uuidString: "A4D90002-0000-4000-8000-00000000000F")!
private let deterministicRecipeID = UUID(uuidString: "A4D90002-0000-4000-8000-00000000D001")!
private let deterministicThaiAssignmentID = UUID(uuidString: "CCA00934-D4D8-5B23-B1BB-284E704FBEA1")!

private func backfillRecipe(
  id: Recipe.ID,
  cuisine: String? = nil,
  course: String? = nil,
  originalSnapshot: Data? = nil
) -> Recipe {
  Recipe(
    id: id,
    title: "Backfill \(id.uuidString)",
    cuisine: cuisine,
    course: course,
    dateCreated: .distantPast,
    dateModified: .distantPast,
    originalSnapshot: originalSnapshot
  )
}

private func seedStarterFacets(in db: Database) throws {
  _ = try CategoryRepository.seedStarterFacets(in: db)
}
