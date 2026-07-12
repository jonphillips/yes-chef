import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryIngredientChoiceTests {
    @Test
    func ingredientChoicesAreScopedAndApplyTheActiveVariation() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_258_000)
      let recipeID = SampleUUIDSequence.uuid(17_501)
      let otherRecipeID = SampleUUIDSequence.uuid(17_502)
      let sectionID = SampleUUIDSequence.uuid(17_503)
      let otherSectionID = SampleUUIDSequence.uuid(17_505)
      let lineID = SampleUUIDSequence.uuid(17_504)
      let otherLineID = SampleUUIDSequence.uuid(17_506)
      var uuids = SampleUUIDSequence(start: 17_600)

      try database.write { db in
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Lime Pasta",
          lines: [
            IngredientLine(
              id: lineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "1 tablespoon lemon juice",
              item: "lemon juice",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: otherRecipeID,
          sectionID: otherSectionID,
          title: "Other Recipe",
          lines: [
            IngredientLine(
              id: otherLineID,
              recipeID: otherRecipeID,
              sectionID: otherSectionID,
              originalText: "1 cup flour",
              item: "flour",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )

        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            summary: "Lime version",
            ingredientOps: [
              .substitute(
                RecipeIngredientReference(id: lineID),
                line: "2 tablespoons lime juice"
              )
            ],
            methodNote: nil
          ),
          recipeID: recipeID,
          name: "Lime",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let choices = try GroceryIngredientChoiceRequest(recipeIDs: [recipeID]).fetch(db)
        expectNoDifference(choices.map(\.recipe.title), ["Lime Pasta"])
        expectNoDifference(choices.map(\.line.originalText), ["2 tablespoons lime juice"])
        expectNoDifference(
          try GroceryIngredientChoiceRequest(recipeIDs: [otherRecipeID]).fetch(db).map(\.line.originalText),
          ["1 cup flour"]
        )
        expectNoDifference(try GroceryIngredientChoiceRequest(recipeIDs: []).fetch(db), [])

        let menuID = try MenuRepository.addMenu(
          title: "Pasta Week",
          notes: nil,
          dayCount: 1,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Shopping note",
          notes: nil,
          dayOffset: 0,
          mealSlot: .lunch,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        expectNoDifference(
          try GroceryMenuRecipeIDsRequest(menuID: menuID).fetch(db),
          [recipeID]
        )
      }
    }
  }
}
