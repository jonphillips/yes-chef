import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeMilkStreetCaptureTests {
    @Test
    func domFallbackRecoversTruncatedMetaJSONLD() throws {
      let sourceURL = try #require(URL(string: "https://www.177milkstreet.com/recipes/gochujang-stir-fried-pork-celery"))

      let page = WebRecipePageParser.parse(
        html: try Self.fixtureHTML("milk-street-gochujang"),
        sourceURL: sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_350_000)
      )

      expectNoDifference(page.title, "Gochujang Stir-Fried Pork and Celery")
      expectNoDifference(
        page.ingredientSections,
        [
          ParsedRecipeIngredientSection(
            lines: [
              "1 pound boneless country-style pork spareribs, sliced crosswise 1/4 inch thick",
              "3 tablespoons soy sauce, divided",
              "2 tablespoons neutral oil, divided",
              "1 tablespoon gochujang",
              "1 tablespoon white sugar",
              "2 teaspoons toasted sesame oil",
              "3 medium celery stalks, sliced on the bias",
              "1 small yellow onion, thinly sliced",
              "3 garlic cloves, finely grated",
              "Kosher salt and ground black pepper",
              "1-2 jalapeno chilies, stemmed and sliced",
              "Toasted sesame seeds, to serve",
            ]
          ),
        ]
      )
      expectNoDifference(
        page.instructionSections,
        [
          ParsedRecipeInstructionSection(
            steps: [
              "In a medium bowl, toss the pork with 1 tablespoon soy sauce and 1 tablespoon oil.",
              "In a 12-inch skillet over medium-high, cook the pork until browned, then transfer to a plate.",
              "Add the celery, onion and garlic to the skillet; return the pork and sauce and cook until glossy.",
            ]
          ),
        ]
      )
      expectNoDifference(page.warnings, [])
      expectNoDifference(
        page.ingredientSections.flatMap(\.lines).contains {
          $0.localizedCaseInsensitiveContains("sign up for full access")
        },
        false
      )
    }

    @Test
    func domFallbackRecoversSectionsTipSummaryAndTime() throws {
      let sourceURL = try #require(URL(string: "https://www.177milkstreet.com/recipes/chicken-peanut-red-chili-sauce-pollo-encacahuatado"))

      let page = WebRecipePageParser.parse(
        html: try Self.fixtureHTML("milk-street-chicken-peanut"),
        sourceURL: sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_370_000)
      )
      let expectedTitle = "Chicken with Peanut and Red Chili Sauce (Pollo Encacahuatado)"
      let expectedSummary = [
        "According to Jorge Fritz and Beto Estúa of Casa Jacaranda cooking school in Mexico City,",
        "there is disagreement about whether encacahuatado is a true mole. We'll let the experts decide",
        "and debate, but we can say the dish does have delicious mole-like qualities: nuts and seeds as",
        "the foundation and dried chilies and spices providing layered, complex flavor.",
      ].joined(separator: " ")
      let expectedTip = [
        "Don't worry about salted versus unsalted peanuts in this recipe. Either will work. However,",
        "if your peanuts are extremely high in sodium, don't add any salt at all to the blender.",
      ].joined(separator: " ")

      expectNoDifference(page.title, expectedTitle)
      expectNoDifference(page.summary, expectedSummary)
      expectNoDifference(page.servingsText, "4-6 servings")
      expectNoDifference(page.cookTimeMinutes, 90)
      expectNoDifference(
        page.ingredientSections,
        [
          ParsedRecipeIngredientSection(
            name: "For the chicken and broth",
            lines: [
              "2½ pounds bone-in, skin-on chicken breasts or thighs, skin removed",
              "3 medium garlic cloves, smashed and peeled",
              "Kosher salt and ground black pepper",
            ]
          ),
          ParsedRecipeIngredientSection(
            name: "For the sauce and to serve",
            lines: [
              "¾ cup roasted peanuts, plus chopped peanuts to serve",
              "3 guajillo chilies, stemmed and seeded",
            ]
          ),
        ]
      )
      expectNoDifference(
        page.instructionSections,
        [
          ParsedRecipeInstructionSection(
            steps: [
              "In a large pot, combine the chicken, garlic, onion, bay and oregano with water to cover.",
              "Meanwhile, toast the tomatoes, garlic and chilies until fragrant and lightly charred.",
              "Blend the peanuts, chilies and broth until smooth, then simmer with the chicken.",
            ]
          ),
        ]
      )
      expectNoDifference(
        page.editorialBlocks,
        [
          ParsedRecipeEditorialBlock(
            label: "Tip",
            text: expectedTip
          ),
        ]
      )
      expectNoDifference(page.warnings, [])
    }

    @Test
    func truncatedMetaJSONLDWithoutDOMFallbackStaysUnusable() throws {
      let page = WebRecipePageParser.parse(
        html: try Self.fixtureHTML("milk-street-truncated-json-ld"),
        sourceURL: URL(string: "https://www.177milkstreet.com/recipes/truncated-only"),
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_360_000)
      )

      expectNoDifference(page.isEmpty, true)
      expectNoDifference(WebRecipeCaptureDraft(page: page).isUsable, false)
      expectNoDifference(page.schemaTypes, [])
      expectNoDifference(page.ingredientSections, [])
      expectNoDifference(page.instructionSections, [])
      expectNoDifference(
        page.warnings,
        [.noStructuredRecipeData, .truncatedStructuredData, .untitledRecipe, .noIngredients, .noInstructions]
      )
    }

    private static func fixtureHTML(_ name: String) throws -> String {
      try String(contentsOf: fixtureURL.appendingPathComponent("\(name).html"), encoding: .utf8)
    }

    private static var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/WebRecipeCapture/SanitizedSites", isDirectory: true)
    }
  }
}
