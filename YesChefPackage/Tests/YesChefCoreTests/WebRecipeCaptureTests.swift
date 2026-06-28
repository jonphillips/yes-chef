import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeCaptureTests {
    @Test
    func jsonLDRecipePageProjectsToRecipeBundle() throws {
      let page = WebRecipePageParser.parse(
        html: Fixtures.jsonLDRecipe,
        sourceURL: URL(string: "https://example.com/recipes/lemon-chicken"),
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_000_000)
      )

      expectNoDifference(page.title, "Lemon Chicken")
      expectNoDifference(page.summary, "A bright weeknight chicken dinner.")
      expectNoDifference(page.author, "Jamie Example")
      expectNoDifference(page.publisherName, "Example Kitchen")
      expectNoDifference(page.servingsText, "Serves 4")
      expectNoDifference(page.prepTimeMinutes, 15)
      expectNoDifference(page.cookTimeMinutes, 40)
      expectNoDifference(page.totalTimeMinutes, 55)
      expectNoDifference(page.rating, 5)
      expectNoDifference(page.categoryNames, ["Dinner", "Chicken"])
      expectNoDifference(
        page.ingredientSections,
        [
          ParsedRecipeIngredientSection(
            name: "For the chicken",
            lines: [
              "1 1/2 pounds chicken thighs",
              "2 tablespoons olive oil",
            ]
          ),
          ParsedRecipeIngredientSection(
            name: "SAUCE",
            lines: [
              "1 lemon, juiced",
              "Kosher salt, to taste",
            ]
          ),
        ]
      )
      expectNoDifference(
        page.instructionSections,
        [
          ParsedRecipeInstructionSection(
            name: "Cook",
            steps: [
              "Season the chicken.",
              "Roast until browned.",
            ]
          ),
        ]
      )
      expectNoDifference(
        page.imageURLs.map(\.absoluteString),
        ["https://example.com/images/lemon-chicken.jpg"]
      )
      expectNoDifference(page.originalHTML.contains("application/ld+json"), true)
      expectNoDifference(page.warnings, [])

      var uuids = SampleUUIDSequence(start: 21_000)
      let now = Date(timeIntervalSinceReferenceDate: 803_100_000)
      let bundle = try page.makeRecipeBundle(now: now, uuid: { uuids.next() })

      expectNoDifference(bundle.recipe.title, "Lemon Chicken")
      expectNoDifference(bundle.recipe.summary, "A bright weeknight chicken dinner.")
      expectNoDifference(bundle.recipe.servings, 4)
      expectNoDifference(bundle.recipe.prepTimeMinutes, 15)
      expectNoDifference(bundle.recipe.cookTimeMinutes, 40)
      expectNoDifference(bundle.recipe.totalTimeMinutes, 55)
      expectNoDifference(bundle.recipe.rating, 5)
      expectNoDifference(bundle.recipe.originalImportText?.contains("Lemon Chicken"), true)
      expectNoDifference(bundle.source?.name, "Example Kitchen")
      expectNoDifference(bundle.source?.url, "https://example.com/recipes/lemon-chicken")
      expectNoDifference(bundle.source?.author, "Jamie Example")
      expectNoDifference(bundle.source?.importedFrom, "Web Recipe Capture")
      expectNoDifference(bundle.ingredientSections.map(\.name), ["For the chicken", "SAUCE"])
      expectNoDifference(
        bundle.ingredients,
        [
          "1 1/2 pounds chicken thighs",
          "2 tablespoons olive oil",
          "1 lemon, juiced",
          "Kosher salt, to taste",
        ]
      )
      expectNoDifference(bundle.ingredientLines.map(\.sortOrder), [0, 1, 2, 3])
      expectNoDifference(bundle.instructionSections.map(\.name), ["Cook"])
      expectNoDifference(bundle.instructions, ["Season the chicken.", "Roast until browned."])
      expectNoDifference(bundle.photos.map(\.sourceURL), ["https://example.com/images/lemon-chicken.jpg"])
      expectNoDifference(bundle.photos.map(\.kind), [.hero])
      expectNoDifference(bundle.photos.map(\.source), [.extracted])

      let snapshotData = try #require(bundle.recipe.originalSnapshot)
      let snapshot = try RecipeBundleCoding.decodeSnapshot(snapshotData)
      expectNoDifference(snapshot.recipe.title, "Lemon Chicken")
      expectNoDifference(snapshot.ingredients, bundle.ingredients)
      expectNoDifference(snapshot.photos.map(\.sourceURL), ["https://example.com/images/lemon-chicken.jpg"])
    }

    @Test
    func microdataRecipePageParsesRecipeVocabulary() {
      let page = WebRecipePageParser.parse(
        html: Fixtures.microdataRecipe,
        sourceURL: URL(string: "https://example.com/recipes/beans")
      )

      expectNoDifference(page.title, "Brothy Beans")
      expectNoDifference(page.summary, "Beans with herbs.")
      expectNoDifference(page.servingsText, "6 servings")
      expectNoDifference(page.prepTimeMinutes, 10)
      expectNoDifference(page.cookTimeMinutes, 90)
      expectNoDifference(page.categoryNames, ["Beans", "Dinner"])
      expectNoDifference(page.ingredientSections.map(\.name), [nil])
      expectNoDifference(page.ingredientSections.flatMap(\.lines), ["1 pound dried beans", "Water"])
      expectNoDifference(page.instructionSections.flatMap(\.steps), ["Soak the beans.", "Simmer until tender."])
      expectNoDifference(page.rating, 4)
      expectNoDifference(page.warnings, [])
    }

    @Test
    func openGraphFallbackProvidesReviewableShellWithoutStructuredRecipeData() {
      let page = WebRecipePageParser.parse(
        html: Fixtures.openGraphOnly,
        sourceURL: URL(string: "https://example.com/story")
      )

      expectNoDifference(page.title, "Chocolate Tart")
      expectNoDifference(page.summary, "A tart from the archive.")
      expectNoDifference(page.author, "Example Staff")
      expectNoDifference(page.imageURLs.map(\.absoluteString), ["https://example.com/tart.jpg"])
      expectNoDifference(
        page.warnings,
        [.noStructuredRecipeData, .noIngredients, .noInstructions]
      )
      expectNoDifference(page.isEmpty, false)
    }

    @Test
    func barrenPageIsEmptyButKeepsRawHTMLAndCleanedText() {
      let html = """
        <html><head><title></title></head><body>
        <nav><a href="/a">A</a><a href="/b">B</a><a href="/c">C</a><a href="/d">D</a></nav>
        <main><p>This page has prose but no recipe structure.</p></main>
        </body></html>
        """

      let page = WebRecipePageParser.parse(html: html)

      expectNoDifference(page.isEmpty, true)
      expectNoDifference(page.originalHTML, html)
      expectNoDifference(page.bodyText, "This page has prose but no recipe structure.")
      expectNoDifference(
        page.warnings,
        [.noStructuredRecipeData, .untitledRecipe, .noIngredients, .noInstructions]
      )
    }

    @Test
    func jsonLDPreservesApostrophesAndAppliesPublicationMap() throws {
      let page = WebRecipePageParser.parse(
        html: Fixtures.jsonLDApostrophe,
        sourceURL: URL(string: "https://www.cooksillustrated.com/recipes/grandmas-pie")
      )

      // Well-formed JSON-LD content keeps its typographic apostrophe and curly quotes
      // (regression: the smart-quote salvage must not run on a clean parse).
      expectNoDifference(page.title, "Grandma\u{2019}s Apple Pie")
      expectNoDifference(page.summary, "She called it \u{201C}the best.\u{201D}")
      expectNoDifference(page.warnings, [])

      var uuids = SampleUUIDSequence(start: 22_000)
      let now = Date(timeIntervalSinceReferenceDate: 803_200_000)
      let bundle = try page.makeRecipeBundle(now: now, uuid: { uuids.next() })

      expectNoDifference(bundle.recipe.title, "Grandma\u{2019}s Apple Pie")
      // The shared publication map turns the bare host into a clean name.
      expectNoDifference(bundle.source?.name, "Cook's Illustrated")
    }

    private enum Fixtures {
      static let jsonLDApostrophe = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Grandma\u{2019}s Apple Pie",
          "description": "She called it \u{201C}the best.\u{201D}",
          "recipeIngredient": ["2 apples", "1 pie crust"],
          "recipeInstructions": "Bake it."
        }
        </script>
        </head><body></body></html>
        """

      static let jsonLDRecipe = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Lemon Chicken",
          "description": "A bright weeknight chicken dinner.",
          "author": { "@type": "Person", "name": "Jamie Example" },
          "publisher": { "@type": "Organization", "name": "Example Kitchen" },
          "image": "https://example.com/images/lemon-chicken.jpg",
          "recipeYield": "Serves 4",
          "prepTime": "PT15M",
          "cookTime": "PT40M",
          "totalTime": "PT55M",
          "recipeCategory": ["Dinner", "Chicken"],
          "aggregateRating": { "@type": "AggregateRating", "ratingValue": "4.6" },
          "recipeIngredient": [
            "For the chicken:",
            "1 1/2 pounds chicken thighs",
            "2 tablespoons olive oil",
            "SAUCE",
            "1 lemon, juiced",
            "Kosher salt, to taste"
          ],
          "recipeInstructions": [
            {
              "@type": "HowToSection",
              "name": "Cook",
              "itemListElement": [
                { "@type": "HowToStep", "text": "Season the chicken." },
                { "@type": "HowToStep", "text": "Roast until browned." }
              ]
            }
          ]
        }
        </script>
        <meta property="og:title" content="Lemon Chicken | Example Kitchen">
        </head><body><main><p>Recipe body.</p></main></body></html>
        """

      static let microdataRecipe = """
        <html><body>
        <article itemscope itemtype="https://schema.org/Recipe">
          <h1 itemprop="name">Brothy Beans</h1>
          <p itemprop="description">Beans with herbs.</p>
          <span itemprop="recipeYield">6 servings</span>
          <time itemprop="prepTime" datetime="PT10M">10 minutes</time>
          <time itemprop="cookTime" datetime="PT1H30M">1 hour 30 minutes</time>
          <span itemprop="recipeCategory">Beans, Dinner</span>
          <div itemprop="aggregateRating" value="4"></div>
          <ul>
            <li itemprop="recipeIngredient">1 pound dried beans</li>
            <li itemprop="recipeIngredient">Water</li>
          </ul>
          <ol itemprop="recipeInstructions">
            <li>Soak the beans.</li>
            <li>Simmer until tender.</li>
          </ol>
        </article>
        </body></html>
        """

      static let openGraphOnly = """
        <html><head>
          <title>Chocolate Tart | Example</title>
          <meta property="og:title" content="Chocolate Tart">
          <meta property="og:description" content="A tart from the archive.">
          <meta property="og:image" content="https://example.com/tart.jpg">
          <meta name="author" content="Example Staff">
        </head><body></body></html>
        """
    }
  }
}
