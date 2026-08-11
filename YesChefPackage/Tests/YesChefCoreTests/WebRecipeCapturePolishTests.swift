import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeCapturePolishTests {
    @Test
    func capturedIngredientPreservesBracketedMetricComment() throws {
      let originalText = "1 cup [140 g] raw whole cashews"
      let page = ParsedRecipePage(
        title: "Cashew Sauce",
        ingredientSections: [ParsedRecipeIngredientSection(lines: [originalText])],
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_250_000)
      )
      var uuids = SampleUUIDSequence(start: 22_500)

      let bundle = try page.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 803_250_000),
        uuid: { uuids.next() }
      )
      let line = try #require(bundle.ingredientLines.first)

      expectNoDifference(line.originalText, originalText)
      expectNoDifference(line.comment, "140 g")
    }

    @Test
    func incomingSourceURLStripsTrackersAndFragmentButCanonicalStaysPreferred() async throws {
      let incomingURL = try #require(
        URL(string: "https://example.com/recipes/fallback?utm_source=newsletter&id=123#comments")
      )
      let canonicalHTML = """
        <html>
          <head>
            <meta property="og:url" content="https://example.com/recipes/canonical?print=true#recipe">
            <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Recipe",
              "name": "Canonical Soup",
              "recipeIngredient": ["1 onion"],
              "recipeInstructions": ["Cook it."]
            }
            </script>
          </head>
        </html>
        """
      let fallbackHTML = """
        <html>
          <head>
            <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Recipe",
              "name": "Fallback Soup",
              "recipeIngredient": ["1 onion"],
              "recipeInstructions": ["Cook it."]
            }
            </script>
          </head>
        </html>
        """
      let client = WebRecipeCaptureClient(
        fetchHTML: { url in
          expectNoDifference(url, incomingURL)
          return canonicalHTML
        },
        renderHTML: { _ in nil }
      )

      let draft = try await client.capture(
        url: incomingURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_750_000)
      )

      expectNoDifference(
        draft.page.sourceURL?.absoluteString,
        "https://example.com/recipes/canonical?print=true#recipe"
      )

      let fallbackDraft = try await client.capture(
        sharePayload: WebRecipeSharePayload(sourceURL: incomingURL, renderedHTML: fallbackHTML),
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_750_100)
      )

      expectNoDifference(fallbackDraft.page.sourceURL?.absoluteString, "https://example.com/recipes/fallback?id=123")
    }

    @Test
    func importIdentityIgnoresKnownTrackingParametersAndFragment() {
      let first = RecipeImportIdentityKey(
        sourceURL: "https://example.com/recipes/tacos?id=123&utm_source=newsletter&fbclid=abc#comments",
        title: "Tacos"
      )
      let second = RecipeImportIdentityKey(
        sourceURL: "https://example.com/recipes/tacos?id=123",
        title: "Tacos"
      )
      let distinctRecipe = RecipeImportIdentityKey(
        sourceURL: "https://example.com/recipes/tacos?id=456",
        title: "Tacos"
      )

      expectNoDifference(first, second)
      #expect(first != distinctRecipe)
      expectNoDifference(first.normalizedSourceURL, "https://example.com/recipes/tacos?id=123")
    }

    @Test
    func captureDraftReviewEditsPersistOnImport() async throws {
      @Dependency(\.defaultDatabase) var database
      let capturedAt = Date(timeIntervalSinceReferenceDate: 803_850_000)
      var draft = WebRecipeCaptureDraft(
        page: ParsedRecipePage(
          sourceURL: URL(string: "https://example.com/recipes/review-edits"),
          title: "Original Title",
          summary: "Original summary.",
          servingsText: "Serves 2",
          totalTimeMinutes: 30,
          ingredientSections: [ParsedRecipeIngredientSection(lines: ["1 onion"])],
          instructionSections: [ParsedRecipeInstructionSection(steps: ["Cook it."])],
          capturedAt: capturedAt
        )
      )
      draft.page.title = "Edited Title"
      draft.page.summary = "Edited summary."
      draft.page.servingsText = "Serves 6"
      draft.page.totalTimeMinutes = 45

      let editedDraft = draft
      let uuids = LockedSampleUUIDSequence(start: 25_500)
      let result = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          editedDraft,
          in: db,
          now: capturedAt,
          uuid: { uuids.next() }
        )
      }

      let recipe = try await database.read { db in
        try #require(try Recipe.find(result.recipeID).fetchOne(db))
      }
      expectNoDifference(recipe.title, "Edited Title")
      expectNoDifference(recipe.summary, "Edited summary.")
      expectNoDifference(recipe.servingsText, "Serves 6")
      expectNoDifference(recipe.totalTimeMinutes, 45)
    }

    @Test
    func multipleCompleteJSONLDRecipesChooseTheMainEntityWithoutBlending() {
      let page = WebRecipePageParser.parse(html: """
        <script type="application/ld+json">
        {"@type":"WebPage","relatedRecipe":{"@type":"Recipe","name":"Nested Recipe","recipeIngredient":["nested ingredient"],"recipeInstructions":["Cook nested."]}}
        </script>
        <script type="application/ld+json">
        {"@type":"WebPage","mainEntity":{"@type":"Recipe","name":"Main Recipe","recipeIngredient":["main ingredient"],"recipeInstructions":["Cook main."]}}
        </script>
        """)

      // `mainEntity` outranks an earlier nested Recipe, so primary selection is not first-seen.
      expectNoDifference(page.title, "Main Recipe")
      expectNoDifference(page.ingredientSections.flatMap(\.lines), ["main ingredient"])
      expectNoDifference(page.instructionSections.flatMap(\.steps), ["Cook main."])
      expectNoDifference(page.warnings, [.multipleRecipeCandidates])
    }

    @Test
    func JSONLDRecipeTeaserIsIgnoredWithoutAMultipleCandidateWarning() {
      let page = WebRecipePageParser.parse(html: """
        <script type="application/ld+json">
        {"@graph":[
          {"@type":"Recipe","name":"Complete Recipe","recipeIngredient":["1 onion"],"recipeInstructions":["Cook the onion."]},
          {"@type":"Recipe","name":"Teaser Recipe","image":"https://example.com/teaser.jpg"}
        ]}
        </script>
        """)

      expectNoDifference(page.title, "Complete Recipe")
      expectNoDifference(page.ingredientSections.flatMap(\.lines), ["1 onion"])
      expectNoDifference(page.warnings, [])
    }

    @Test
    func nestedHowToSectionsFlattenWithAComposedNameAndWarning() {
      let page = WebRecipePageParser.parse(html: """
        <script type="application/ld+json">
        {"@type":"Recipe","name":"Nested Method","recipeIngredient":["1 onion"],"recipeInstructions":[{"@type":"HowToSection","name":"Make dinner","itemListElement":[{"@type":"HowToStep","text":"Heat the pan."},{"@type":"HowToSection","name":"Finish sauce","itemListElement":[{"@type":"HowToStep","text":"Stir in butter."}]}]}]}
        </script>
        """)

      expectNoDifference(
        page.instructionSections,
        [
          ParsedRecipeInstructionSection(name: "Make dinner", steps: ["Heat the pan."]),
          ParsedRecipeInstructionSection(name: "Make dinner — Finish sauce", steps: ["Stir in butter."]),
        ]
      )
      expectNoDifference(page.warnings, [.nestedInstructionSectionsFlattened])
      #expect(!page.instructionSections.flatMap(\.steps).contains("Finish sauce"))
    }

    @Test
    func JSONLDIngredientDedupIsScopedToEachSection() {
      let page = WebRecipePageParser.parse(html: """
        <script type="application/ld+json">
        {"@type":"Recipe","name":"Divided Sugar","yesChef:ingredientSections":[{"name":"Cake","recipeIngredient":["1 cup sugar","1 cup sugar"]},{"name":"Frosting","recipeIngredient":["1 cup sugar"]}],"recipeInstructions":["Bake the cake."]}
        </script>
        """)

      expectNoDifference(
        page.ingredientSections,
        [
          ParsedRecipeIngredientSection(name: "Cake", lines: ["1 cup sugar"]),
          ParsedRecipeIngredientSection(name: "Frosting", lines: ["1 cup sugar"]),
        ]
      )
    }

    private final class LockedSampleUUIDSequence: @unchecked Sendable {
      private let lock = NSLock()
      private var sequence: SampleUUIDSequence

      init(start: Int) {
        self.sequence = SampleUUIDSequence(start: start)
      }

      func next() -> UUID {
        lock.withLock {
          sequence.next()
        }
      }
    }
  }
}
