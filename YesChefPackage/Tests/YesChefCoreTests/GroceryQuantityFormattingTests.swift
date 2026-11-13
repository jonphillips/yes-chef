import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryQuantityFormattingTests {
    @Test
    func formatsFractionsAndRoundsOtherValuesUpToAnEighth() {
      expectNoDifference(
        [1.08333, 0.4375, 1.0 / 3.0, 2.0 / 3.0, 1.5, 3.0].map(formatGroceryQuantity),
        ["1 ⅛", "½", "⅓", "⅔", "1 ½", "3"]
      )
    }

    @Test
    func consolidationStoresRoundedTextAndExactSummedQuantity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_060_000)

      let merged = try database.write { db -> GroceryItem in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { SampleUUIDSequence.uuid(90_600) })
        for (index, quantity) in [1.0 / 4.0, 1.0 / 2.0, 1.0 / 3.0].enumerated() {
          try GroceryItem.insert {
            GroceryItem(
              id: SampleUUIDSequence.uuid(90_601 + index),
              groceryListID: listID,
              title: "flour",
              canonicalName: "flour",
              quantity: quantity,
              quantityText: IngredientScaler.formattedQuantity(quantity),
              unit: "cup",
              sortOrder: index,
              dateCreated: now,
              dateModified: now
            )
          }.execute(db)
        }
        _ = try GroceryRepository.consolidate(listID: listID, in: db, now: now)
        return try #require(GroceryItem.fetchAll(db).first { $0.groceryListID == listID })
      }

      #expect(abs((merged.quantity ?? 0) - (13.0 / 12.0)) < 0.000_001)
      expectNoDifference(merged.quantityText, "1 ⅛")
    }
  }
}
