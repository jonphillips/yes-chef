import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchCompareTests {
    @Test
    func compareAlignsSharedIngredientsOnCanonicalRowsAndBlanksTheRest() {
      let working = makeCompareDetail(
        seed: 30_000,
        title: "Weeknight Birria",
        items: ["chuck roast", "guajillo chiles", "onion"]
      )
      let candidate = makeCompareDetail(
        seed: 31_000,
        title: "Classic Birria",
        items: ["chuck roast", "ancho chiles", "onion", "tomatoes"]
      )

      let comparison = WorkbenchCompare.ingredientComparison(working: working, candidates: [candidate])

      // Working pinned first, candidates follow.
      expectNoDifference(comparison.columns.map(\.role), [.working, .candidate])
      expectNoDifference(comparison.columns.map(\.title), ["Weeknight Birria", "Classic Birria"])
      // Working-recipe order first, then candidate-only keys.
      expectNoDifference(
        comparison.rows.map(\.label),
        ["Chuck roast", "Guajillo chiles", "Onion", "Ancho chiles", "Tomatoes"]
      )
      // Shared ingredient lines up on one row; absence reads as an honest blank.
      expectNoDifference(
        comparison.rows.map(\.cells),
        [
          ["1 chuck roast", "1 chuck roast"],
          ["1 guajillo chiles", nil],
          ["1 onion", "1 onion"],
          [nil, "1 ancho chiles"],
          [nil, "1 tomatoes"],
        ]
      )
      #expect(!comparison.hasOtherLines)
    }

    @Test
    func compareDropsAmbiguousWithinRecipeCollisionsToTheColumnOtherTail() {
      let candidate = makeCompareDetail(
        seed: 32_000,
        title: "Saucy Birria",
        items: ["tomatoes", "crushed tomatoes", "onion"]
      )

      let comparison = WorkbenchCompare.ingredientComparison(working: nil, candidates: [candidate])

      // No working recipe: only the candidate column, unpinned.
      expectNoDifference(comparison.columns.map(\.role), [.candidate])
      // Both tomato lines canonicalize to "tomatoes" — ambiguous, so neither claims the shared row.
      expectNoDifference(comparison.rows.map(\.label), ["Onion"])
      expectNoDifference(comparison.rows.map(\.cells), [["1 onion"]])
      #expect(comparison.hasOtherLines)
      expectNoDifference(comparison.columns[0].otherLines, ["1 tomatoes", "1 crushed tomatoes"])
    }

    @Test
    func compareSkipsIngredientHeaderLines() {
      let working = makeCompareDetail(
        seed: 33_000,
        title: "Birria",
        items: ["chuck roast"],
        headerTexts: ["For the consommé"]
      )

      let comparison = WorkbenchCompare.ingredientComparison(working: working, candidates: [])

      expectNoDifference(comparison.rows.map(\.label), ["Chuck roast"])
      #expect(!comparison.hasOtherLines)
    }

    private func makeCompareDetail(
      seed: Int,
      title: String,
      items: [String],
      headerTexts: [String] = []
    ) -> RecipeDetailData {
      let recipeID = SampleUUIDSequence.uuid(seed)
      let sectionID = SampleUUIDSequence.uuid(seed + 1)
      var sortOrder = 0
      var lines: [IngredientLine] = []
      for headerText in headerTexts {
        lines.append(
          IngredientLine(
            id: SampleUUIDSequence.uuid(seed + 100 + sortOrder),
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: headerText,
            isHeader: true,
            sortOrder: sortOrder
          )
        )
        sortOrder += 1
      }
      for item in items {
        lines.append(
          IngredientLine(
            id: SampleUUIDSequence.uuid(seed + 100 + sortOrder),
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 \(item)",
            item: item,
            sortOrder: sortOrder
          )
        )
        sortOrder += 1
      }
      return RecipeDetailData(
        recipe: Recipe(
          id: recipeID,
          title: title,
          dateCreated: Date(timeIntervalSinceReferenceDate: 0),
          dateModified: Date(timeIntervalSinceReferenceDate: 0)
        ),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        ingredientLines: lines
      )
    }
  }
}
