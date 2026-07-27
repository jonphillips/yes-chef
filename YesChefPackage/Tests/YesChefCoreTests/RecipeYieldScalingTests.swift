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

  /// The number is routinely preceded by a word, and every one of these used to scale to nothing at
  /// all — silently, while "4–6 servings" worked — because the scaler anchored at the start of the
  /// string. The recipe's own phrasing is kept; only the number moves.
  @Test(arguments: [
    ("Serves 2", 3.0, "Serves 6"),
    ("Serves 2 to 4", 3.0, "Serves 6–12"),
    ("Serves 4-6", 0.5, "Serves 2–3"),
    ("Yield: 6", 0.5, "Yield: 3"),
    ("Makes 4 dozen cookies", 2.0, "Makes 8 dozen cookies"),
  ])
  func scalesYieldQuantityThatFollowsAWord(
    text: String,
    factor: Double,
    expected: String
  ) {
    expectNoDifference(RecipeYieldScaler.scaledText(text, factor: factor), expected)
  }

  @Test
  func leavesYieldWithNoNumberAtAllUnscaled() {
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
