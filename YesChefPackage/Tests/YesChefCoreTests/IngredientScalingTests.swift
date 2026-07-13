import CustomDump
import Testing
import YesChefCore

struct IngredientScalingTests {
  @Test
  func ingredientParserParsesVulgarFractions() {
    let recipeID = SampleUUIDSequence.uuid(21)
    let sectionID = SampleUUIDSequence.uuid(22)
    var uuids = SampleUUIDSequence(start: 23)

    let lines = IngredientParser.lines(
      from: """
      1 ¼ teaspoon salt
      1¼ teaspoons pepper
      ⅓ cup sugar
      2 tablespoons soy sauce
      """,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { uuids.next() }
    )

    expectNoDifference(lines.map(\.quantity), [1.25, 1.25, 1.0 / 3.0, 2])
    expectNoDifference(lines.map(\.quantityText), ["1 ¼", "1¼", "⅓", "2"])
    expectNoDifference(lines.map(\.unit), ["teaspoon", "teaspoons", "cup", "tablespoons"])
    expectNoDifference(lines.map(\.item), ["salt", "pepper", "sugar", "soy sauce"])
  }

  @Test
  func scalingFormatsCommonFractionsAsMixedNumbers() {
    let recipeID = SampleUUIDSequence.uuid(31)
    let sectionID = SampleUUIDSequence.uuid(32)
    var uuids = SampleUUIDSequence(start: 33)
    let lines = IngredientParser.lines(
      from: """
      1 ¼ teaspoon salt
      1¼ teaspoons pepper
      ⅓ cup sugar
      """,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { uuids.next() }
    )

    expectNoDifference(IngredientScaler.scaledText(for: lines[0], factor: 2), "2 ½ teaspoons salt")
    expectNoDifference(IngredientScaler.scaledText(for: lines[1], factor: 2), "2 ½ teaspoons pepper")
    expectNoDifference(IngredientScaler.scaledText(for: lines[2], factor: 3), "1 cup sugar")
  }

  @Test
  func scalingPreservesAlternateMeasurementsAndPurchaseDetail() {
    let recipeID = SampleUUIDSequence.uuid(41)
    let sectionID = SampleUUIDSequence.uuid(42)
    var uuids = SampleUUIDSequence(start: 43)
    let originalText = "4 lb / 1.8 kg beef, preferably 3 lb chuck roast plus 1 lb boneless short ribs, cut into 2- to 3-inch pieces; trim only hard exterior fat"
    let line = IngredientParser.lines(
      from: originalText,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { uuids.next() }
    )[0]

    expectNoDifference(
      IngredientScaler.scaledText(for: line, factor: 3),
      "12 lbs / 1.8 kg beef, preferably 3 lb chuck roast plus 1 lb boneless short ribs, cut into 2- to 3-inch pieces; trim only hard exterior fat"
    )
  }
}
