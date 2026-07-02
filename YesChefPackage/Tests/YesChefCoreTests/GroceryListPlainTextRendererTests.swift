import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryListPlainTextRendererTests {
    @Test
    func rendersCurrentGroupingAndOrder() {
      let now = Date(timeIntervalSinceReferenceDate: 805_050_000)
      let listID = SampleUUIDSequence.uuid(13_150)
      let list = GroceryList(
        id: listID,
        title: "Saturday Market",
        sortOrder: 0,
        dateCreated: now,
        dateModified: now
      )
      let rows = [
        GroceryItemRowData(
          item: GroceryItem(
            id: SampleUUIDSequence.uuid(13_151),
            groceryListID: listID,
            title: "apples",
            quantityText: "6",
            aisle: "Produce",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        ),
        GroceryItemRowData(
          item: GroceryItem(
            id: SampleUUIDSequence.uuid(13_152),
            groceryListID: listID,
            title: "milk",
            quantityText: "2",
            unit: "cartons",
            notes: "whole",
            isPurchased: true,
            purchasedAt: now,
            sortOrder: 1,
            dateCreated: now,
            dateModified: now
          )
        ),
      ]

      expectNoDifference(
        GroceryListPlainTextRenderer.render(list: list, rows: rows),
        """
        Saturday Market

        To Buy
        - 6 apples (Produce)

        Purchased
        - 2 cartons milk (whole)
        """
      )
    }

    @Test
    func rendersEmptyList() {
      let now = Date(timeIntervalSinceReferenceDate: 805_055_000)
      let list = GroceryList(
        id: SampleUUIDSequence.uuid(13_155),
        title: "Hardware Store",
        sortOrder: 0,
        dateCreated: now,
        dateModified: now
      )

      expectNoDifference(
        GroceryListPlainTextRenderer.render(list: list, rows: []),
        """
        Hardware Store

        No grocery items.
        """
      )
    }
  }
}
