import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CategoryRepositoryTests {
    @Test
    func sortsSiblingCategoriesAlphabetically() {
      let now = Date(timeIntervalSinceReferenceDate: 802_700_000)
      let course = Category(
        id: SampleUUIDSequence.uuid(1),
        name: "Course",
        sortOrder: 0,
        dateCreated: now
      )
      let dessert = Category(
        id: SampleUUIDSequence.uuid(2),
        name: "Dessert",
        parentCategoryID: course.id,
        sortOrder: 0,
        dateCreated: now
      )
      let breakfast = Category(
        id: SampleUUIDSequence.uuid(3),
        name: "Breakfast",
        parentCategoryID: course.id,
        sortOrder: 1,
        dateCreated: now
      )
      let cuisine = Category(
        id: SampleUUIDSequence.uuid(4),
        name: "Cuisine",
        sortOrder: 1,
        dateCreated: now
      )

      expectNoDifference(
        CategoryHierarchy.displayRows(from: [course, dessert, breakfast, cuisine]).map(\.displayName),
        [
          "Course",
          "Course > Breakfast",
          "Course > Dessert",
          "Cuisine",
        ]
      )
    }

    @Test
    func starterCategoriesAreStableAndIdempotent() throws {
      @Dependency(\.defaultDatabase) var database

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let afterFirstSeed = try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
        try CategoryRepository.seedStarterCategories(in: db)
        expectNoDifference(
          try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString },
          afterFirstSeed
        )

        let categoriesByID = Dictionary(uniqueKeysWithValues: afterFirstSeed.map { ($0.id, $0) })
        let displayNames = Set(
          afterFirstSeed.map { CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID) }
        )
        let expectedSeedNames: Set<String> = [
          "Cuisine", "Course",
          "Cuisine > American", "Cuisine > Chinese", "Cuisine > French", "Cuisine > Indian",
          "Cuisine > Italian", "Cuisine > Japanese", "Cuisine > Korean", "Cuisine > Mexican",
          "Cuisine > Thai", "Cuisine > Vietnamese",
          "Course > Breakfast", "Course > Lunch", "Course > Dinner", "Course > Appetizer",
          "Course > Side Dish", "Course > Dessert", "Course > Snack", "Course > Drink",
        ]
        #expect(expectedSeedNames.isSubset(of: displayNames))
      }
    }

    @Test
    func latePeerSeedCannotClearStarterDeletionTombstone() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_300_000)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let thai = try #require((try Category.fetchAll(db)).first { $0.name == "Thai" })

        try CategoryRepository.deleteCategory(categoryID: thai.id, in: db, now: deletedAt)
        var latePeerState = try #require(
          (try CategorySeedState.fetchAll(db)).first { $0.categoryID == thai.id }
        )
        latePeerState.isDeleted = false
        latePeerState.dateModified = deletedAt.addingTimeInterval(60)
        try CategorySeedState.upsert { latePeerState }.execute(db)
        try Category.insert {
          Category(
            id: thai.id,
            name: thai.name,
            parentCategoryID: thai.parentCategoryID,
            sortOrder: thai.sortOrder,
            dateCreated: thai.dateCreated
          )
        }
        .execute(db)
        try CategoryRepository.seedStarterCategories(in: db)

        #expect(!(try Category.fetchAll(db)).contains { $0.id == thai.id })
        let tombstone = try #require(
          (try CategorySeedTombstone.fetchAll(db)).first { $0.id == latePeerState.id }
        )
        expectNoDifference(tombstone.dateDeleted, deletedAt)

        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func latePeerReclaimsTombstonedNamespaceLeafFirst() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_325_000)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let cuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let cuisineChildren = try Category.fetchAll(db).filter { $0.parentCategoryID == cuisine.id }
        #expect(cuisineChildren.count == 10)

        // These rows model a late peer: its full seeded namespace is still present when the
        // deletions performed on another device arrive through CloudKit.
        let tombstonedCategoryIDs = [cuisine.id] + cuisineChildren.map(\.id)
        for categoryID in tombstonedCategoryIDs {
          let tombstone = CategorySeedTombstone(id: categoryID, dateDeleted: deletedAt)
          try CategorySeedTombstone.insert { tombstone }.execute(db)
        }

        try CategoryRepository.seedStarterCategories(in: db)

        let remainingCategoryIDs = Set(try Category.fetchAll(db).map(\.id))
        #expect(tombstonedCategoryIDs.allSatisfy { !remainingCategoryIDs.contains($0) })

        for categoryID in tombstonedCategoryIDs {
          try CategorySeedTombstone.find(categoryID).delete().execute(db)
        }
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func laterTombstoneImmediatelyHidesSeedAndNextCategoryWriteReclaimsIt() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_340_000)
      let now = Date(timeIntervalSinceReferenceDate: 802_340_100)
      var uuids = SampleUUIDSequence(start: 750)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let thai = try #require((try Category.fetchAll(db)).first { $0.name == "Thai" })
        let tombstone = CategorySeedTombstone(id: thai.id, dateDeleted: deletedAt)
        try CategorySeedTombstone.insert { tombstone }.execute(db)

        // No bootstrap/reseed is simulated here: this is the same process receiving a later
        // CloudKit tombstone. Reads must hide the stale deterministic row immediately.
        #expect((try Category.fetchAll(db)).contains { $0.id == thai.id })
        #expect(!(try CategoryListRequest().fetch(db)).contains { $0.id == thai.id })

        let transientCategory = try CategoryRepository.createCategory(
          name: "Tombstone Reconciliation Test",
          parentCategoryID: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        #expect(!(try Category.fetchAll(db)).contains { $0.id == thai.id })

        try Category.find(transientCategory.id).delete().execute(db)
        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func partialNamespaceTombstoneHidesDescendantsFromAllRecipeProjections() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_345_000)
      let now = Date(timeIntervalSinceReferenceDate: 802_345_100)
      var uuids = SampleUUIDSequence(start: 760)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let cuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let thai = try #require(
          (try Category.fetchAll(db)).first { $0.name == "Thai" && $0.parentCategoryID == cuisine.id }
        )
        let recipeID = try RecipeRepository.save(
          draft: RecipeEditorDraft(title: "Partial Tombstone Curry", selectedCategoryIDs: [thai.id]),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let recipeCategory = try #require(
          (try RecipeCategory.fetchAll(db)).first { $0.recipeID == recipeID && $0.categoryID == thai.id }
        )
        let tombstone = CategorySeedTombstone(id: cuisine.id, dateDeleted: deletedAt)
        try CategorySeedTombstone.insert { tombstone }.execute(db)

        // CloudKit has delivered the namespace tombstone but none of its child tombstones. The
        // linked Thai row cannot be reclaimed, so every logical reader must still hide it.
        #expect((try Category.fetchAll(db)).contains { $0.id == thai.id })
        #expect(!(try CategoryListRequest().fetch(db)).contains { $0.id == thai.id })
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.categories, [])
        expectNoDifference(detail.categoryDisplayNames, [])
        let row = try #require(try RecipeListRequest().fetch(db).first { $0.recipe.id == recipeID })
        expectNoDifference(row.categoryNames, [])
        expectNoDifference(row.categoryFilterNames, [])

        try RecipeCategory.find(recipeCategory.id).delete().execute(db)
        try Recipe.find(recipeID).delete().execute(db)
        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func movedSeedOutsideTombstonedNamespaceRemainsEffective() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_347_000)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let cuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let thai = try #require(
          (try Category.fetchAll(db)).first { $0.name == "Thai" && $0.parentCategoryID == cuisine.id }
        )
        try CategoryRepository.updateCategory(
          categoryID: thai.id,
          name: thai.name,
          parentCategoryID: nil,
          in: db
        )
        let tombstone = CategorySeedTombstone(id: cuisine.id, dateDeleted: deletedAt)
        try CategorySeedTombstone.insert { tombstone }.execute(db)

        let rows = try CategoryListRequest().fetch(db)
        #expect(rows.contains { $0.id == thai.id && $0.parentCategoryID == nil })

        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        try CategoryRepository.updateCategory(
          categoryID: thai.id,
          name: thai.name,
          parentCategoryID: cuisine.id,
          in: db
        )
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func recipeSaveCreatesFreshCategoryInsteadOfAssigningTombstonedSeed() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_348_000)
      let now = Date(timeIntervalSinceReferenceDate: 802_348_100)
      var uuids = SampleUUIDSequence(start: 770)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let cuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let thai = try #require(
          (try Category.fetchAll(db)).first { $0.name == "Thai" && $0.parentCategoryID == cuisine.id }
        )
        let tombstone = CategorySeedTombstone(id: thai.id, dateDeleted: deletedAt)
        try CategorySeedTombstone.insert { tombstone }.execute(db)

        let recipeID = try RecipeRepository.save(
          draft: RecipeEditorDraft(title: "Imported Thai Curry", categoryNames: "Cuisine > Thai"),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let recipeCategory = try #require(
          (try RecipeCategory.fetchAll(db)).first { $0.recipeID == recipeID }
        )
        #expect(recipeCategory.categoryID != thai.id)
        let freshThai = try #require(
          (try Category.fetchAll(db)).first { $0.id == recipeCategory.categoryID && $0.name == "Thai" }
        )
        #expect(freshThai.id != thai.id)

        try RecipeCategory.find(recipeCategory.id).delete().execute(db)
        try Recipe.find(recipeID).delete().execute(db)
        try Category.find(freshThai.id).delete().execute(db)
        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func unresolvedStarterParentDoesNotCreateChildAtRoot() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_350_000)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let cuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let american = try #require(
          (try Category.fetchAll(db)).first { $0.name == "American" && $0.parentCategoryID == cuisine.id }
        )
        let tombstone = CategorySeedTombstone(id: cuisine.id, dateDeleted: deletedAt)
        try CategorySeedTombstone.insert { tombstone }.execute(db)
        try Category.find(cuisine.id).delete().execute(db)
        try Category.find(american.id).delete().execute(db)

        try CategoryRepository.seedStarterCategories(in: db)

        #expect(!(try Category.fetchAll(db)).contains { $0.name == "American" && $0.parentCategoryID == nil })

        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }

    @Test
    func seedStateStillConvergesConcurrentSameNamedCategory() throws {
      @Dependency(\.defaultDatabase) var database
      let earlier = Date(timeIntervalSinceReferenceDate: -1)
      let peerCategoryID = SampleUUIDSequence.uuid(799)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let cuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let peerCuisine = Category(
          id: peerCategoryID,
          name: "Cuisine",
          sortOrder: 0,
          dateCreated: earlier
        )
        try Category.insert { peerCuisine }.execute(db)
        var seedState = try #require(
          (try CategorySeedState.fetchAll(db)).first { $0.categoryID == cuisine.id }
        )
        seedState.categoryID = peerCuisine.id
        try CategorySeedState.upsert { seedState }.execute(db)

        try CategoryRepository.seedStarterCategories(in: db)

        let cuisineRoots = try Category.fetchAll(db).filter {
          $0.name == "Cuisine" && $0.parentCategoryID == nil
        }
        expectNoDifference(cuisineRoots.map(\.id), [peerCategoryID])
        expectNoDifference(
          try CategorySeedState.fetchAll(db).first { $0.id == seedState.id }?.categoryID,
          peerCategoryID
        )
      }
    }

    @Test
    func renamesMovesAndPreservesRecipeAssignments() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 802_500_000)
      var uuids = SampleUUIDSequence(start: 800)

      try database.write { db in
        let eventType = try CategoryRepository.createCategory(
          name: "Editor Test Event",
          parentCategoryID: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let dinner = try CategoryRepository.createCategory(
          name: "Dinner",
          parentCategoryID: eventType.id,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let occasion = try CategoryRepository.createCategory(
          name: "Editor Test Occasion",
          parentCategoryID: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let recipeID = try RecipeRepository.save(
          draft: RecipeEditorDraft(
            title: "Dinner Party Chicken",
            ingredientText: "1 chicken",
            instructionText: "Roast.",
            selectedCategoryIDs: [dinner.id]
          ),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        try CategoryRepository.updateCategory(
          categoryID: dinner.id,
          name: "Dinner Party",
          parentCategoryID: occasion.id,
          in: db
        )

        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.categories.map(\.id), [dinner.id])
        expectNoDifference(detail.categoryDisplayNames, ["Editor Test Occasion > Dinner Party"])

        let row = try #require(try RecipeListRequest().fetch(db).first { $0.recipe.id == recipeID })
        expectNoDifference(row.categoryNames, ["Editor Test Occasion > Dinner Party"])
        expectNoDifference(
          row.categoryFilterNames,
          ["Editor Test Occasion", "Editor Test Occasion > Dinner Party"]
        )
      }
    }

    @Test
    func rejectsDuplicateSiblingAndUnsafeDelete() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 802_600_000)
      var uuids = SampleUUIDSequence(start: 900)

      try database.write { db in
        let mealType = try CategoryRepository.createCategory(
          name: "Guardrail Test Meal Type",
          parentCategoryID: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let dinner = try CategoryRepository.createCategory(
          name: "Dinner",
          parentCategoryID: mealType.id,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        do {
          _ = try CategoryRepository.createCategory(
            name: "dinner",
            parentCategoryID: mealType.id,
            in: db,
            now: now,
            uuid: { uuids.next() }
          )
          #expect(Bool(false), "Expected duplicate sibling category to be rejected.")
        } catch let error as CategoryRepositoryError {
          expectNoDifference(error, .duplicateSibling(name: "dinner"))
        }

        do {
          try CategoryRepository.deleteCategory(categoryID: mealType.id, in: db, now: now)
          #expect(Bool(false), "Expected deleting a category with children to be rejected.")
        } catch let error as CategoryRepositoryError {
          expectNoDifference(error, .cannotDeleteCategoryWithChildren)
        }

        do {
          try CategoryRepository.updateCategory(
            categoryID: mealType.id,
            name: "Guardrail Test Meal Type",
            parentCategoryID: dinner.id,
            in: db
          )
          #expect(Bool(false), "Expected moving a category under its child to be rejected.")
        } catch let error as CategoryRepositoryError {
          expectNoDifference(error, .cannotParentCategoryUnderDescendant)
        }
      }
    }

    @Test
    func tombstoneSuppressesMappedRepresentativeAndDormantTagSource() throws {
      @Dependency(\.defaultDatabase) var database
      let deletedAt = Date(timeIntervalSinceReferenceDate: 802_650_000)
      let now = Date(timeIntervalSinceReferenceDate: 802_650_100)
      let mappedCategoryID = SampleUUIDSequence.uuid(980)
      var uuids = SampleUUIDSequence(start: 981)

      try database.write { db in
        try CategoryRepository.seedStarterCategories(in: db)
        let seededCuisine = try #require((try Category.fetchAll(db)).first { $0.name == "Cuisine" })
        let seedState = try #require(
          (try CategorySeedState.fetchAll(db)).first { $0.categoryID == seededCuisine.id }
        )
        let mappedCategory = Category(
          id: mappedCategoryID,
          name: "Legacy Cuisine",
          sortOrder: 99,
          dateCreated: now
        )
        try Category.insert { mappedCategory }.execute(db)
        var mappedState = seedState
        mappedState.categoryID = mappedCategory.id
        try CategorySeedState.upsert { mappedState }.execute(db)
        try Tag.insert {
          Tag(
            id: mappedCategory.id,
            name: mappedCategory.name,
            sortOrder: mappedCategory.sortOrder,
            dateCreated: mappedCategory.dateCreated
          )
        }
        .execute(db)

        let existingRecipeID = try RecipeRepository.save(
          draft: RecipeEditorDraft(title: "Mapped Seed Recipe", selectedCategoryIDs: [mappedCategory.id]),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let tombstone = CategorySeedTombstone(id: seedState.id, dateDeleted: deletedAt)
        try CategorySeedTombstone.insert { tombstone }.execute(db)

        // The mapped row is deliberately linked, so reclamation cannot remove it. The tombstone
        // still makes both the seed and its current representative immediately unavailable.
        #expect((try Category.fetchAll(db)).contains { $0.id == mappedCategory.id })
        #expect(!(try CategoryListRequest().fetch(db)).contains { $0.id == mappedCategory.id })
        let existingDetail = try #require(try RecipeRepository.fetchDetail(recipeID: existingRecipeID, in: db))
        expectNoDifference(existingDetail.categories, [])

        let laterRecipeID = try RecipeRepository.save(
          draft: RecipeEditorDraft(title: "Later Mapped Seed Recipe", selectedCategoryIDs: [mappedCategory.id]),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        #expect(!(try RecipeCategory.fetchAll(db)).contains { $0.recipeID == laterRecipeID })

        try CategoryRepository.foldDormantTagsIntoCategories(in: db)
        try CategoryRepository.seedStarterCategories(in: db)
        #expect((try Category.fetchAll(db)).filter { $0.id == mappedCategory.id }.count == 1)
        #expect(!(try CategoryListRequest().fetch(db)).contains { $0.id == mappedCategory.id })

        for recipeCategory in try RecipeCategory.fetchAll(db) where [existingRecipeID, laterRecipeID]
          .contains(recipeCategory.recipeID) {
          try RecipeCategory.find(recipeCategory.id).delete().execute(db)
        }
        try Recipe.find(existingRecipeID).delete().execute(db)
        try Recipe.find(laterRecipeID).delete().execute(db)
        try Tag.find(mappedCategory.id).delete().execute(db)
        try CategorySeedTombstone.find(tombstone.id).delete().execute(db)
        mappedState.categoryID = seededCuisine.id
        try CategorySeedState.upsert { mappedState }.execute(db)
        try Category.find(mappedCategory.id).delete().execute(db)
        try CategoryRepository.seedStarterCategories(in: db)
      }
    }
  }
}
