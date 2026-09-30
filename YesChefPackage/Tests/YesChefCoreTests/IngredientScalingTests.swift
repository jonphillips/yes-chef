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

  @Test
  func scalesLeadingIngredientRangesButNotHyphenatedDimensions() {
    let recipeID = SampleUUIDSequence.uuid(51)
    let sectionID = SampleUUIDSequence.uuid(52)
    var uuids = SampleUUIDSequence(start: 53)
    let lines = IngredientParser.lines(
      from: """
      8-10 ounces kale
      8–10 oz spinach
      8 to 10 ounces chard
      8 - 10 ounces collards
      1½-2 cups flour
      2-3-inch pieces ginger
      1-inch piece ginger
      """,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { uuids.next() }
    )

    expectNoDifference(
      lines.map { IngredientScaler.scaledText(for: $0, factor: 2) },
      [
        "16–20 ounces kale",
        "16–20 oz spinach",
        "16–20 ounces chard",
        "16–20 ounces collards",
        "3–4 cups flour",
        "2-3-inch pieces ginger",
        "1-inch piece ginger",
      ]
    )
    expectNoDifference(IngredientScaler.scaledText(for: lines[0], factor: 0.5), "4–5 ounces kale")
    expectNoDifference(IngredientScaler.scaledText(for: lines[0], factor: 1), "8-10 ounces kale")
  }

  @Test
  func rangeParsingStoresUpperBoundAndLeavesUnitAndItemReadable() {
    let cases: [(String, Double, String, String?, String?)] = [
      ("8-10 ounces kale", 10, "8-10", "ounces", "kale"),
      ("8–10 oz spinach", 10, "8–10", "oz", "spinach"),
      ("8 to 10 ounces kale", 10, "8 to 10", "ounces", "kale"),
      ("8 - 10 ounces chard", 10, "8 - 10", "ounces", "chard"),
      ("1½-2 cups flour", 2, "1½-2", "cups", "flour"),
    ]

    for (text, quantity, quantityText, unit, item) in cases {
      let parsed = IngredientParser.parse(text)
      expectNoDifference(parsed.quantity, quantity)
      expectNoDifference(parsed.quantityText, quantityText)
      expectNoDifference(parsed.unit, unit)
      expectNoDifference(parsed.item, item)
    }
  }
}
