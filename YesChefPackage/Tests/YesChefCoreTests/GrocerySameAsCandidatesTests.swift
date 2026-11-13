import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GrocerySameAsCandidatesTests {
    @Test
    func leavesOutSelfAndItemsWithTheSameResolvedName() {
      let now = Date(timeIntervalSinceReferenceDate: 900_020_000)
      let listID = SampleUUIDSequence.uuid(90_520)
      let rows = [
        row(id: 90_521, listID: listID, title: "fresh mint leaves"),
        row(id: 90_522, listID: listID, title: "mint"),
        row(id: 90_523, listID: listID, title: "parsley"),
        row(id: 90_524, listID: listID, title: "unsalted butter"),
        row(id: 90_525, listID: listID, title: "unsalted butter"),
      ]
      let fixes = IngredientNameFixes(rows: [
        IngredientNameFix(
          id: SampleUUIDSequence.uuid(90_526),
          fromName: CanonicalIngredient.baseName("fresh mint leaves") ?? "fresh mint leaves",
          toName: "mint",
          dateModified: now
        ),
      ])

      expectNoDifference(
        GrocerySameAsCandidates.rows(for: rows[0].id, from: rows, fixes: fixes).map(\.id),
        [rows[2].id, rows[3].id, rows[4].id]
      )
    }

    private func row(id: Int, listID: GroceryList.ID, title: String) -> GroceryItemRowData {
      let now = Date(timeIntervalSinceReferenceDate: 900_020_000)
      return GroceryItemRowData(item: GroceryItem(
        id: SampleUUIDSequence.uuid(id),
        groceryListID: listID,
        title: title,
        canonicalName: CanonicalIngredient.baseName(title),
        sortOrder: id,
        dateCreated: now,
        dateModified: now
      ))
    }
  }
}
