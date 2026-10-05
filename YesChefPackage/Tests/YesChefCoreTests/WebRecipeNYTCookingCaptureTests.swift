import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeNYTCookingCaptureTests {
    @Test
    func renderedIngredientGroupsMatchTheFlatJSONLDAndAuthorUsesItsName() throws {
      let page = WebRecipePageParser.parse(
        html: try Self.fixtureHTML("nyt-cooking-ingredient-groups"),
        sourceURL: URL(string: "https://cooking.nytimes.com/recipes/1026813-easy-carrot-cake"),
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_400_000)
      )

      expectNoDifference(page.author, "Genevieve Ko")
      expectNoDifference(page.ingredientSections.map(\.name), ["For the cake", "For the frosting"])
      expectNoDifference(page.ingredientSections.map { $0.lines.count }, [15, 4])
      expectNoDifference(page.ingredientSections.flatMap(\.lines).count, 19)
      expectNoDifference(page.tagNames, [
        "Carrot", "Cream Cheese", "Easter", "Easy", "Make-Ahead", "Mother’s Day",
        "Party", "Sheet-Pan", "Sour Cream", "Spring", "Walnut",
      ])
      expectNoDifference(page.categoryNames, ["Carrot Cake", "Dessert"])
    }

    @Test
    func anNYTPageWithoutGroupHeadingsKeepsItsFlatIngredientList() throws {
      let page = WebRecipePageParser.parse(
        html: try Self.fixtureHTML("nyt-comments"),
        sourceURL: URL(string: "https://cooking.nytimes.com/recipes/flat-recipe")
      )

      expectNoDifference(page.ingredientSections.map(\.name), [nil])
      expectNoDifference(page.ingredientSections.flatMap(\.lines).count, 15)
    }

    @Test
    func mismatchedNYTDOMLinesDoNotReplaceTheFlatList() throws {
      let fixture = try Self.fixtureHTML("nyt-cooking-ingredient-groups")
      let shortened = fixture.replacingOccurrences(
        of: "        <li><p class=\"pantry--ui ingredient_ingredient__19\">1 teaspoon vanilla extract</p></li>\n",
        with: ""
      )
      let page = WebRecipePageParser.parse(
        html: shortened,
        sourceURL: URL(string: "https://cooking.nytimes.com/recipes/1026813-easy-carrot-cake")
      )

      expectNoDifference(page.ingredientSections.map(\.name), [nil])
      expectNoDifference(page.ingredientSections.flatMap(\.lines).count, 19)
    }

    @Test
    func JSONLDAuthorUsesOnlyDistinctEntityNames() {
      let cases: [(author: String, expected: String?)] = [
        (#"[{"@type":"Person","name":"A"},{"@type":"Person","name":"B"}]"#, "A and B"),
        (#"[{"@type":"Person","name":"A"},{"@type":"Person","name":"B"},{"@type":"Person","name":"C"}]"#, "A, B, and C"),
        (#"{"@type":"Person","url":"https://example.com/author"}"#, nil),
      ]
      for testCase in cases {
        let html = """
          <script type="application/ld+json">
          {"@type":"Recipe","name":"Soup","author":\(testCase.author),"recipeIngredient":["1 cup water"],"recipeInstructions":["Boil"]}
          </script>
          <meta property="article:author" content="https://example.com/author">
          """
        let page = WebRecipePageParser.parse(html: html)
        expectNoDifference(page.author, testCase.expected)
      }
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
