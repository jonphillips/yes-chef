import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CategoryRepositoryTests {
    @Test
    func starterFacetsAreStableAndIdempotent() throws {
      @Dependency(\.defaultDatabase) var database

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let firstFacets = try Facet.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        let firstCategories = try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        _ = try CategoryRepository.seedStarterFacets(in: db)
        expectNoDifference(try Facet.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }, firstFacets)
        expectNoDifference(try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }, firstCategories)
        #expect(firstFacets.map(\.name) == ["Cuisine", "Course"])
        #expect(firstCategories.allSatisfy { $0.facetID != nil && $0.parentCategoryID == nil })
      }
    }

    @Test
    func promotesNamespaceWithoutChangingAChildOrRecipeJoinIdentity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_000_000)
      let cuisineID = SampleUUIDSequence.uuid(1)
      let koreanID = SampleUUIDSequence.uuid(2)
      let recipeID = SampleUUIDSequence.uuid(3)
      let assignmentID = SampleUUIDSequence.uuid(4)

      try database.write { db in
        try Category.insert { Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: now) }.execute(db)
        try Category.insert {
          Category(id: koreanID, name: "Korean", parentCategoryID: cuisineID, sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Recipe.insert { Recipe(id: recipeID, title: "Korean Noodles", dateCreated: now, dateModified: now) }
          .execute(db)
        try RecipeCategory.insert { RecipeCategory(id: assignmentID, recipeID: recipeID, categoryID: koreanID) }
          .execute(db)

        let audit = try CategoryRepository.seedStarterFacets(in: db)
        #expect(audit.promotedRoots.count == 1)
        expectNoDifference(try Category.find(koreanID).fetchOne(db)?.facetID, try Facet.fetchAll(db).first?.id)
        expectNoDifference(try Category.find(koreanID).fetchOne(db)?.parentCategoryID, nil)
        expectNoDifference(try RecipeCategory.find(assignmentID).fetchOne(db)?.categoryID, koreanID)
        #expect(try Category.find(cuisineID).fetchOne(db) == nil)
      }
    }

    @Test
    func remapsDirectNamespaceAssignmentAndReportsIt() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_100_000)
      let cuisineID = SampleUUIDSequence.uuid(11)
      let recipeID = SampleUUIDSequence.uuid(12)

      try database.write { db in
        try Category.insert { Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: now) }.execute(db)
        try Recipe.insert { Recipe(id: recipeID, title: "Unfiled", dateCreated: now, dateModified: now) }.execute(db)
        try RecipeCategory.insert {
          RecipeCategory(id: SampleUUIDSequence.uuid(13), recipeID: recipeID, categoryID: cuisineID)
        }
        .execute(db)

        let audit = try CategoryRepository.seedStarterFacets(in: db)
        let remap = try #require(audit.remappedRootAssignments.first)
        #expect(remap.rootCategoryID == cuisineID)
        #expect(remap.recipeCount == 1)
        #expect(try Category.find(remap.destinationCategoryID).fetchOne(db)?.facetID == nil)
      }
    }

    @Test
    func rejectsLooseParentsAndCrossFacetMoves() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_200_000)
      var ids = SampleUUIDSequence(start: 90_000)

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let loose = try CategoryRepository.createCategory(
          name: "Weeknight", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        #expect(throws: CategoryRepositoryError.looseLabelsCannotHaveChildren) {
          _ = try CategoryRepository.createCategory(
            name: "Quick", parentCategoryID: loose.id, in: db, now: now, uuid: { ids.next() }
          )
        }
        let facets = try Facet.fetchAll(db)
        let cuisine = try #require(facets.first { $0.name == "Cuisine" })
        let course = try #require(facets.first { $0.name == "Course" })
        let cuisineValue = try CategoryRepository.createCategory(
          name: "Test Cuisine", facetID: cuisine.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let courseValue = try CategoryRepository.createCategory(
          name: "Test Course", facetID: course.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        #expect(throws: CategoryRepositoryError.parentFacetMismatch) {
          try CategoryRepository.updateCategory(
            categoryID: cuisineValue.id, name: cuisineValue.name, parentCategoryID: courseValue.id, in: db
          )
        }
      }
    }
  }
}
