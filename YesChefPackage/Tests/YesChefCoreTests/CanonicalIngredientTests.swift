import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CanonicalIngredientTests {
    @Test
    func canonicalizesAliasesAndLightPlurals() {
      expectNoDifference(CanonicalIngredient.baseName("anchovy fillets"), "anchovies")
      expectNoDifference(CanonicalIngredient.baseName("anchovy filets"), "anchovies")
      expectNoDifference(CanonicalIngredient.baseName("scallions"), "green onions")
      expectNoDifference(CanonicalIngredient.baseName("green onion"), "green onions")
      expectNoDifference(CanonicalIngredient.baseName("tomatoes"), "tomatoes")
      expectNoDifference(CanonicalIngredient.baseName("tomato"), "tomatoes")
    }

    @Test
    func prepAdverbsAndParsleyVarietiesShareAKey() {
      expectNoDifference(CanonicalIngredient.baseName("finely chopped fresh mint"), "mint")
      expectNoDifference(CanonicalIngredient.baseName("minced fresh mint"), "mint")
      expectNoDifference(CanonicalIngredient.baseName("very thinly sliced shallots"), "shallot")
      expectNoDifference(CanonicalIngredient.baseName("freshly cracked black pepper"), "black pepper")
      expectNoDifference(CanonicalIngredient.baseName("chopped flat-leaf parsley"), "parsley")
      expectNoDifference(CanonicalIngredient.baseName("minced fresh parsley"), "parsley")
      expectNoDifference(CanonicalIngredient.baseName("Italian parsley"), "parsley")
      // Form words stay on the grocery key.
      expectNoDifference(CanonicalIngredient.baseName("finely chopped frozen spinach"), "frozen spinach")
    }

    @Test
    func compoundPartsSplitOnAnd() {
      expectNoDifference(
        CanonicalIngredient.compoundParts("salt and freshly cracked black pepper"),
        ["salt", "black pepper"]
      )
      expectNoDifference(CanonicalIngredient.compoundParts("black pepper"), nil)
    }

    @Test
    func chilePepperSpellingsCollapseToOneKey() {
      // chile / chiles / chilies all reduce to `chile` — the naive `-ies → y` rule turned
      // `chilies → chily`, splitting it off from `chiles → chile` onto a separate matrix row.
      for spelling in ["ancho chile", "ancho chiles", "ancho chilies", "ancho chilis"] {
        expectNoDifference(CanonicalIngredient.baseName(spelling), "ancho chile")
        expectNoDifference(CanonicalIngredient.comparisonKey(spelling), "ancho chile")
      }

      // The targeted exception does not disturb the generic `-ies → y` / `-oes → o` plurals.
      expectNoDifference(CanonicalIngredient.baseName("berries"), "berry")
      expectNoDifference(CanonicalIngredient.baseName("cherries"), "cherry")
      expectNoDifference(CanonicalIngredient.baseName("tomatoes"), "tomatoes")
      expectNoDifference(CanonicalIngredient.baseName("potatoes"), "potato")
    }

    @Test
    func comparisonKeyCoarsensFormWhileGroceryKeyKeepsItSplit() {
      // The compare key drops form/state words so variants share a matrix row…
      expectNoDifference(
        CanonicalIngredient.comparisonKey("dried ancho chiles"),
        CanonicalIngredient.comparisonKey("ancho chiles")
      )
      expectNoDifference(
        CanonicalIngredient.comparisonKey("frozen spinach"),
        CanonicalIngredient.comparisonKey("fresh spinach")
      )
      expectNoDifference(CanonicalIngredient.comparisonKey("frozen spinach"), "spinach")
      // …descriptors strip from any position, not just the front…
      expectNoDifference(
        CanonicalIngredient.comparisonKey("medium garlic cloves"),
        CanonicalIngredient.comparisonKey("garlic cloves")
      )
      // …and aliases still resolve.
      expectNoDifference(CanonicalIngredient.comparisonKey("scallions"), "green onions")

      // But the grocery key deliberately keeps state distinct — a wrong SKU on the shop is expensive.
      #expect(
        CanonicalIngredient.baseName("frozen spinach")
          != CanonicalIngredient.baseName("fresh spinach")
      )
      #expect(
        CanonicalIngredient.baseName("dried ancho chiles")
          != CanonicalIngredient.baseName("ancho chiles")
      )
    }

    @Test
    func preservesExistingPantryStapleMatchingBehavior() {
      for (offset, title) in GroceryPantryAssumptions.defaultStaples.enumerated() {
        expectNoDifference(
          GroceryPantryAssumptions.isPantryStaple(
            IngredientLine(
              id: SampleUUIDSequence.uuid(41_000 + offset),
              recipeID: SampleUUIDSequence.uuid(42_000 + offset),
              sectionID: SampleUUIDSequence.uuid(43_000 + offset),
              originalText: title,
              item: title,
              sortOrder: offset
            )
          ),
          true
        )
      }

      expectNoDifference(
        GroceryPantryAssumptions.isPantryStaple(
          IngredientLine(
            id: SampleUUIDSequence.uuid(44_001),
            recipeID: SampleUUIDSequence.uuid(44_002),
            sectionID: SampleUUIDSequence.uuid(44_003),
            originalText: "olive oil, divided",
            item: nil,
            sortOrder: 0
          )
        ),
        true
      )
    }

    @Test
    func generatedGroceriesMergeAliasesThroughCanonicalKey() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 820_000_000)
      var uuids = SampleUUIDSequence(start: 45_000)

      let firstRecipeID = SampleUUIDSequence.uuid(45_101)
      let firstSectionID = SampleUUIDSequence.uuid(45_102)
      let anchovyFilletID = SampleUUIDSequence.uuid(45_103)
      let scallionID = SampleUUIDSequence.uuid(45_104)
      let tomatoID = SampleUUIDSequence.uuid(45_105)
      let secondRecipeID = SampleUUIDSequence.uuid(45_201)
      let secondSectionID = SampleUUIDSequence.uuid(45_202)
      let anchovyID = SampleUUIDSequence.uuid(45_203)
      let greenOnionID = SampleUUIDSequence.uuid(45_204)
      let tomatoesID = SampleUUIDSequence.uuid(45_205)

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertRecipeFixture(
          recipeID: firstRecipeID,
          sectionID: firstSectionID,
          title: "Bagna Cauda",
          lines: [
            IngredientLine(
              id: anchovyFilletID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "4 anchovy fillets",
              quantity: 4,
              quantityText: "4",
              item: "anchovy fillets",
              sortOrder: 0
            ),
            IngredientLine(
              id: scallionID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "2 scallions",
              quantity: 2,
              quantityText: "2",
              item: "scallions",
              sortOrder: 1
            ),
            IngredientLine(
              id: tomatoID,
              recipeID: firstRecipeID,
              sectionID: firstSectionID,
              originalText: "1 tomato",
              quantity: 1,
              quantityText: "1",
              item: "tomato",
              sortOrder: 2
            ),
          ],
          now: now,
          in: db
        )
        try insertRecipeFixture(
          recipeID: secondRecipeID,
          sectionID: secondSectionID,
          title: "Pasta",
          lines: [
            IngredientLine(
              id: anchovyID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "2 anchovies",
              quantity: 2,
              quantityText: "2",
              item: "anchovies",
              sortOrder: 0
            ),
            IngredientLine(
              id: greenOnionID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "1 green onion",
              quantity: 1,
              quantityText: "1",
              item: "green onion",
              sortOrder: 1
            ),
            IngredientLine(
              id: tomatoesID,
              recipeID: secondRecipeID,
              sectionID: secondSectionID,
              originalText: "2 tomatoes",
              quantity: 2,
              quantityText: "2",
              item: "tomatoes",
              sortOrder: 2
            ),
          ],
          now: now,
          in: db
        )

        _ = try GroceryRepository.addRecipe(
          recipeID: firstRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try GroceryRepository.addRecipe(
          recipeID: secondRecipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let rows = try GroceryItemListRequest().fetch(db)
        expectNoDifference(rows.map(\.item.title), ["anchovies", "green onions", "tomatoes"])
        expectNoDifference(rows.map(\.item.quantity), [6, 3, 3].map(Optional.some))
        expectNoDifference(
          rows.map { $0.sources.map(\.ingredientLineID) },
          [
            [anchovyFilletID, anchovyID].map(Optional.some),
            [scallionID, greenOnionID].map(Optional.some),
            [tomatoID, tomatoesID].map(Optional.some),
          ]
        )
      }
    }
  }
}
