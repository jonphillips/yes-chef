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
        let secondAudit = try CategoryRepository.seedStarterFacets(in: db)
        let firstFacets = try Facet.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        let firstCategories = try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        _ = try CategoryRepository.seedStarterFacets(in: db)
        expectNoDifference(try Facet.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }, firstFacets)
        expectNoDifference(try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }, firstCategories)
        #expect(firstFacets.map(\.name) == ["Cuisine", "Course"])
        #expect(firstCategories.allSatisfy { $0.facetID != nil && $0.parentCategoryID == nil })
        #expect(!secondAudit.requiresReview)
      }
    }

    @Test
    func promotesNamespaceWithoutChangingAChildOrRecipeJoinIdentity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_000_000)
      let cuisineID = try #require(UUID(uuidString: "A4D90002-0000-4000-8000-000000000001"))
      let koreanID = SampleUUIDSequence.uuid(2)
      let thaiID = SampleUUIDSequence.uuid(5)
      let recipeID = SampleUUIDSequence.uuid(3)
      let assignmentID = SampleUUIDSequence.uuid(4)

      try database.write { db in
        try Category.insert { Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: now) }.execute(db)
        try Category.insert {
          Category(id: koreanID, name: "Regional", parentCategoryID: cuisineID, sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Category.insert {
          Category(id: thaiID, name: "Thai", parentCategoryID: koreanID, sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Recipe.insert { Recipe(id: recipeID, title: "Korean Noodles", dateCreated: now, dateModified: now) }
          .execute(db)
        try RecipeCategory.insert { RecipeCategory(id: assignmentID, recipeID: recipeID, categoryID: koreanID) }
          .execute(db)

        let audit = try CategoryRepository.seedStarterFacets(in: db)
        #expect(audit.promotedRoots.count == 1)
        #expect(audit.requiresReview)
        #expect(audit.deletedCategoryIDs.contains(cuisineID))
        #expect(audit.parentChanges == [.init(categoryID: koreanID, fromParentCategoryID: cuisineID, toParentCategoryID: nil)])
        expectNoDifference(try Category.find(koreanID).fetchOne(db)?.facetID, try Facet.fetchAll(db).first?.id)
        expectNoDifference(try Category.find(koreanID).fetchOne(db)?.parentCategoryID, nil)
        expectNoDifference(try Category.find(thaiID).fetchOne(db)?.facetID, try Facet.fetchAll(db).first?.id)
        expectNoDifference(try Category.find(thaiID).fetchOne(db)?.parentCategoryID, koreanID)
        expectNoDifference(try RecipeCategory.find(assignmentID).fetchOne(db)?.categoryID, koreanID)
        #expect(try Category.find(cuisineID).fetchOne(db) == nil)
      }
    }

    @Test
    func remapsDirectNamespaceAssignmentAndReportsIt() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_100_000)
      let cuisineID = try #require(UUID(uuidString: "A4D90002-0000-4000-8000-000000000001"))
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
        #expect(try Category.find(remap.destinationCategoryID).fetchOne(db)?.name == "Legacy Cuisine")
        let secondAudit = try CategoryRepository.seedStarterFacets(in: db)
        #expect(try Category.find(remap.destinationCategoryID).fetchOne(db) != nil)
        #expect(!secondAudit.requiresReview)
      }
    }

    @Test
    func nameFallbackIsAuditedButUserLooseNamespaceIsNotPromoted() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_150_000)
      let fallbackRootID = SampleUUIDSequence.uuid(20)
      let userLooseID = SampleUUIDSequence.uuid(21)
      let legacyValueID = try #require(UUID(uuidString: "A4D90002-0000-4000-8000-000000000004"))

      try database.write { db in
        try Category.insert { Category(id: fallbackRootID, name: "Cuisine", sortOrder: 0, dateCreated: now) }.execute(db)
        try Category.insert {
          Category(id: legacyValueID, name: "Chinese", parentCategoryID: fallbackRootID, sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Category.insert { Category(id: userLooseID, name: "Cuisine", sortOrder: 1, dateCreated: now) }.execute(db)

        let audit = try CategoryRepository.seedStarterFacets(in: db)
        #expect(audit.fallbackMatchedRootCategoryIDs == [fallbackRootID])
        #expect(try Category.find(userLooseID).fetchOne(db) != nil)
      }
    }

    @Test
    func promotionDeduplicatesFlattenedFacetValuesAndRecipeJoins() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_175_000)
      let cuisineID = try #require(UUID(uuidString: "A4D90002-0000-4000-8000-000000000001"))
      let nestedID = SampleUUIDSequence.uuid(30)
      let existingID = SampleUUIDSequence.uuid(31)
      let firstRecipeID = SampleUUIDSequence.uuid(32)
      let secondRecipeID = SampleUUIDSequence.uuid(33)

      try database.write { db in
        try Category.insert { Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: now) }.execute(db)
        try Category.insert {
          Category(id: nestedID, name: "Regional", parentCategoryID: cuisineID, sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Category.insert {
          Category(id: existingID, name: "Regional", facetID: cuisineID, sortOrder: 1, dateCreated: now)
        }
        .execute(db)
        for recipeID in [firstRecipeID, secondRecipeID] {
          try Recipe.insert { Recipe(id: recipeID, title: recipeID.uuidString, dateCreated: now, dateModified: now) }
            .execute(db)
        }
        try RecipeCategory.insert { RecipeCategory(id: SampleUUIDSequence.uuid(34), recipeID: firstRecipeID, categoryID: nestedID) }
          .execute(db)
        try RecipeCategory.insert { RecipeCategory(id: SampleUUIDSequence.uuid(35), recipeID: secondRecipeID, categoryID: existingID) }
          .execute(db)

        let audit = try CategoryRepository.seedStarterFacets(in: db)
        let regional = try Category.fetchAll(db).filter { $0.facetID == cuisineID && $0.name == "Regional" }
        #expect(regional.count == 1)
        let canonical = try #require(regional.first)
        #expect(audit.categoryMerges.count == 1)
        #expect(audit.deletedCategoryIDs.contains(nestedID) || audit.deletedCategoryIDs.contains(existingID))
        let joinedCategoryIDs = Set(try RecipeCategory.fetchAll(db).map(\.categoryID))
        #expect(joinedCategoryIDs.contains(canonical.id))
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

    @Test
    func movingLooseCategoryUnderFacetWritesFacetAndPreservesRecipeAssignment() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_250_000)
      var ids = SampleUUIDSequence(start: 91_000)

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let cuisine = try #require(try Facet.fetchAll(db).first { $0.name == "Cuisine" })
        let parent = try CategoryRepository.createCategory(
          name: "Regional", facetID: cuisine.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let loose = try CategoryRepository.createCategory(
          name: "Weeknight", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let recipe = Recipe(id: ids.next(), title: "Noodles", dateCreated: now, dateModified: now)
        try Recipe.insert { recipe }.execute(db)
        let join = RecipeCategory(id: ids.next(), recipeID: recipe.id, categoryID: loose.id)
        try RecipeCategory.insert { join }.execute(db)

        try CategoryRepository.updateCategory(categoryID: loose.id, name: "Fast", parentCategoryID: parent.id, in: db)
        expectNoDifference(try Category.find(loose.id).fetchOne(db)?.facetID, cuisine.id)
        expectNoDifference(try Category.find(loose.id).fetchOne(db)?.parentCategoryID, parent.id)
        expectNoDifference(try RecipeCategory.find(join.id).fetchOne(db)?.categoryID, loose.id)
      }
    }

    @Test
    func sortingDuplicatesAndUnsafeDeletesRemainGuarded() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_300_000)
      var ids = SampleUUIDSequence(start: 92_000)

      try database.write { db in
        _ = try CategoryRepository.createCategory(
          name: "Zebra", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let apple = try CategoryRepository.createCategory(
          name: "Apple", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        #expect(CategoryRepository.sortedCategories(try Category.fetchAll(db)).map(\.name) == ["Apple", "Zebra"])
        #expect(throws: CategoryRepositoryError.duplicateSibling(name: "apple")) {
          _ = try CategoryRepository.createCategory(
            name: "apple", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
          )
        }
        let recipe = Recipe(id: ids.next(), title: "Apple Pie", dateCreated: now, dateModified: now)
        try Recipe.insert { recipe }.execute(db)
        try RecipeCategory.insert { RecipeCategory(id: ids.next(), recipeID: recipe.id, categoryID: apple.id) }.execute(db)
        #expect(throws: CategoryRepositoryError.cannotDeleteCategoryUsedByRecipes) {
          try CategoryRepository.deleteCategory(categoryID: apple.id, in: db)
        }
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let cuisine = try #require(try Facet.fetchAll(db).first { $0.name == "Cuisine" })
        let parent = try CategoryRepository.createCategory(
          name: "Parent", facetID: cuisine.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        _ = try CategoryRepository.createCategory(
          name: "Child", parentCategoryID: parent.id, in: db, now: now, uuid: { ids.next() }
        )
        #expect(throws: CategoryRepositoryError.cannotDeleteCategoryWithChildren) {
          try CategoryRepository.deleteCategory(categoryID: parent.id, in: db)
        }
      }
    }

    @Test
    func categoryGroupsCanBeCreatedRenamedAndHiddenWithoutChangingTheirValues() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_350_000)
      var ids = SampleUUIDSequence(start: 93_000)

      try database.write { db in
        let facet = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        let value = try CategoryRepository.createCategory(
          name: "Taco", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )

        try CategoryRepository.setFacetHidden(facetID: facet.id, hidden: true, in: db)
        #expect(try CategoryListRequest().fetch(db).isEmpty)
        try CategoryRepository.setFacetHidden(facetID: facet.id, hidden: false, in: db)
        try CategoryRepository.setCategoryHidden(categoryID: value.id, hidden: true, in: db)

        try CategoryRepository.renameFacet(facetID: facet.id, name: "Format", in: db)

        expectNoDifference(try Facet.find(facet.id).fetchOne(db)?.name, "Format")
        expectNoDifference(try Facet.find(facet.id).fetchOne(db)?.hidden, false)
        expectNoDifference(try Category.find(value.id).fetchOne(db)?.facetID, facet.id)
        expectNoDifference(try Category.find(value.id).fetchOne(db)?.hidden, true)
        expectNoDifference(try FacetListRequest().fetch(db).map(\.id), [facet.id])
        expectNoDifference(try FacetManagementListRequest().fetch(db).map(\.id), [facet.id])
      }
    }

    @Test
    func categoryGroupsRejectDuplicateNames() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_400_000)
      var ids = SampleUUIDSequence(start: 94_000)

      try database.write { db in
        _ = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        #expect(throws: CategoryRepositoryError.duplicateFacetName(name: "dish type")) {
          _ = try CategoryRepository.createFacet(
            name: "dish type", in: db, now: now, uuid: { ids.next() }
          )
        }
      }
    }

    @Test
    func categoryNamesAreUniqueWithinTheirFacetAndParentOnly() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_450_000)
      var ids = SampleUUIDSequence(start: 95_000)

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let facets = try Facet.fetchAll(db)
        let cuisine = try #require(facets.first { $0.name == "Cuisine" })
        let mealType = try CategoryRepository.createFacet(
          name: "Meal Type", in: db, now: now, uuid: { ids.next() }
        )

        let looseItalian = try CategoryRepository.createCategory(
          name: "Italian", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let cuisineDinner = try CategoryRepository.createCategory(
          name: "Dinner", facetID: cuisine.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let mealTypeDinner = try CategoryRepository.createCategory(
          name: "Dinner", facetID: mealType.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )

        expectNoDifference(looseItalian.facetID, nil)
        expectNoDifference(cuisineDinner.facetID, cuisine.id)
        expectNoDifference(mealTypeDinner.facetID, mealType.id)
      }
    }

    @Test
    func userCategoryGroupsCanBeDeletedOnlyAfterTheirValuesAreRemoved() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_500_000)
      var ids = SampleUUIDSequence(start: 96_000)

      try database.write { db in
        let facet = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        let value = try CategoryRepository.createCategory(
          name: "Taco", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )

        #expect(throws: CategoryRepositoryError.cannotDeleteFacetWithCategories) {
          try CategoryRepository.deleteFacet(facetID: facet.id, in: db)
        }
        try CategoryRepository.deleteCategory(categoryID: value.id, in: db)
        try CategoryRepository.deleteFacet(facetID: facet.id, in: db)
        #expect(try Facet.find(facet.id).fetchOne(db) == nil)

        _ = try CategoryRepository.seedStarterFacets(in: db)
        let cuisine = try #require(try Facet.fetchAll(db).first { $0.name == "Cuisine" })
        #expect(throws: CategoryRepositoryError.cannotDeleteStarterFacet) {
          try CategoryRepository.deleteFacet(facetID: cuisine.id, in: db)
        }
      }
    }
  }
}
