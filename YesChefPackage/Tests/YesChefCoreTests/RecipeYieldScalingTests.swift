import CustomDump
import Testing
import YesChefCore

struct RecipeYieldScalingTests {
  @Test(arguments: [
    ("2½ cups", 2.0, "5 cups"),
    ("2 1/2 cups", 2.0, "5 cups"),
    ("4 servings", 2.0, "8 servings"),
    ("4-6 servings", 2.0, "8–12 servings"),
    ("6", 2.0, "12"),
  ])
  func scalesLeadingYieldQuantity(
    text: String,
    factor: Double,
    expected: String
  ) {
    expectNoDifference(RecipeYieldScaler.scaledText(text, factor: factor), expected)
  }

  @Test
  func leavesYieldWithoutLeadingNumberUnscaled() {
    expectNoDifference(RecipeYieldScaler.scaledText("Makes plenty", factor: 2), "Makes plenty")
  }

  @Test(arguments: [
    ("2½ cups", 2.5),
    ("2 1/2 cups", 2.5),
    ("4 servings", 4.0),
    ("4-6 servings", 4.0),
    ("Serves 4", 4.0),
    ("6", 6.0),
  ])
  func parsesLeadingServingQuantity(text: String, expected: Double) {
    expectNoDifference(ServingParser.servings(from: text), expected)
  }

  @Test
  func doesNotParseServingQuantityWithoutLeadingNumber() {
    expectNoDifference(ServingParser.servings(from: "Makes plenty"), nil)
  }
}
