import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GrocerySourceContributionTests {
    @Test
    func groupsSourcesByContributionPreservingSourceOrder() {
      let itemID = SampleUUIDSequence.uuid(19_001)
      let listID = SampleUUIDSequence.uuid(19_002)
      let recipeID = SampleUUIDSequence.uuid(19_003)
      let firstSourceID = SampleUUIDSequence.uuid(19_004)
      let secondSourceID = SampleUUIDSequence.uuid(19_005)
      let menuID = SampleUUIDSequence.uuid(19_006)
      let menuItemID = SampleUUIDSequence.uuid(19_007)
      let menuSourceID = SampleUUIDSequence.uuid(19_008)
      let customSourceID = SampleUUIDSequence.uuid(19_009)
      let now = Date(timeIntervalSinceReferenceDate: 806_000_000)

      let row = GroceryItemRowData(
        item: GroceryItem(
          id: itemID,
          groceryListID: listID,
          title: "milk",
          sortOrder: 0,
          dateCreated: now,
          dateModified: now
        ),
        sources: [
          GroceryItemSource(
            id: firstSourceID,
            groceryItemID: itemID,
            origin: .recipe,
            recipeID: recipeID,
            sourceTitle: "Pancakes",
            dateCreated: now
          ),
          GroceryItemSource(
            id: secondSourceID,
            groceryItemID: itemID,
            origin: .recipe,
            recipeID: recipeID,
            sourceTitle: "Pancakes",
            dateCreated: now
          ),
          GroceryItemSource(
            id: menuSourceID,
            groceryItemID: itemID,
            origin: .menu,
            menuID: menuID,
            menuItemID: menuItemID,
            sourceTitle: "Brunch",
            sourceSubtitle: "Waffles",
            dateCreated: now
          ),
          GroceryItemSource(
            id: customSourceID,
            groceryItemID: itemID,
            origin: .custom,
            sourceTitle: "Custom",
            dateCreated: now
          ),
        ]
      )

      expectNoDifference(
        row.sourceContributions.map(\.id),
        [
          .recipe(recipeID),
          .menuItem(menuID, menuItemID),
          .source(customSourceID),
        ]
      )
      expectNoDifference(
        row.sourceContributions.map { $0.sources.map(\.id) },
        [
          [firstSourceID, secondSourceID],
          [menuSourceID],
          [customSourceID],
        ]
      )
      expectNoDifference(
        row.sourceContributions.map(\.removalTitle),
        ["Remove Recipe Items", "Remove Menu Dish Items", nil]
      )
    }
  }
}
