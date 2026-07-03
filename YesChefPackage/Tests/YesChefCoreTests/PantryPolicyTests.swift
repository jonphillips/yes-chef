import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct PantryPolicyTests {
    @Test
    func policyStatesRoundTripThroughRepository() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 824_000_000)
      var uuids = SampleUUIDSequence(start: 51_000)

      try database.write { db in
        let unlimitedID = try PantryRepository.addItem(
          title: "Olive oil",
          policy: .unlimited,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let thresholdID = try PantryRepository.addItem(
          title: "Soy sauce",
          policy: .threshold(quantity: 0.5, unit: " cup "),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let confirmID = try PantryRepository.addItem(
          title: "Brown sugar",
          policy: .alwaysConfirm,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        expectNoDifference(try PantryItem.find(unlimitedID).fetchOne(db)?.policy, .unlimited)
        expectNoDifference(
          try PantryItem.find(thresholdID).fetchOne(db)?.policy,
          .threshold(quantity: 0.5, unit: "cup")
        )
        expectNoDifference(try PantryItem.find(confirmID).fetchOne(db)?.policy, .alwaysConfirm)
      }
    }

    @Test
    func thresholdZeroStoresAsAlwaysConfirm() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 824_100_000)
      var uuids = SampleUUIDSequence(start: 51_100)

      try database.write { db in
        let itemID = try PantryRepository.addItem(
          title: "Soy sauce",
          policy: .threshold(quantity: 0, unit: "cup"),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let item = try #require(try PantryItem.find(itemID).fetchOne(db))
        expectNoDifference(item.policy, .alwaysConfirm)
        expectNoDifference(item.isUnlimited, false)
        expectNoDifference(item.thresholdQuantity, nil)
        expectNoDifference(item.thresholdUnit, nil)
      }
    }

    @Test
    func countUnitsCannotExposeThresholdFields() {
      expectNoDifference(PantryPolicy.canUseThreshold(unit: "cup"), true)
      expectNoDifference(PantryPolicy.canUseThreshold(unit: "oz"), true)
      expectNoDifference(PantryPolicy.canUseThreshold(unit: "cloves"), false)
      expectNoDifference(PantryPolicy.canUseThreshold(unit: nil), false)
    }

    @Test
    func canonicalNameBackfillPreservesExistingPantryMatchingBehavior() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 824_200_000)
      let lineID = SampleUUIDSequence.uuid(51_201)
      let itemID = SampleUUIDSequence.uuid(51_202)
      let recipeID = SampleUUIDSequence.uuid(51_204)
      let sectionID = SampleUUIDSequence.uuid(51_205)
      let listID = SampleUUIDSequence.uuid(51_206)

      try database.write { db in
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Oil",
          lines: [
            IngredientLine(
              id: lineID,
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "1 tablespoon olive oil",
              quantity: 1,
              quantityText: "1",
              unit: "tablespoon",
              item: "olive oil",
              sortOrder: 0,
              confidence: .medium
            )
          ],
          now: now,
          in: db
        )
        try GroceryList.insert {
          GroceryList(
            id: listID,
            title: "Migration",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: itemID,
            groceryListID: listID,
            title: "anchovy fillets",
            quantity: 4,
            quantityText: "4",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try #sql("UPDATE \"ingredientLines\" SET \"canonicalName\" = NULL WHERE \"id\" = \(bind: lineID)")
          .execute(db)
        try #sql("UPDATE \"groceryItems\" SET \"canonicalName\" = NULL WHERE \"id\" = \(bind: itemID)")
          .execute(db)

        try GroceryCanonicalNameCache.backfill(in: db)

        let line = try #require(try IngredientLine.find(lineID).fetchOne(db))
        let item = try #require(try GroceryItem.find(itemID).fetchOne(db))

        expectNoDifference(line.canonicalName, "olive oil")
        expectNoDifference(item.canonicalName, "anchovies")
        expectNoDifference(
          GroceryPantryAssumptions.isPantryStaple(line, pantryStaples: ["olive oil"]),
          true
        )
      }
    }
  }
}
