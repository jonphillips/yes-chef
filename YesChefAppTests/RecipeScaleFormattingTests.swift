import Testing
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

  @Test
  func scaledServingsSummaryPreservesSourceRanges() {
    #expect(
      ScaleText.scaledServingsSummary(
        servingsText: "Serves 2 to 4",
        baseServings: 2,
        factor: 3
      ) == "6–12 servings"
    )
    #expect(
      ScaleText.scaledServingsSummary(
        servingsText: "4–6 servings",
        baseServings: 4,
        factor: 0.5
      ) == "2–3 servings"
    )
  }

  @Test
  func scaledServingsSummaryFallsBackToStoredServings() {
    #expect(
      ScaleText.scaledServingsSummary(
        servingsText: "Serves 2",
        baseServings: 2,
        factor: 3
      ) == "6 servings"
    )
  }
}
