import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryStoreAreaTests {
    @Test
    func foldsSynonymsAndTitleCasesUnknownAreas() {
      expectNoDifference(GroceryStoreArea.normalized(" vegetables "), .produce)
      expectNoDifference(GroceryStoreArea.normalized("Butcher"), .meatAndSeafood)
      expectNoDifference(GroceryStoreArea.normalized("seafood"), .meatAndSeafood)
      expectNoDifference(GroceryStoreArea.normalized("bulk bins"), .custom("Bulk Bins"))
    }

    @Test
    func ordersCanonicalAreasInStoreWalkOrder() {
      expectNoDifference(
        GroceryStoreArea.canonicalAreas.map(\.title),
        [
          "Produce",
          "Bakery",
          "Deli",
          "Canned & Dry",
          "Condiments & Oils",
          "Spices",
          "Baking",
          "Beverages",
          "Meat & Seafood",
          "Household",
          "Dairy",
          "Frozen",
          "Other",
        ]
      )
    }

    @Test
    func groupsUnknownAreasJustBeforeOther() {
      let listID = SampleUUIDSequence.uuid(87_001)
      let now = Date(timeIntervalSinceReferenceDate: 879_000_000)
      let rows = [
        GroceryItemRowData(
          item: GroceryItem(
            id: SampleUUIDSequence.uuid(87_002),
            groceryListID: listID,
            title: "Apples",
            aisle: "Produce",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        ),
        GroceryItemRowData(
          item: GroceryItem(
            id: SampleUUIDSequence.uuid(87_003),
            groceryListID: listID,
            title: "Grains",
            aisle: "bulk bins",
            sortOrder: 1,
            dateCreated: now,
            dateModified: now
          )
        ),
        GroceryItemRowData(
          item: GroceryItem(
            id: SampleUUIDSequence.uuid(87_004),
            groceryListID: listID,
            title: "Za'atar",
            sortOrder: 2,
            dateCreated: now,
            dateModified: now
          )
        ),
      ]

      expectNoDifference(GroceryStoreArea.sections(for: rows).map(\.title), ["Produce", "Bulk Bins", "Other"])
    }

    @Test
    func seedsCommonCanonicalNames() {
      expectNoDifference(GroceryStoreArea.seed(for: "avocado"), .produce)
      expectNoDifference(GroceryStoreArea.seed(for: "milk"), .dairy)
      expectNoDifference(GroceryStoreArea.seed(for: "chicken thighs"), .meatAndSeafood)
      expectNoDifference(GroceryStoreArea.seed(for: "all-purpose flour"), .baking)
    }

    @Test
    func seedsAislesOnCustomInsertion() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 879_500_000)
      var uuids = SampleUUIDSequence(start: 87_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let itemID = try GroceryRepository.addCustomItem(
          title: "Milk",
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let item = try #require(try GroceryItem.find(itemID).fetchOne(db))
        expectNoDifference(item.aisle, "Dairy")
      }
    }

    @Test
    func preservesUserSetAisleOnGenerationAndBackfill() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 880_000_000)
      let recipeID = SampleUUIDSequence.uuid(88_001)
      let sectionID = SampleUUIDSequence.uuid(88_002)
      let lineID = SampleUUIDSequence.uuid(88_003)
      var uuids = SampleUUIDSequence(start: 88_100)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Chicken Dinner",
          lines: [
            IngredientLine(
              id: lineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "chicken thighs",
              item: "chicken thighs",
              shoppingCategory: "My Butcher",
              sortOrder: 0
            )
          ],
          now: now,
          in: db
        )

        let itemID = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let item = try #require(try GroceryItem.find(itemID[0]).fetchOne(db))
        expectNoDifference(item.aisle, "My Butcher")

        try GroceryStoreAreaCache.backfill(in: db)
        let backfilledItem = try #require(try GroceryItem.find(itemID[0]).fetchOne(db))
        expectNoDifference(backfilledItem.aisle, "My Butcher")
      }
    }

    @Test
    func backfillSeedsOnlyMissingAreasAndIsIdempotent() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 880_100_000)
      let listID = SampleUUIDSequence.uuid(88_201)
      let potatoID = SampleUUIDSequence.uuid(88_202)
      let zaatarID = SampleUUIDSequence.uuid(88_203)

      try database.write { db in
        try GroceryList.insert {
          GroceryList(
            id: listID,
            title: "Shopping",
            sortOrder: 0,
            isDefault: true,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: potatoID,
            groceryListID: listID,
            title: "Potatoes",
            canonicalName: "potato",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: zaatarID,
            groceryListID: listID,
            title: "Za'atar",
            canonicalName: "za'atar",
            sortOrder: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        try GroceryStoreAreaCache.backfill(in: db)
        try GroceryStoreAreaCache.backfill(in: db)

        let potato = try #require(try GroceryItem.find(potatoID).fetchOne(db))
        let zaatar = try #require(try GroceryItem.find(zaatarID).fetchOne(db))
        expectNoDifference(potato.aisle, "Produce")
        expectNoDifference(zaatar.aisle, nil)
      }
    }
  }
}
