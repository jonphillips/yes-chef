import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryConsolidationTests {
    @Test
    func keepsEarliestItemAndTypedNotesWithoutChurningOnSecondRun() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_260_000)
      let modifiedAt = now.addingTimeInterval(60)
      var uuids = SampleUUIDSequence(start: 17_500)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let otherListID = try GroceryRepository.addList(
          title: "Other list", in: db, now: now, uuid: { uuids.next() }
        )
        let butterIDs = [uuids.next(), uuids.next(), uuids.next()]
        for (index, id) in butterIDs.enumerated() {
          let quantity = [2.0, 6.0, 6.0][index]
          let item = GroceryItem(
            id: id,
            groceryListID: listID,
            title: "unsalted butter",
            canonicalName: "unsalted butter",
            quantity: quantity,
            quantityText: String(Int(quantity)),
            unit: "tablespoons",
            aisle: ["Dairy", "Baking", "Produce"][index],
            notes: ["softened", "for pie", "for stock"][index],
            sortOrder: index,
            dateCreated: now,
            dateModified: now
          )
          try GroceryItem.insert { item }.execute(db)
          try GroceryItemSource.insert {
            GroceryItemSource(
              id: uuids.next(),
              groceryItemID: id,
              origin: index == 1 ? .recipe : .custom,
              ingredientLineID: index == 1 ? uuids.next() : nil,
              ingredientText: "unsalted butter",
              dateCreated: now
            )
          }.execute(db)
        }
        let checked = GroceryItem(
          id: uuids.next(), groceryListID: listID, title: "unsalted butter",
          canonicalName: "unsalted butter", quantity: 1, quantityText: "1",
          unit: "tablespoon", isPurchased: true, sortOrder: 3, dateCreated: now, dateModified: now
        )
        try GroceryItem.insert { checked }.execute(db)
        let otherListItem = GroceryItem(
          id: uuids.next(), groceryListID: otherListID, title: "unsalted butter",
          canonicalName: "unsalted butter", quantity: 3, quantityText: "3",
          unit: "tablespoons", sortOrder: 0, dateCreated: now, dateModified: now
        )
        try GroceryItem.insert { otherListItem }.execute(db)

        #expect(try GroceryRepository.consolidate(listID: listID, in: db, now: modifiedAt) == 2)
        let survivor = try #require(try GroceryItem.find(butterIDs[0]).fetchOne(db))
        #expect(survivor.quantity == 14)
        #expect(survivor.aisle == "Dairy")
        #expect(survivor.notes == "softened; for pie; for stock")
        #expect(try GroceryItem.find(butterIDs[1]).fetchOne(db) == nil)
        #expect(try GroceryItem.find(butterIDs[2]).fetchOne(db) == nil)
        #expect(try GroceryItemSource.where { $0.groceryItemID.eq(survivor.id) }.fetchCount(db) == 3)
        #expect(try GroceryItem.find(checked.id).fetchOne(db) != nil)
        #expect(try GroceryItem.find(otherListItem.id).fetchOne(db) != nil)
        #expect(
          try GroceryRepository.consolidate(
            listID: listID, in: db, now: modifiedAt.addingTimeInterval(10)
          ) == 0
        )
        #expect(try GroceryItem.find(survivor.id).fetchOne(db)?.dateModified == modifiedAt)
      }
    }

    @Test
    func consolidatesWithNewFixButLeavesIncompatibleUnitsTogether() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_261_000)
      var uuids = SampleUUIDSequence(start: 17_600)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let firstID = uuids.next()
        let secondID = uuids.next()
        for (id, title, order) in [
          (firstID, "dragonfruit alpha", 0),
          (secondID, "dragonfruit beta", 1),
          (uuids.next(), "butter", 2),
          (uuids.next(), "butter", 3),
        ] {
          let item = GroceryItem(
            id: id,
            groceryListID: listID,
            title: title,
            canonicalName: title,
            quantity: 1,
            quantityText: "1",
            unit: order < 2 ? "bunches" : (order == 2 ? "cups" : "grams"),
            sortOrder: order,
            dateCreated: now,
            dateModified: now
          )
          try GroceryItem.insert { item }.execute(db)
        }
        #expect(try IngredientNameFixRepository.save(from: "dragonfruit alpha", to: "dragonfruit beta", in: db, now: now))

        #expect(try GroceryRepository.consolidate(listID: listID, in: db, now: now.addingTimeInterval(5)) == 1)
        #expect(try GroceryItem.find(firstID).fetchOne(db)?.quantity == 2)
        #expect(try GroceryItem.find(secondID).fetchOne(db) == nil)
        #expect(try GroceryItem.where { $0.groceryListID.eq(listID) }.fetchAll(db).filter { $0.title == "butter" }.count == 2)
      }
    }

    @Test
    func sortsUncheckedItemsByTitleBeforeSortOrder() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_262_000)
      var uuids = SampleUUIDSequence(start: 17_700)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        for (title, order, purchased) in [
          ("zucchini", 0, false),
          ("apple", 1, false),
          ("aardvark", -1, true),
        ] {
          let item = GroceryItem(
            id: uuids.next(), groceryListID: listID, title: title,
            canonicalName: title, isPurchased: purchased, sortOrder: order,
            dateCreated: now, dateModified: now
          )
          try GroceryItem.insert { item }.execute(db)
        }

        #expect(try GroceryItemListRequest().fetch(db).map(\.item.title) == ["apple", "zucchini", "aardvark"])
      }
    }
  }
}
