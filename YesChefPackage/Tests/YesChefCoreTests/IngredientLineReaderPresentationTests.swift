import CustomDump
import Testing
import YesChefCore

struct IngredientLineReaderPresentationTests {
  @Test
  func unitlessAmountsComeFromScaledTextAndKeepPreparationSeparate() {
    let lines = parsedLines([
      "1 large onion, diced",
      "3 garlic cloves, minced",
      "2-3 carrots",
    ])

    expectNoDifference(
      display(lines[0], factor: 2),
      IngredientLineReaderDisplay(primaryText: "2 large onion", secondaryText: "diced")
    )
    expectNoDifference(
      display(lines[1], factor: 2),
      IngredientLineReaderDisplay(primaryText: "6 garlic cloves", secondaryText: "minced")
    )
    expectNoDifference(
      display(lines[2], factor: 2),
      IngredientLineReaderDisplay(primaryText: "4–6 carrots")
    )
  }

  @Test
  func unitlessAmountsAtScaleOneRemainUnchanged() {
    let lines = parsedLines([
      "1 large onion, diced",
      "3 garlic cloves, minced",
      "2-3 carrots",
    ])

    expectNoDifference(
      lines.map { display($0, factor: 1) },
      [
        IngredientLineReaderDisplay(primaryText: "1 large onion", secondaryText: "diced"),
        IngredientLineReaderDisplay(primaryText: "3 garlic cloves", secondaryText: "minced"),
        IngredientLineReaderDisplay(primaryText: "2-3 carrots"),
      ]
    )
  }

  @Test
  func dimensionMeasurementsStayPartOfTheItem() {
    let lines = parsedLines([
      "1-inch piece fresh ginger, peeled",
      "2-3-inch pieces ginger",
    ])
    expectNoDifference(lines.map(\.quantity), [nil, nil])

    for factor in [1.0, 2.0] {
      expectNoDifference(
        lines.map { display($0, factor: factor) },
        [
          IngredientLineReaderDisplay(primaryText: "1-inch piece fresh ginger", secondaryText: "peeled"),
          IngredientLineReaderDisplay(primaryText: "2-3-inch pieces ginger"),
        ]
      )
    }
  }

  private func display(_ line: IngredientLine, factor: Double) -> IngredientLineReaderDisplay? {
    IngredientLineReaderPresentation.display(
      for: line,
      scaledText: IngredientScaler.scaledText(for: line, factor: factor)
    )
  }

  private func parsedLines(_ texts: [String]) -> [IngredientLine] {
    var uuids = SampleUUIDSequence(start: 95_000)
    return texts.flatMap { text in
      IngredientParser.lines(
        from: text,
        recipeID: SampleUUIDSequence.uuid(95_100),
        sectionID: SampleUUIDSequence.uuid(95_101),
        uuid: { uuids.next() }
      )
    }
  }
}
