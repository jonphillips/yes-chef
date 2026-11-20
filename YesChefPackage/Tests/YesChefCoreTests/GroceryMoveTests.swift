import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryMoveTests {
    @Test
    func movesLinesAndConsolidatesIntoDestinationWithoutChangingTripAssignments() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 905_100_000)
      let movedAt = now.addingTimeInterval(30)
      var uuids = SampleUUIDSequence(start: 95_100)

      try database.write { db in
        let sourceListID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let destinationListID = try GroceryRepository.addList(
          title: "Fresh", in: db, now: now, uuid: { uuids.next() }
        )
        let keptSource = GroceryItem(
          id: uuids.next(), groceryListID: sourceListID, title: "carrots", sortOrder: 2,
          dateCreated: now, dateModified: now
        )
        let butter = GroceryItem(
          id: uuids.next(), groceryListID: sourceListID, title: "butter", canonicalName: "butter",
          quantity: 2, quantityText: "2", unit: "tablespoons", aisle: "Baking", sortOrder: 1,
          dateCreated: now, dateModified: now
        )
        let purchased = GroceryItem(
          id: uuids.next(), groceryListID: sourceListID, title: "tea", canonicalName: "tea",
          aisle: "Beverages", isPurchased: true, sortOrder: 0,
          dateCreated: now, dateModified: now
        )
        let destinationButter = GroceryItem(
          id: uuids.next(), groceryListID: destinationListID, title: "unsalted butter",
          canonicalName: "butter", quantity: 6, quantityText: "6", unit: "tablespoons",
          aisle: "Dairy", sortOrder: 4, dateCreated: now, dateModified: now
        )
        for item in [keptSource, butter, purchased, destinationButter] {
          try GroceryItem.insert { item }.execute(db)
        }
        let butterSource = GroceryItemSource(
          id: uuids.next(), groceryItemID: butter.id, origin: .custom,
          ingredientText: "2 tablespoons butter", dateCreated: now
        )
        let destinationSource = GroceryItemSource(
          id: uuids.next(), groceryItemID: destinationButter.id, origin: .custom,
          ingredientText: "6 tablespoons butter", dateCreated: now
        )
        let purchasedSource = GroceryItemSource(
          id: uuids.next(), groceryItemID: purchased.id, origin: .custom,
          ingredientText: "tea", dateCreated: now
        )
        for source in [butterSource, destinationSource, purchasedSource] {
          try GroceryItemSource.insert { source }.execute(db)
        }
        let assignment = GroceryTripAssignment(
          id: uuids.next(), canonicalName: "butter", trip: .advance, dateModified: now
        )
        try GroceryTripAssignment.insert { assignment }.execute(db)

        #expect(try GroceryRepository.moveItems(
          [butter.id, purchased.id], toListID: destinationListID, in: db, now: movedAt
        ) == 1)

        let kept = try #require(try GroceryItem.find(keptSource.id).fetchOne(db))
        #expect(kept.groceryListID == sourceListID)
        #expect(try GroceryItem.find(butter.id).fetchOne(db) == nil)
        let purchasedAfterMove = try #require(try GroceryItem.find(purchased.id).fetchOne(db))
        #expect(purchasedAfterMove.groceryListID == destinationListID)
        #expect(purchasedAfterMove.id == purchased.id)
        #expect(purchasedAfterMove.aisle == "Beverages")
        #expect(purchasedAfterMove.isPurchased)
        #expect(purchasedAfterMove.sortOrder == 5)
        #expect(purchasedAfterMove.dateModified == movedAt)
        let survivor = try #require(try GroceryItem.find(destinationButter.id).fetchOne(db))
        #expect(survivor.quantity == 8)
        #expect(survivor.id == destinationButter.id)
        #expect(survivor.title == "unsalted butter")
        #expect(survivor.aisle == "Dairy")
        #expect(try GroceryItemSource.where { $0.groceryItemID.eq(survivor.id) }.fetchAll(db).count == 2)
        #expect(try GroceryItemSource.where { $0.groceryItemID.eq(purchased.id) }.fetchOne(db) == purchasedSource)
        #expect(try GroceryTripAssignment.fetchAll(db) == [assignment])
      }
    }

    @Test
    func movedItemsConsolidateTogetherButSkipPurchasedAndIncompatibleLines() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 905_101_000)
      var uuids = SampleUUIDSequence(start: 95_200)

      try database.write { db in
        let sourceListID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let destinationListID = try GroceryRepository.addList(
          title: "Other", in: db, now: now, uuid: { uuids.next() }
        )
        let first = GroceryItem(
          id: uuids.next(), groceryListID: sourceListID, title: "butter", canonicalName: "butter",
          quantity: 2, quantityText: "2", unit: "tablespoons", sortOrder: 0,
          dateCreated: now, dateModified: now
        )
        let second = GroceryItem(
          id: uuids.next(), groceryListID: sourceListID, title: "butter", canonicalName: "butter",
          quantity: 3, quantityText: "3", unit: "tablespoons", sortOrder: 1,
          dateCreated: now, dateModified: now
        )
        let incompatible = GroceryItem(
          id: uuids.next(), groceryListID: sourceListID, title: "butter", canonicalName: "butter",
          quantity: 1, quantityText: "1", unit: "grams", sortOrder: 2,
          dateCreated: now, dateModified: now
        )
        let purchasedDestination = GroceryItem(
          id: uuids.next(), groceryListID: destinationListID, title: "butter", canonicalName: "butter",
          quantity: 1, quantityText: "1", unit: "tablespoons", isPurchased: true, sortOrder: 0,
          dateCreated: now, dateModified: now
        )
        for item in [first, second, incompatible, purchasedDestination] {
          try GroceryItem.insert { item }.execute(db)
        }

        #expect(try GroceryRepository.moveItems(
          [first.id, second.id, incompatible.id], toListID: destinationListID, in: db, now: now
        ) == 1)
        let destinationItems = try GroceryItem.where { $0.groceryListID.eq(destinationListID) }
          .fetchAll(db)
          .sorted { $0.sortOrder < $1.sortOrder }
        #expect(destinationItems.count == 3)
        #expect(destinationItems.first?.id == purchasedDestination.id)
        #expect(try GroceryItem.find(first.id).fetchOne(db)?.quantity == 5)
        #expect(try GroceryItem.find(second.id).fetchOne(db) == nil)
        #expect(try GroceryItem.find(incompatible.id).fetchOne(db)?.groceryListID == destinationListID)
        #expect(try GroceryRepository.moveItems(
          [first.id, incompatible.id], toListID: destinationListID, in: db, now: now.addingTimeInterval(1)
        ) == 0)
        #expect(try GroceryItem.find(incompatible.id).fetchOne(db)?.dateModified == now)
        let missingListID = uuids.next()
        #expect(throws: GroceryRepositoryError.listNotFound(missingListID)) {
          try GroceryRepository.moveItems([incompatible.id], toListID: missingListID, in: db, now: now)
        }
      }
    }
  }
}
