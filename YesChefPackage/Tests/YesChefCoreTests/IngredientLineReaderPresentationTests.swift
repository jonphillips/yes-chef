import CustomDump
import Foundation
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

  @Test
  func downscaledUnitsKeepTheSplitPresentationForPluralAndAbbreviatedUnits() {
    let lines = parsedLines([
      "2 tablespoons olive oil, divided",
      "2 tbsp olive oil, divided",
    ])

    expectNoDifference(
      lines.map { display($0, factor: 0.5) },
      [
        IngredientLineReaderDisplay(primaryText: "1 tablespoon olive oil", secondaryText: "divided"),
        IngredientLineReaderDisplay(primaryText: "1 tbsp olive oil", secondaryText: "divided"),
      ]
    )
  }

  @Test
  func realIngredientCorpusPreservesReaderScalingInvariants() throws {
    let lines = try realIngredientLines()
    #expect(!lines.isEmpty)
    let factors = [1.0, 2.0, 0.5, 1.0 / 3.0]

    for line in lines where !line.isHeader {
      let identityText = IngredientScaler.scaledText(for: line, factor: 1)
      #expect(identityText == line.originalText, "1× changed '\(line.originalText)' to '\(identityText)'")

      let identityDisplay = IngredientLineReaderPresentation.display(for: line, scaledText: line.originalText)
      let oneXDisplay = IngredientLineReaderPresentation.display(for: line, scaledText: identityText)
      expectNoDifference(oneXDisplay, identityDisplay)

      for factor in factors {
        let scaledText = IngredientScaler.scaledText(for: line, factor: factor)
        let scaledDisplay = IngredientLineReaderPresentation.display(for: line, scaledText: scaledText)

        if identityDisplay != nil {
          #expect(scaledDisplay != nil, "Split reader display disappeared for '\(line.originalText)' at \(factor)×")
        }
        if let scaledDisplay {
          #expect(
            !startsWithTwoAmounts(scaledDisplay.primaryText),
            "Reader display starts with two amounts: '\(scaledDisplay.primaryText)' from '\(line.originalText)' at \(factor)×"
          )
        }
        #expect(
          scaledDisplay?.secondaryText == identityDisplay?.secondaryText,
          "Secondary text changed for '\(line.originalText)' at \(factor)×"
        )
      }
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

  private func realIngredientLines() throws -> [IngredientLine] {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let paprikaRoot = testDirectory.appendingPathComponent("Fixtures/PaprikaHTML", isDirectory: true)
    var uuids = SampleUUIDSequence(start: 96_000)
    var lines: [IngredientLine] = []

    for sampleRecipe in SampleRecipes.all {
      for section in sampleRecipe.ingredientSections {
        lines.append(contentsOf: IngredientParser.lines(
          from: section.text,
          recipeID: sampleRecipe.id ?? uuids.next(),
          sectionID: section.id,
          uuid: { uuids.next() }
        ))
      }
    }

    for exportName in ["SyntheticExport", "SanitizedRealExport"] {
      let export = try PaprikaHTMLImporter.parseExport(
        at: paprikaRoot.appendingPathComponent(exportName, isDirectory: true)
      )
      for recipe in export.recipes {
        lines.append(contentsOf: IngredientParser.lines(
          from: recipe.ingredients.joined(separator: "\n"),
          recipeID: uuids.next(),
          sectionID: uuids.next(),
          uuid: { uuids.next() }
        ))
      }
    }

    let soupPath = testDirectory
      .appendingPathComponent("Fixtures/WebRecipeCapture/SanitizedSites/nyt-comments.html")
    let soupHTML = try String(contentsOf: soupPath, encoding: .utf8)
    let soup = WebRecipePageParser.parse(html: soupHTML)
    lines.append(contentsOf: IngredientParser.lines(
      from: soup.ingredientSections.flatMap(\.lines).joined(separator: "\n"),
      recipeID: uuids.next(),
      sectionID: uuids.next(),
      uuid: { uuids.next() }
    ))

    return lines
  }

  private func startsWithTwoAmounts(_ text: String) -> Bool {
    guard let firstAmount = QuantityParser.leadingQuantity(in: text) else { return false }
    let suffix = text[firstAmount.range.upperBound...]
    let whitespace = suffix.prefix(while: \.isWhitespace)
    guard !whitespace.isEmpty else { return false }
    return QuantityParser.leadingQuantity(in: String(suffix.dropFirst(whitespace.count))) != nil
  }
}
