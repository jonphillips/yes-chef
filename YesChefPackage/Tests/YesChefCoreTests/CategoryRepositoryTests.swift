import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

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
        #expect(firstFacets.map(\.name) == ["Cuisine", "Course", "Protein", "Dietary", "Dish Type", "Technique"])
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
            categoryID: cuisineValue.id,
            name: cuisineValue.name,
            facetID: nil,
            parentCategoryID: courseValue.id,
            in: db
          )
        }
        #expect(throws: CategoryRepositoryError.parentFacetMismatch) {
          try CategoryRepository.updateCategory(
            categoryID: cuisineValue.id,
            name: cuisineValue.name,
            facetID: cuisine.id,
            parentCategoryID: courseValue.id,
            in: db
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

        try CategoryRepository.updateCategory(
          categoryID: loose.id,
          name: "Fast",
          facetID: cuisine.id,
          parentCategoryID: parent.id,
          in: db
        )
        expectNoDifference(try Category.find(loose.id).fetchOne(db)?.facetID, cuisine.id)
        expectNoDifference(try Category.find(loose.id).fetchOne(db)?.parentCategoryID, parent.id)
        expectNoDifference(try RecipeCategory.find(join.id).fetchOne(db)?.categoryID, loose.id)
      }
    }

    @Test
    func movingLegacyLooseHierarchyIntoAGroupCascadesToItsDescendants() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_260_000)
      var ids = SampleUUIDSequence(start: 91_500)

      try database.write { db in
        let facet = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        let root = Category(id: ids.next(), name: "Weeknight", sortOrder: 0, dateCreated: now)
        let child = Category(
          id: ids.next(), name: "Fast", parentCategoryID: root.id, sortOrder: 0, dateCreated: now
        )
        try Category.insert { root }.execute(db)
        try Category.insert { child }.execute(db)

        try CategoryRepository.updateCategory(
          categoryID: root.id, name: root.name, facetID: facet.id, parentCategoryID: nil, in: db
        )

        expectNoDifference(try Category.find(root.id).fetchOne(db)?.facetID, facet.id)
        expectNoDifference(try Category.find(child.id).fetchOne(db)?.facetID, facet.id)
      }
    }

    @Test
    func movingAValueToLooseRejectsChildrenButAllowsALeaf() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_270_000)
      var ids = SampleUUIDSequence(start: 91_750)

      try database.write { db in
        let facet = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        let root = try CategoryRepository.createCategory(
          name: "Dinner", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        _ = try CategoryRepository.createCategory(
          name: "Quick", facetID: facet.id, parentCategoryID: root.id, in: db, now: now, uuid: { ids.next() }
        )
        let leaf = try CategoryRepository.createCategory(
          name: "Weeknight", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )

        #expect(throws: CategoryRepositoryError.looseLabelsCannotHaveChildren) {
          try CategoryRepository.updateCategory(
            categoryID: root.id, name: root.name, facetID: nil, parentCategoryID: nil, in: db
          )
        }
        try CategoryRepository.updateCategory(
          categoryID: leaf.id, name: leaf.name, facetID: nil, parentCategoryID: nil, in: db
        )
        expectNoDifference(try Category.find(leaf.id).fetchOne(db)?.facetID, nil)
      }
    }

    @Test
    func movingAGroupValueToAnotherGroupCascadesToItsDescendants() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_280_000)
      var ids = SampleUUIDSequence(start: 92_000)

      try database.write { db in
        let firstFacet = try CategoryRepository.createFacet(
          name: "Cuisine", in: db, now: now, uuid: { ids.next() }
        )
        let secondFacet = try CategoryRepository.createFacet(
          name: "Course", in: db, now: now, uuid: { ids.next() }
        )
        let root = try CategoryRepository.createCategory(
          name: "Regional", facetID: firstFacet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let child = try CategoryRepository.createCategory(
          name: "Italian", facetID: firstFacet.id, parentCategoryID: root.id, in: db, now: now, uuid: { ids.next() }
        )

        try CategoryRepository.updateCategory(
          categoryID: root.id, name: root.name, facetID: secondFacet.id, parentCategoryID: nil, in: db
        )

        expectNoDifference(try Category.find(root.id).fetchOne(db)?.facetID, secondFacet.id)
        expectNoDifference(try Category.find(child.id).fetchOne(db)?.facetID, secondFacet.id)
      }
    }

    @Test
    func movingOntoAnExistingValueMergesIntoThatValue() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_290_000)
      var ids = SampleUUIDSequence(start: 92_250)

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let cuisine = try #require(try Facet.fetchAll(db).first { $0.name == "Cuisine" })
        let existing = try #require(try Category.fetchAll(db).first {
          $0.facetID == cuisine.id && $0.parentCategoryID == nil && $0.name == "Chinese"
        })
        let source = try CategoryRepository.createCategory(
          name: "Chinese", parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let child = Category(
          id: ids.next(), name: "Regional", parentCategoryID: source.id, sortOrder: 0, dateCreated: now
        )
        try Category.insert { child }.execute(db)
        let recipe = Recipe(id: ids.next(), title: "Noodles", dateCreated: now, dateModified: now)
        let assignment = RecipeCategory(id: ids.next(), recipeID: recipe.id, categoryID: source.id)
        try Recipe.insert { recipe }.execute(db)
        try RecipeCategory.insert { assignment }.execute(db)

        try CategoryRepository.updateCategory(
          categoryID: source.id, name: source.name, facetID: cuisine.id, parentCategoryID: nil, in: db
        )

        #expect(try Category.find(source.id).fetchOne(db) == nil)
        #expect(try Category.find(existing.id).fetchOne(db) != nil)
        expectNoDifference(try RecipeCategory.find(assignment.id).fetchOne(db)?.categoryID, existing.id)
        expectNoDifference(try Category.find(child.id).fetchOne(db)?.facetID, cuisine.id)
        expectNoDifference(try Category.find(child.id).fetchOne(db)?.parentCategoryID, existing.id)
      }
    }

    @Test
    func renamingInPlaceOntoAnExistingSiblingStillFails() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_300_000)
      var ids = SampleUUIDSequence(start: 92_500)

      try database.write { db in
        let facet = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        _ = try CategoryRepository.createCategory(
          name: "Dinner", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let lunch = try CategoryRepository.createCategory(
          name: "Lunch", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )

        #expect(throws: CategoryRepositoryError.duplicateSibling(name: "Dinner")) {
          try CategoryRepository.updateCategory(
            categoryID: lunch.id, name: "Dinner", facetID: facet.id, parentCategoryID: nil, in: db
          )
        }
      }
    }

    @Test
    func movingAStarterCategoryIsAllowed() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_310_000)
      var ids = SampleUUIDSequence(start: 92_750)

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let starter = try #require(try Category.fetchAll(db).first { $0.name == "Chinese" })
        let destination = try CategoryRepository.createFacet(
          name: "Regional", in: db, now: now, uuid: { ids.next() }
        )

        try CategoryRepository.updateCategory(
          categoryID: starter.id, name: starter.name, facetID: destination.id, parentCategoryID: nil, in: db
        )

        expectNoDifference(try Category.find(starter.id).fetchOne(db)?.facetID, destination.id)
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
    func hiddenCategoryAssignmentsAreSuppressedFromRecipeReadsAndRestoreWhenUnhidden() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_360_000)
      var ids = SampleUUIDSequence(start: 93_100)

      try database.write { db in
        let cuisine = try CategoryRepository.createFacet(
          name: "Cuisine", in: db, now: now, uuid: { ids.next() }
        )
        let course = try CategoryRepository.createFacet(
          name: "Course", in: db, now: now, uuid: { ids.next() }
        )
        let visibleValue = try CategoryRepository.createCategory(
          name: "Thai", facetID: cuisine.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let hiddenValue = try CategoryRepository.createCategory(
          name: "Korean", facetID: cuisine.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let hiddenFacetValue = try CategoryRepository.createCategory(
          name: "Dinner", facetID: course.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        let recipe = Recipe(id: ids.next(), title: "Hidden Labels", dateCreated: now, dateModified: now)
        try Recipe.insert { recipe }.execute(db)
        for categoryID in [visibleValue.id, hiddenValue.id, hiddenFacetValue.id] {
          try RecipeCategory.insert {
            RecipeCategory(id: ids.next(), recipeID: recipe.id, categoryID: categoryID)
          }
          .execute(db)
        }

        try CategoryRepository.setCategoryHidden(categoryID: hiddenValue.id, hidden: true, in: db)
        try CategoryRepository.setFacetHidden(facetID: course.id, hidden: true, in: db)

        let hiddenListRow = try #require(try RecipeListRequest().fetch(db).first { $0.recipe.id == recipe.id })
        let hiddenDetail = try #require(try RecipeDetailRequest(recipeID: recipe.id).fetch(db))
        expectNoDifference(hiddenListRow.categoryNames, ["Thai"])
        expectNoDifference(hiddenListRow.categoryFilterNames, ["Thai"])
        expectNoDifference(hiddenDetail.categoryDisplayNames, ["Thai"])
        #expect(Set(try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db).map(\.categoryID)) == [
          visibleValue.id, hiddenValue.id, hiddenFacetValue.id,
        ])

        try CategoryRepository.setCategoryHidden(categoryID: hiddenValue.id, hidden: false, in: db)
        try CategoryRepository.setFacetHidden(facetID: course.id, hidden: false, in: db)

        let restoredListRow = try #require(try RecipeListRequest().fetch(db).first { $0.recipe.id == recipe.id })
        let restoredDetail = try #require(try RecipeDetailRequest(recipeID: recipe.id).fetch(db))
        #expect(Set(restoredListRow.categoryNames) == ["Thai", "Korean", "Dinner"])
        #expect(Set(restoredListRow.categoryFilterNames) == ["Thai", "Korean", "Dinner"])
        #expect(Set(restoredDetail.categoryDisplayNames) == ["Thai", "Korean", "Dinner"])
      }
    }

    @Test
    func acceptingAProposedValueUnhidesAnExactHiddenFacetMatch() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_375_000)
      var ids = SampleUUIDSequence(start: 93_500)

      try database.write { db in
        let facet = try CategoryRepository.createFacet(
          name: "Dish Type", in: db, now: now, uuid: { ids.next() }
        )
        let hiddenValue = try CategoryRepository.createCategory(
          name: "Taco", facetID: facet.id, parentCategoryID: nil, in: db, now: now, uuid: { ids.next() }
        )
        try CategoryRepository.setCategoryHidden(categoryID: hiddenValue.id, hidden: true, in: db)
        let recipe = Recipe(id: ids.next(), title: "Fish Tacos", dateCreated: now, dateModified: now)
        try Recipe.insert { recipe }.execute(db)

        try RecipeRepository.reconcileSuggestedLabels(
          [.newChild(.init(facet: facet, parentCategory: nil, name: "Taco"))],
          recipeID: recipe.id,
          in: db,
          now: now,
          uuid: { ids.next() }
        )

        expectNoDifference(try Category.find(hiddenValue.id).fetchOne(db)?.hidden, false)
        expectNoDifference(try RecipeCategory.fetchAll(db).map(\.categoryID), [hiddenValue.id])
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

  @Suite
  struct StarterFacetSeedTests {
    @Test
    func editorialStarterFacetsSeedWithStableIDsAndAreIdempotent() throws {
      @Dependency(\.defaultDatabase) var database
      let expectedFacets: [(ordinal: UInt8, name: String)] = [
        (21, "Protein"), (22, "Dietary"), (23, "Dish Type"), (24, "Technique"),
      ]
      let expectedValues: [(ordinal: UInt8, name: String, facetOrdinal: UInt8)] = [
        (25, "Chicken", 21), (26, "Beef", 21), (27, "Pork", 21), (28, "Lamb", 21),
        (29, "Fish", 21), (30, "Shellfish", 21), (31, "Turkey", 21), (32, "Duck", 21),
        (33, "Sausage", 21), (34, "Eggs", 21), (35, "Tofu", 21), (36, "Beans & Legumes", 21),
        (37, "Vegetarian", 22), (38, "Vegan", 22), (39, "Gluten-Free", 22), (40, "Dairy-Free", 22),
        (41, "Nut-Free", 22), (42, "Low-Carb", 22), (43, "Paleo", 22), (44, "Pescatarian", 22),
        (45, "Soup", 23), (46, "Stew", 23), (47, "Salad", 23), (48, "Sandwich", 23),
        (49, "Pasta", 23), (50, "Pizza", 23), (51, "Taco", 23), (52, "Curry", 23),
        (53, "Casserole", 23), (54, "Bowl", 23), (55, "Bread", 23), (56, "Dumpling", 23),
        (57, "Pie", 23), (58, "Cake", 23), (59, "Cookie", 23),
        (60, "Grill", 24), (61, "Roast", 24), (62, "Braise", 24), (63, "Sear/Sauté", 24),
        (64, "Fry", 24), (65, "Stir-Fry", 24), (66, "Sous Vide", 24), (67, "Slow Cooker", 24),
        (68, "Pressure Cooker", 24), (69, "Air Fryer", 24), (70, "Bake", 24), (71, "Smoke", 24),
        (72, "Steam", 24), (73, "No-Cook", 24),
      ]

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        let firstFacets = try Facet.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        let firstCategories = try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        let secondAudit = try CategoryRepository.seedStarterFacets(in: db)

        for expectedFacet in expectedFacets {
          let facet = try #require(firstFacets.first { $0.id == starterFacetSeedID(expectedFacet.ordinal) })
          #expect(facet.name == expectedFacet.name)
          #expect(CategoryRepository.isStarterFacet(facet.id))
        }
        for expectedValue in expectedValues {
          let category = try #require(firstCategories.first { $0.id == starterFacetSeedID(expectedValue.ordinal) })
          #expect(category.name == expectedValue.name)
          #expect(category.facetID == starterFacetSeedID(expectedValue.facetOrdinal))
        }
        #expect(secondAudit.seededFacetIDs.isEmpty)
        #expect(secondAudit.seededCategoryIDs.isEmpty)
        #expect(try Facet.fetchAll(db).count == firstFacets.count)
        #expect(try Category.fetchAll(db).count == firstCategories.count)
      }
    }

    @Test
    func editorialStarterFacetsAreNonDeletable() throws {
      @Dependency(\.defaultDatabase) var database

      try database.write { db in
        _ = try CategoryRepository.seedStarterFacets(in: db)
        for name in ["Protein", "Dietary", "Dish Type", "Technique"] {
          let facet = try #require(try Facet.fetchAll(db).first { $0.name == name })
          #expect(throws: CategoryRepositoryError.cannotDeleteStarterFacet) {
            try CategoryRepository.deleteFacet(facetID: facet.id, in: db)
          }
        }
      }
    }

    @Test
    func proteinLooseLabelWithNonStarterChildIsNotPromotedByNameFallback() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 816_160_000)
      let proteinID = SampleUUIDSequence.uuid(22)
      let customChildID = SampleUUIDSequence.uuid(23)

      try database.write { db in
        try Category.insert { Category(id: proteinID, name: "Protein", sortOrder: 0, dateCreated: now) }.execute(db)
        try Category.insert {
          Category(id: customChildID, name: "Custom Cut", parentCategoryID: proteinID, sortOrder: 0, dateCreated: now)
        }
        .execute(db)

        let audit = try CategoryRepository.seedStarterFacets(in: db)
        #expect(!audit.fallbackMatchedRootCategoryIDs.contains(proteinID))
        #expect(!audit.promotedRoots.contains(where: { $0.category.id == proteinID }))
        expectNoDifference(try Category.find(proteinID).fetchOne(db)?.facetID, nil)
        expectNoDifference(try Category.find(customChildID).fetchOne(db)?.parentCategoryID, proteinID)
      }
    }
  }
}

private func starterFacetSeedID(_ ordinal: UInt8) -> UUID {
  UUID(uuid: (0xA4, 0xD9, 0x00, 0x02, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, ordinal))
}
