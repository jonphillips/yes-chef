import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryItemEditingTests {
    @Test
    func updatesGeneratedItemDisplayFieldsWithoutChangingSourceBreakdown() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_260_000)
      let editedAt = Date(timeIntervalSinceReferenceDate: 805_261_000)
      let recipeID = SampleUUIDSequence.uuid(17_201)
      let sectionID = SampleUUIDSequence.uuid(17_202)
      let milkLineID = SampleUUIDSequence.uuid(17_203)
      var uuids = SampleUUIDSequence(start: 17_300)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Pancakes",
          lines: [
            IngredientLine(
              id: milkLineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "2 cups milk",
              quantity: 2,
              quantityText: "2",
              unit: "cups",
              item: "milk",
              shoppingCategory: "Dairy",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )

        let itemID = try #require(
          try GroceryRepository.addRecipe(
            recipeID: recipeID,
            groceryListID: listID,
            in: db,
            now: now,
            uuid: { uuids.next() }
          )
          .first
        )
        let originalRow = try #require(try GroceryItemListRequest().fetch(db).first { $0.id == itemID })

        try GroceryRepository.updateItem(
          itemID: itemID,
          title: "  Whole milk  ",
          quantityText: " 3 cartons ",
          unit: " cartons ",
          aisle: " Dairy case ",
          notes: " Organic if available ",
          in: db,
          now: editedAt
        )

        let editedRow = try #require(try GroceryItemListRequest().fetch(db).first { $0.id == itemID })
        expectNoDifference(editedRow.item.title, "Whole milk")
        expectNoDifference(editedRow.item.quantity, nil)
        expectNoDifference(editedRow.item.quantityText, "3 cartons")
        expectNoDifference(editedRow.item.unit, "cartons")
        expectNoDifference(editedRow.item.aisle, "Dairy case")
        expectNoDifference(editedRow.item.notes, "Organic if available")
        expectNoDifference(editedRow.item.dateModified, editedAt)
        expectNoDifference(editedRow.sources, originalRow.sources)
      }
    }
  }
}
