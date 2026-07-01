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
