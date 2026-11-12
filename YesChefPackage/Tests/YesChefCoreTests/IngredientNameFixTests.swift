import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite(.serialized, .dependencies {
    $0.context = .live
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefIngredientNameFixTests-\(UUID().uuidString).sqlite").path
    try $0.bootstrapDatabase(path: path, syncMode: .disabled)
  })
  struct IngredientNameFixTests {
    @Test
    func saveNormalizesAndFlattensFixesWithoutTouchingIngredients() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_700_000)

      try database.write { db in
        #expect(try IngredientNameFixRepository.save(from: "Curly-leaf parsley", to: "Parsley", in: db, now: now))
        #expect(try IngredientNameFixRepository.save(from: "Parsley", to: "cilantro", in: db, now: now))

        let rows = try IngredientNameFix.fetchAll(db).sorted { $0.fromName < $1.fromName }
        #expect(rows.map(\.fromName) == ["curly leaf parsley", "parsley"])
        #expect(rows.map(\.toName) == ["cilantro", "cilantro"])
        #expect(IngredientNameFixes(rows: rows).canonicalName("curly-leaf parsley") == "cilantro")
        #expect(try IngredientNameFixRepository.save(from: "parsley", to: "PARSLEY", in: db, now: now) == false)

        #expect(try IngredientLine.fetchCount(db) == 0)
        #expect(try GroceryItem.fetchCount(db) == 0)
        try IngredientNameFixRepository.delete(fromName: "curly leaf parsley", in: db)
        #expect(try IngredientNameFix.fetchAll(db).count == 1)
        #expect(try IngredientLine.fetchCount(db) == 0)
        #expect(try GroceryItem.fetchCount(db) == 0)

        #expect(try IngredientNameFixRepository.save(from: "cilantro", to: "parsley", in: db, now: now))
        let reversed = try IngredientNameFix.fetchAll(db)
        #expect(reversed.count == 1)
        #expect(reversed.first?.fromName == "cilantro")
        #expect(reversed.first?.toName == "parsley")
      }
    }

    @Test
    func lookupTerminatesWhenSyncedRowsContainACycle() {
      let cycle = IngredientNameFixes(rows: [
        IngredientNameFix(
          id: DeterministicID.ingredientNameFix(fromName: "dragonfruit alpha"),
          fromName: "dragonfruit alpha",
          toName: "dragonfruit beta",
          dateModified: .distantPast
        ),
        IngredientNameFix(
          id: DeterministicID.ingredientNameFix(fromName: "dragonfruit beta"),
          fromName: "dragonfruit beta",
          toName: "dragonfruit alpha",
          dateModified: .distantPast
        ),
      ])

      #expect(cycle.canonicalName("dragonfruit alpha") == "dragonfruit alpha")
    }

    @Test
    func compareKeyAppliesAFixWhoseFromNameHasAFormWord() {
      let fixes = IngredientNameFixes(rows: [
        IngredientNameFix(
          id: DeterministicID.ingredientNameFix(fromName: "smoked paprika"),
          fromName: "smoked paprika",
          toName: "pimenton",
          dateModified: .distantPast
        ),
      ])

      #expect(CanonicalIngredient.comparisonKey("smoked paprika") == "paprika")
      #expect(fixes.comparisonKey("smoked paprika") == "pimenton")
      #expect(fixes.comparisonKey("pimentón") == "pimenton")
      #expect(fixes.comparisonKey("sweet paprika") == CanonicalIngredient.comparisonKey("sweet paprika"))
    }

    @Test
    func runtimeAreaBackfillResolvesThroughFixes() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 901_100_000)
      var uuids = SampleUUIDSequence(start: 91_100)

      try database.write { db in
        try GroceryStoreAreaCache.applyUserCorrection(
          canonicalName: "parsley", area: "Bakery", in: db, now: now, uuid: { uuids.next() }
        )
        #expect(try IngredientNameFixRepository.save(from: "curly leaf parsley", to: "parsley", in: db, now: now))
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let item = GroceryItem(
          id: uuids.next(), groceryListID: listID,
          title: "curly leaf parsley", canonicalName: "curly leaf parsley", sortOrder: 0,
          dateCreated: now, dateModified: now
        )
        try GroceryItem.insert { item }.execute(db)

        try GroceryStoreAreaCache.backfill(in: db, fixes: IngredientNameFixes.load(in: db))

        #expect(try GroceryItem.find(item.id).fetchOne(db)?.aisle == GroceryStoreArea.bakery.title)
      }
    }

    @Test
    func sameAsMergesCompatibleItemsAndMovesTheirSources() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_800_000)
      var uuids = SampleUUIDSequence(start: 90_800)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let fromID = try GroceryRepository.addCustomItem(
          title: "curly-leaf parsley", groceryListID: listID, in: db, now: now, uuid: { uuids.next() }
        )
        let toID = try GroceryRepository.addCustomItem(
          title: "parsley", groceryListID: listID, in: db, now: now, uuid: { uuids.next() }
        )

        try GroceryRepository.sameAs(itemID: fromID, targetItemID: toID, in: db, now: now)

        let items = try GroceryItem.where { $0.groceryListID.eq(listID) }.fetchAll(db)
        #expect(items.map(\.id) == [toID])
        let sources = try GroceryItemSource.fetchAll(db)
        #expect(sources.count == 2)
        #expect(sources.allSatisfy { $0.groceryItemID == toID })
        #expect(try IngredientNameFixes.load(in: db).canonicalName("curly-leaf parsley") == "parsley")
      }
    }

    @Test
    func sameAsKeepsIncompatibleItemsAndAdoptsTargetDisplayFields() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_900_000)
      var uuids = SampleUUIDSequence(start: 90_900)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        let fromID = try GroceryRepository.addCustomItem(
          title: "curly-leaf parsley", aisle: "Herbs", notes: "chopped",
          groceryListID: listID, in: db, now: now, uuid: { uuids.next() }
        )
        let toID = try GroceryRepository.addCustomItem(
          title: "parsley", aisle: "Produce",
          groceryListID: listID, in: db, now: now, uuid: { uuids.next() }
        )
        let otherListID = try GroceryRepository.addList(
          title: "Another list", in: db, now: now, uuid: { uuids.next() }
        )
        let otherListItemID = try GroceryRepository.addCustomItem(
          title: "curly-leaf parsley", groceryListID: otherListID, in: db, now: now, uuid: { uuids.next() }
        )

        try GroceryRepository.sameAs(itemID: fromID, targetItemID: toID, in: db, now: now)

        let items = try GroceryItem.where { $0.groceryListID.eq(listID) }.fetchAll(db)
        let from = try #require(items.first { $0.id == fromID })
        #expect(items.count == 2)
        #expect(from.title == "parsley")
        #expect(from.canonicalName == "parsley")
        #expect(from.aisle == "Produce")
        #expect(from.notes == "chopped")
        #expect(try GroceryItem.find(otherListItemID).fetchOne(db)?.title == "curly-leaf parsley")
      }
    }

    @Test
    func fixAppliesToAreaTripPantryAndCompareKeys() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 901_000_000)
      let groceryListID = SampleUUIDSequence.uuid(91_001)
      let sourceItem = GroceryItem(
        id: SampleUUIDSequence.uuid(91_002), groceryListID: groceryListID,
        title: "curly leaf parsley", canonicalName: "curly leaf parsley", sortOrder: 0,
        dateCreated: now, dateModified: now
      )
      let pantryItem = PantryItem(
        id: SampleUUIDSequence.uuid(91_003), title: "parsley", sortOrder: 0,
        dateCreated: now, dateModified: now
      )
      let workingID = SampleUUIDSequence.uuid(91_004)
      let workingSectionID = SampleUUIDSequence.uuid(91_005)
      let candidateID = SampleUUIDSequence.uuid(91_006)
      let candidateSectionID = SampleUUIDSequence.uuid(91_007)
      let working = RecipeDetailData(
        recipe: Recipe(id: workingID, title: "Working", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: workingSectionID, recipeID: workingID, sortOrder: 0)],
        ingredientLines: [IngredientLine(
          id: SampleUUIDSequence.uuid(91_008), recipeID: workingID, sectionID: workingSectionID,
          originalText: "curly leaf parsley", item: "curly leaf parsley", sortOrder: 0
        )]
      )
      let candidate = RecipeDetailData(
        recipe: Recipe(id: candidateID, title: "Candidate", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: candidateSectionID, recipeID: candidateID, sortOrder: 0)],
        ingredientLines: [IngredientLine(
          id: SampleUUIDSequence.uuid(91_009), recipeID: candidateID, sectionID: candidateSectionID,
          originalText: "parsley", item: "parsley", sortOrder: 0
        )]
      )

      try database.write { db in
        #expect(try IngredientNameFixRepository.save(from: "curly leaf parsley", to: "parsley", in: db, now: now))
        let fixes = try IngredientNameFixes.load(in: db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(91_010), canonicalName: "parsley", area: "Meat & Seafood",
            source: .user, dateModified: now
          )
        }.execute(db)
        try GroceryTripAssignment.insert {
          GroceryTripAssignment(
            id: DeterministicID.groceryTrip(canonicalName: "parsley"), canonicalName: "parsley",
            trip: .advance, dateModified: now
          )
        }.execute(db)

        #expect(try GroceryStoreAreaCache.resolvedAreas(for: ["curly leaf parsley"], in: db)["curly leaf parsley"] == .meatAndSeafood)
        #expect(try GroceryTripRepository.trips(forCanonicalNames: ["curly leaf parsley"], in: db)["parsley"] == .advance)
        #expect(GroceryPantryAssumptions.isPantryStaple(
          IngredientLine(
            id: SampleUUIDSequence.uuid(91_011), recipeID: workingID, sectionID: workingSectionID,
            originalText: "curly leaf parsley", item: "curly leaf parsley", sortOrder: 0
          ), pantryStaples: ["parsley"], fixes: fixes
        ))
        let suppression = PantrySuppression.evaluate(
          list: [GroceryItemRowData(item: sourceItem)], policies: [pantryItem], fixes: fixes
        )
        #expect(suppression.assumedInPantry.map(\.id) == [sourceItem.id])
        let comparison = WorkbenchCompare.ingredientComparison(
          working: working, candidates: [candidate], fixes: fixes
        )
        #expect(comparison.rows.map(\.id) == ["parsley"])
        #expect(comparison.rows.first?.cells == ["curly leaf parsley", "parsley"])
      }
    }

    @Test
    func generatedGroceriesUseFixesAndStoreBaseNames() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 901_100_000)
      var uuids = SampleUUIDSequence(start: 91_100)
      let firstRecipeID = SampleUUIDSequence.uuid(91_201)
      let firstSectionID = SampleUUIDSequence.uuid(91_202)
      let secondRecipeID = SampleUUIDSequence.uuid(91_203)
      let secondSectionID = SampleUUIDSequence.uuid(91_204)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        try insertRecipeFixture(
          recipeID: firstRecipeID, sectionID: firstSectionID, title: "First",
          lines: [IngredientLine(
            id: SampleUUIDSequence.uuid(91_205), recipeID: firstRecipeID, sectionID: firstSectionID,
            originalText: "1 curly leaf parsley", quantity: 1, quantityText: "1",
            item: "curly leaf parsley", sortOrder: 0
          )], now: now, in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID, sectionID: secondSectionID, title: "Second",
          lines: [IngredientLine(
            id: SampleUUIDSequence.uuid(91_206), recipeID: secondRecipeID, sectionID: secondSectionID,
            originalText: "2 parsley", quantity: 2, quantityText: "2", item: "parsley", sortOrder: 0
          )], now: now, in: db
        )
        #expect(try IngredientNameFixRepository.save(from: "curly leaf parsley", to: "parsley", in: db, now: now))
        _ = try GroceryRepository.addRecipe(recipeID: firstRecipeID, groceryListID: listID, in: db, now: now, uuid: { uuids.next() })
        _ = try GroceryRepository.addRecipe(recipeID: secondRecipeID, groceryListID: listID, in: db, now: now, uuid: { uuids.next() })
        let merged = try GroceryItem.where { $0.groceryListID.eq(listID) }.fetchAll(db)
        #expect(merged.count == 1)
        #expect(merged.first?.canonicalName == "curly leaf parsley")
        #expect(merged.first?.quantity == 3)

        try IngredientNameFixRepository.delete(fromName: "curly leaf parsley", in: db)
        _ = try GroceryRepository.clearAllItems(groceryListID: listID, in: db)
        _ = try GroceryRepository.addRecipe(recipeID: firstRecipeID, groceryListID: listID, in: db, now: now, uuid: { uuids.next() })
        _ = try GroceryRepository.addRecipe(recipeID: secondRecipeID, groceryListID: listID, in: db, now: now, uuid: { uuids.next() })
        #expect(try GroceryItem.where { $0.groceryListID.eq(listID) }.fetchCount(db) == 2)
      }
    }
  }
}
