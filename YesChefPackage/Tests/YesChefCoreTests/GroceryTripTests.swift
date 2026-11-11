import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryTripTests {
    @Test
    func defaultTripUsesKeeperListThenAreaThenFresh() {
      for name in ["onion", "yellow onion", "garlic", "garlic clove", "lemon juice", "celery stalk", "butternut squash",
                   "cranberry"] {
        #expect(GroceryTripRule.defaultTrip(canonicalName: name, area: nil) == .advance)
      }
      for name in ["green onion", "spring onion", "cilantro", "turkey", "baguette"] {
        #expect(GroceryTripRule.defaultTrip(canonicalName: name, area: "Produce") == .fresh)
      }
      for area in ["Canned & Dry", "Baking", "Frozen"] {
        #expect(GroceryTripRule.defaultTrip(canonicalName: "unknown item", area: area) == .advance)
      }
      #expect(GroceryTripRule.defaultTrip(canonicalName: "unknown item", area: nil) == .fresh)
    }

    @Test
    func savedSwitchWinsAndAreaCorrectionSetsTheDefault() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_100_000)
      let name = try #require(CanonicalIngredient.canonicalName("canned tomatoes"))
      try database.write { db in
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_101), canonicalName: name,
            area: "Canned & Dry", source: .user, dateModified: now
          )
        }.execute(db)
        let corrected = try GroceryTripRepository.trips(forCanonicalNames: [name, "cilantro"], in: db)
        #expect(corrected[name] == .advance)
        #expect(corrected["cilantro"] == .fresh)

        try GroceryTripRepository.recordSwitches([name: .fresh], in: db, now: now)
        try GroceryTripRepository.recordSwitches([name: .fresh], in: db, now: now.addingTimeInterval(1))
        let assignments = try GroceryTripAssignment.fetchAll(db)
        #expect(assignments.count == 1)
        #expect(assignments.first?.id == DeterministicID.groceryTrip(canonicalName: name))
        #expect(try GroceryTripRepository.trips(forCanonicalNames: [name], in: db)[name] == .fresh)
      }
    }

    @Test
    func tripListReusesExactTitleAndCreatesMissingTitle() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_200_000)
      try database.write { db in
        let first = try GroceryRepository.tripListID(title: "Thanksgiving — Advance", in: db, now: now,
          uuid: { SampleUUIDSequence.uuid(90_201) })
        let reused = try GroceryRepository.tripListID(title: "Thanksgiving — Advance", in: db, now: now,
          uuid: { SampleUUIDSequence.uuid(90_202) })
        let other = try GroceryRepository.tripListID(title: "Thanksgiving — Fresh", in: db, now: now,
          uuid: { SampleUUIDSequence.uuid(90_203) })
        #expect(first == reused)
        #expect(first != other)
      }
    }

    @Test
    func skippedStapleTitlesIncludesUnlimitedPantryItemsOnly() {
      let now = Date(timeIntervalSinceReferenceDate: 900_300_000)
      let unlimited = PantryItem(id: SampleUUIDSequence.uuid(90_301), title: "Olive oil", isUnlimited: true,
        sortOrder: 0, dateCreated: now, dateModified: now)
      let remindMe = PantryItem(id: SampleUUIDSequence.uuid(90_302), title: "Butter", isUnlimited: false,
        thresholdQuantity: 1, thresholdUnit: "cup", sortOrder: 1, dateCreated: now, dateModified: now)
      let confirm = PantryItem(id: SampleUUIDSequence.uuid(90_303), title: "Eggs", isUnlimited: false,
        sortOrder: 2, dateCreated: now, dateModified: now)
      #expect(GroceryPantryAssumptions.skippedStapleTitles(from: [unlimited, remindMe, confirm]) == ["Olive oil"])
    }

    @Test
    func groceriesHelpPageFitsLabelBudget() {
      #expect(AppHelpPage.groceries.plainText.count <= 1_800)
      #expect(AppHelpPage.groceries.plainText.contains("How Groceries Work"))
    }
  }
}
