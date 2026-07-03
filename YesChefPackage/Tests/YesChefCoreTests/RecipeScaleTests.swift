import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeScaleTests {
    @Test
    func persistsScaleIndependentlyPerPlacement() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 812_100_000)
      let recipeID = SampleUUIDSequence.uuid(35_001)
      var uuids = SampleUUIDSequence(start: 35_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Scaled Chicken",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let menuID = try MenuRepository.addMenu(
          title: "Scale Menu",
          notes: nil,
          dayCount: 1,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let menuItemID = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let mealPlanItemID = try MealCalendarRepository.addRecipeItem(
          recipeID: recipeID,
          on: scheduledDate,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        expectNoDifference(try RecipeScaleRepository.scale(for: .recipe(recipeID), in: db), 1.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .menuItem(menuItemID), in: db), 1.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .mealPlanItem(mealPlanItemID), in: db), 1.0)

        try RecipeScaleRepository.setScale(2.0, for: .recipe(recipeID), in: db)
        try RecipeScaleRepository.setScale(3.0, for: .menuItem(menuItemID), in: db)
        try RecipeScaleRepository.setScale(0.5, for: .mealPlanItem(mealPlanItemID), in: db)

        expectNoDifference(try RecipeScaleRepository.scale(for: .recipe(recipeID), in: db), 2.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .menuItem(menuItemID), in: db), 3.0)
        expectNoDifference(try RecipeScaleRepository.scale(for: .mealPlanItem(mealPlanItemID), in: db), 0.5)
      }
    }

    @Test
    func recipeScaleRequestReadsTheContextScale() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 812_200_000)
      let recipeID = SampleUUIDSequence.uuid(35_201)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Request Chicken",
            dateCreated: now,
            dateModified: now,
            viewScale: 1.5
          )
        }
        .execute(db)

        expectNoDifference(try RecipeScaleRequest(context: .recipe(recipeID)).fetch(db), 1.5)
      }
    }
  }
}
