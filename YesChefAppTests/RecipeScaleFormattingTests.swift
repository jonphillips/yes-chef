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
}
