import CustomDump
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct IngredientSectionHeadingTests {
    @Test
    func ingredientRangesRemainIngredientsWhenCheckingSectionHeadings() {
      expectNoDifference(
        IngredientSectionHeading.sections(in: ["8-10 ounces kale:", "SAUCE", "1 cup stock"]),
        [
          .init(name: nil, lines: ["8-10 ounces kale:"]),
          .init(name: "SAUCE", lines: ["1 cup stock"]),
        ]
      )
    }
  }
}
