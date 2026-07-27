import Testing
import YesChefCore
@testable import YesChef

@Suite
struct RecipeScaleFormattingTests {
  @Test
  func ingredientInputCasesUseTheFullAuthoringSet() {
    #expect(
      ScaleFraction.ingredientInputCases.map(\.label) == [
        "¼", "½", "¾", "⅓", "⅔", "⅛", "⅜", "⅝", "⅞",
      ]
    )
  }

  @Test
  func appendingFractionLeavesExistingTextUntouched() {
    #expect(ScaleFraction.appending(.oneHalf, to: "1 ") == "1 ½")
    #expect(ScaleFraction.appending(.threeEighths, to: "") == "⅜")
  }

  // These two expectations were written on 2026-07-12 against
  // `ScaleText.scaledServingsSummary(servingsText:baseServings:factor:)`, which normalised every
  // yield to "N servings" and fell back to a stored `baseServings`. On 2026-07-16 production moved
  // to `RecipeYieldScaler.scaledText`, which instead keeps the recipe's own phrasing; on 2026-07-18
  // the call sites here were swapped to the new API and the expected strings were left behind.
  // Nothing ran the target, so the mismatch sat for nine days. Re-baselined to the current contract.
  //
  // `RecipeYieldScaler` is Core, and `RecipeYieldScalingTests` in YesChefCoreTests now covers these
  // cases and more in the fast loop. These two are redundant and belong in the app-layer→Core sweep.
  @Test
  func scaledServingsSummaryPreservesSourceRanges() {
    #expect(
      RecipeYieldScaler.scaledText("Serves 2 to 4", factor: 3) == "Serves 6–12"
    )
    #expect(
      RecipeYieldScaler.scaledText("4–6 servings", factor: 0.5) == "2–3 servings"
    )
  }

  @Test
  func scaledServingsSummaryKeepsThePhrasingAroundTheNumber() {
    #expect(
      RecipeYieldScaler.scaledText("Serves 2", factor: 3) == "Serves 6"
    )
  }
}
