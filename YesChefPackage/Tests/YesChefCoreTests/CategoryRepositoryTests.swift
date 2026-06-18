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
          try CategoryRepository.deleteCategory(categoryID: mealType.id, in: db)
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
  }
}
