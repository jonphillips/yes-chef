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

    @Test
    func captureClientFetchesParsesAndCommitsRecipe() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://example.com/recipes/lemon-chicken"))
      let capturedAt = Date(timeIntervalSinceReferenceDate: 803_300_000)
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Fixtures.jsonLDRecipe },
        renderHTML: { _ in nil }
      )

      let draft = try await client.capture(url: sourceURL, capturedAt: capturedAt)

      expectNoDifference(draft.page.title, "Lemon Chicken")
      expectNoDifference(draft.usedRenderedFallback, false)

      let uuids = LockedSampleUUIDSequence(start: 23_000)
      let importResult = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: capturedAt,
          uuid: { uuids.next() }
        )
      }

      expectNoDifference(importResult.outcome, .imported)

      try await database.read { db in
        let recipe = try #require(try Recipe.find(importResult.recipeID).fetchOne(db))
        let source = try #require(try RecipeSource.fetchAll(db).first { $0.recipeID == recipe.id })
        expectNoDifference(recipe.title, "Lemon Chicken")
        expectNoDifference(recipe.originalImportText, Fixtures.jsonLDRecipe)
        expectNoDifference(source.url, sourceURL.absoluteString)
      }
    }

    @Test
    func capturingSameURLTwiceIsIdempotent() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://example.com/recipes/idempotent-lemon-chicken"))
      let capturedAt = Date(timeIntervalSinceReferenceDate: 803_400_000)
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Fixtures.jsonLDRecipe },
        renderHTML: { _ in nil }
      )
      let draft = try await client.capture(url: sourceURL, capturedAt: capturedAt)

      let baseline = try await database.read(captureRowCounts)
      let uuids = LockedSampleUUIDSequence(start: 24_000)
      let firstResult = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: capturedAt,
          uuid: { uuids.next() }
        )
      }
      let afterFirst = try await database.read(captureRowCounts)
      let secondResult = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: capturedAt.addingTimeInterval(60),
          uuid: { uuids.next() }
        )
      }
      let afterSecond = try await database.read(captureRowCounts)

      expectNoDifference(firstResult.outcome, .imported)
      expectNoDifference(secondResult.outcome, .alreadyImported)
      expectNoDifference(secondResult.recipeID, firstResult.recipeID)
      expectNoDifference(afterFirst, baseline.adding(recipeDelta: 1, sourceDelta: 1, ingredientSectionDelta: 2, ingredientLineDelta: 4, instructionSectionDelta: 1, instructionStepDelta: 2, photoDelta: 1, importRefDelta: 1))
      expectNoDifference(afterSecond, afterFirst)
    }

    @Test
    func captureClientUsesRenderedFallbackWhenRawFetchParsesToNothing() async throws {
      let sourceURL = try #require(URL(string: "https://example.com/recipes/js-rendered"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Fixtures.barrenShell },
        renderHTML: { _ in Fixtures.jsonLDRecipe }
      )

      let draft = try await client.capture(
        url: sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_500_000)
      )

      expectNoDifference(draft.usedRenderedFallback, true)
      expectNoDifference(draft.page.title, "Lemon Chicken")
      expectNoDifference(draft.page.originalHTML, Fixtures.jsonLDRecipe)
    }

    @Test
    func sharePayloadWithRenderedHTMLDoesNotFetchAgain() async throws {
      let sourceURL = try #require(URL(string: "https://example.com/recipes/shared-lemon-chicken"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in throw WebRecipeCaptureClientError.unimplementedFetch },
        renderHTML: { _ in nil }
      )

      let draft = try await client.capture(
        sharePayload: WebRecipeSharePayload(
          sourceURL: sourceURL,
          renderedHTML: Fixtures.jsonLDRecipe
        ),
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_700_000)
      )

      expectNoDifference(draft.usedRenderedFallback, false)
      expectNoDifference(draft.page.title, "Lemon Chicken")
      expectNoDifference(draft.page.sourceURL?.absoluteString, sourceURL.absoluteString)
      expectNoDifference(draft.page.originalHTML, Fixtures.jsonLDRecipe)
    }

    @Test
    func sharePayloadFallsBackToURLCaptureWhenRenderedHTMLIsMissing() async throws {
      let sourceURL = try #require(URL(string: "https://example.com/recipes/shared-url-only"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { url in
          expectNoDifference(url, sourceURL)
          return Fixtures.jsonLDRecipe
        },
        renderHTML: { _ in nil }
      )

      let draft = try await client.capture(
        sharePayload: WebRecipeSharePayload(sourceURL: sourceURL, renderedHTML: nil),
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_800_000)
      )

      expectNoDifference(draft.page.title, "Lemon Chicken")
      expectNoDifference(draft.page.originalHTML, Fixtures.jsonLDRecipe)
    }

    @Test
    func sharePayloadHTMLPathCommitsWithSameDeltasAsURLPathAndIsIdempotent() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://example.com/recipes/shared-parity"))
      let capturedAt = Date(timeIntervalSinceReferenceDate: 803_900_000)
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Fixtures.jsonLDRecipe },
        renderHTML: { _ in nil }
      )
      let urlDraft = try await client.capture(url: sourceURL, capturedAt: capturedAt)
      let shareDraft = try await client.capture(
        sharePayload: WebRecipeSharePayload(
          sourceURL: sourceURL,
          renderedHTML: Fixtures.jsonLDRecipe
        ),
        capturedAt: capturedAt
      )

      expectNoDifference(shareDraft.page, urlDraft.page)

      let baseline = try await database.read(captureRowCounts)
      let uuids = LockedSampleUUIDSequence(start: 25_000)
      let firstResult = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          shareDraft,
          in: db,
          now: capturedAt,
          uuid: { uuids.next() }
        )
      }
      let afterFirst = try await database.read(captureRowCounts)
      let secondResult = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          shareDraft,
          in: db,
          now: capturedAt.addingTimeInterval(60),
          uuid: { uuids.next() }
        )
      }
      let afterSecond = try await database.read(captureRowCounts)

      expectNoDifference(firstResult.outcome, .imported)
      expectNoDifference(secondResult.outcome, .alreadyImported)
      expectNoDifference(secondResult.recipeID, firstResult.recipeID)
      expectNoDifference(afterFirst, baseline.adding(recipeDelta: 1, sourceDelta: 1, ingredientSectionDelta: 2, ingredientLineDelta: 4, instructionSectionDelta: 1, instructionStepDelta: 2, photoDelta: 1, importRefDelta: 1))
      expectNoDifference(afterSecond, afterFirst)
    }

    @Test
    func sanitizedRealShapeFixturesCaptureAndCommitIdempotently() async throws {
      @Dependency(\.defaultDatabase) var database
      let cases = try SanitizedSiteCase.all()
      let uuids = LockedSampleUUIDSequence(start: 26_000)

      for siteCase in cases {
        let client = WebRecipeCaptureClient(
          fetchHTML: { url in
            expectNoDifference(url, siteCase.sourceURL)
            return siteCase.fetchHTML
          },
          renderHTML: { url in
            expectNoDifference(url, siteCase.sourceURL)
            return siteCase.renderedHTML
          }
        )

        let draft = try await client.capture(
          url: siteCase.sourceURL,
          capturedAt: Date(timeIntervalSinceReferenceDate: 804_000_000)
        )

        expectNoDifference(draft.usedRenderedFallback, siteCase.expectsRenderedFallback)
        expectNoDifference(draft.page.title, siteCase.expectedTitle)
        expectNoDifference(draft.page.ingredientSections.map(\.name), siteCase.expectedIngredientSectionNames)
        expectNoDifference(draft.page.instructionSections.map(\.name), siteCase.expectedInstructionSectionNames)
        expectNoDifference(draft.page.warnings, siteCase.expectedWarnings)

        let before = try await database.read(captureRowCounts)
        let firstResult = try await database.write { db in
          try RecipeRepository.importCapturedRecipe(
            draft,
            in: db,
            now: Date(timeIntervalSinceReferenceDate: 804_100_000),
            uuid: { uuids.next() }
          )
        }
        let afterFirst = try await database.read(captureRowCounts)
        let secondResult = try await database.write { db in
          try RecipeRepository.importCapturedRecipe(
            draft,
            in: db,
            now: Date(timeIntervalSinceReferenceDate: 804_100_060),
            uuid: { uuids.next() }
          )
        }
        let afterSecond = try await database.read(captureRowCounts)

        expectNoDifference(firstResult.outcome, .imported)
        expectNoDifference(secondResult.outcome, .alreadyImported)
        expectNoDifference(secondResult.recipeID, firstResult.recipeID)
        expectNoDifference(afterFirst.recipes, before.recipes + 1)
        expectNoDifference(afterFirst.sources, before.sources + 1)
        expectNoDifference(afterFirst.importRefs, before.importRefs + 1)
        expectNoDifference(afterSecond, afterFirst)

        try await database.read { db in
          let recipe = try #require(try Recipe.find(firstResult.recipeID).fetchOne(db))
          let source = try #require(try RecipeSource.fetchAll(db).first { $0.recipeID == recipe.id })
          expectNoDifference(recipe.title, siteCase.expectedTitle)
          expectNoDifference(recipe.originalImportText, siteCase.expectedOriginalHTML)
          expectNoDifference(source.name, siteCase.expectedSourceName)
          expectNoDifference(source.url, siteCase.sourceURL.absoluteString)
        }
      }
    }

    @Test
    func sanitizedShareHTMLFixtureMatchesURLCapture() async throws {
      let siteCase = try SanitizedSiteCase.seriousEatsJSONLD()
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in siteCase.fetchHTML },
        renderHTML: { _ in nil }
      )

      let urlDraft = try await client.capture(
        url: siteCase.sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_200_000)
      )
      let shareDraft = try await client.capture(
        sharePayload: WebRecipeSharePayload(
          sourceURL: siteCase.sourceURL,
          renderedHTML: siteCase.fetchHTML
        ),
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_200_000)
      )

      expectNoDifference(shareDraft, urlDraft)
    }

    @Test
    func declaredNonUTF8CharsetPreservesOriginalHTMLBytesThroughCommit() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://www.kingarthurbaking.com/recipes/cafe-toast"))
      let html = """
        <!doctype html>
        <html><head>
          <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Recipe",
            "name": "Caf\u{00E9} Breakfast Toast",
            "description": "A Latin-1 encoded fixture.",
            "publisher": { "@type": "Organization", "name": "King Arthur Baking" },
            "recipeYield": "2 servings",
            "recipeIngredient": ["2 slices bread", "1 spoon jam"],
            "recipeInstructions": ["Toast the bread.", "Spread with jam."]
          }
          </script>
        </head><body></body></html>
        """
      let data = try #require(html.data(using: .isoLatin1))
      let response = try #require(HTTPURLResponse(
        url: sourceURL,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "text/html; charset=iso-8859-1"]
      ))
      let decodedHTML = WebRecipeCaptureClient.decodedHTML(data: data, response: response)
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in decodedHTML },
        renderHTML: { _ in nil }
      )

      let draft = try await client.capture(
        url: sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_300_000)
      )
      expectNoDifference(draft.page.title, "Caf\u{00E9} Breakfast Toast")
      expectNoDifference(decodedHTML.data(using: .isoLatin1), data)

      let uuids = LockedSampleUUIDSequence(start: 27_000)
      let result = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: Date(timeIntervalSinceReferenceDate: 804_300_000),
          uuid: { uuids.next() }
        )
      }

      try await database.read { db in
        let recipe = try #require(try Recipe.find(result.recipeID).fetchOne(db))
        expectNoDifference(recipe.title, "Caf\u{00E9} Breakfast Toast")
        expectNoDifference(recipe.originalImportText?.data(using: .isoLatin1), data)
      }
    }

    @Test
    func cancelAfterFetchWritesNothing() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://example.com/recipes/cancelled"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Fixtures.jsonLDRecipe },
        renderHTML: { _ in nil }
      )
      let baseline = try await database.read(captureRowCounts)

      _ = try await client.capture(
        url: sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 803_600_000)
      )

      let afterFetch = try await database.read(captureRowCounts)
      expectNoDifference(afterFetch, baseline)
    }

    private struct CaptureRowCounts: Equatable {
      var recipes: Int
      var sources: Int
      var ingredientSections: Int
      var ingredientLines: Int
      var instructionSections: Int
      var instructionSteps: Int
      var photos: Int
      var importRefs: Int

      func adding(
        recipeDelta: Int,
        sourceDelta: Int,
        ingredientSectionDelta: Int,
        ingredientLineDelta: Int,
        instructionSectionDelta: Int,
        instructionStepDelta: Int,
        photoDelta: Int,
        importRefDelta: Int
      ) -> Self {
        Self(
          recipes: recipes + recipeDelta,
          sources: sources + sourceDelta,
          ingredientSections: ingredientSections + ingredientSectionDelta,
          ingredientLines: ingredientLines + ingredientLineDelta,
          instructionSections: instructionSections + instructionSectionDelta,
          instructionSteps: instructionSteps + instructionStepDelta,
          photos: photos + photoDelta,
          importRefs: importRefs + importRefDelta
        )
      }
    }

    private func captureRowCounts(_ db: Database) throws -> CaptureRowCounts {
      try CaptureRowCounts(
        recipes: Recipe.fetchAll(db).count,
        sources: RecipeSource.fetchAll(db).count,
        ingredientSections: IngredientSection.fetchAll(db).count,
        ingredientLines: IngredientLine.fetchAll(db).count,
        instructionSections: InstructionSection.fetchAll(db).count,
        instructionSteps: InstructionStep.fetchAll(db).count,
        photos: RecipePhoto.fetchAll(db).count,
        importRefs: RecipeImportRef.fetchAll(db).count
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

private struct SanitizedSiteCase {
  var sourceURL: URL
  var fetchHTML: String
  var renderedHTML: String?
  var expectedTitle: String
  var expectedSourceName: String
  var expectedIngredientSectionNames: [String?]
  var expectedInstructionSectionNames: [String?]
  var expectedWarnings: [WebRecipeCaptureWarning]
  var expectsRenderedFallback: Bool

  var expectedOriginalHTML: String {
    renderedHTML ?? fetchHTML
  }

  static func all() throws -> [Self] {
    [
      try seriousEatsJSONLD(),
      try smittenKitchenMicrodata(),
      try kitchnOpenGraph(),
      try kingArthurUnicode(),
      try jsRenderedAllrecipes(),
    ]
  }

  static func seriousEatsJSONLD() throws -> Self {
    Self(
      sourceURL: try #require(URL(string: "https://www.seriouseats.com/crispy-chickpea-bowls")),
      fetchHTML: try fixtureHTML("serious-eats-json-ld"),
      expectedTitle: "Crispy Chickpea Bowls",
      expectedSourceName: "Serious Eats",
      expectedIngredientSectionNames: ["For the chickpeas", "For serving"],
      expectedInstructionSectionNames: ["Roast", "Assemble"],
      expectedWarnings: [],
      expectsRenderedFallback: false
    )
  }

  static func smittenKitchenMicrodata() throws -> Self {
    Self(
      sourceURL: try #require(URL(string: "https://smittenkitchen.com/2026/06/broccoli-cheddar-galette/")),
      fetchHTML: try fixtureHTML("smitten-kitchen-microdata"),
      expectedTitle: "Broccoli Cheddar Galette",
      expectedSourceName: "Smitten Kitchen",
      expectedIngredientSectionNames: ["For the dough", "For the filling"],
      expectedInstructionSectionNames: ["Make the dough", "Bake"],
      expectedWarnings: []
    )
  }

  static func kitchnOpenGraph() throws -> Self {
    Self(
      sourceURL: try #require(URL(string: "https://www.thekitchn.com/freezer-breakfast-burritos")),
      fetchHTML: try fixtureHTML("kitchn-open-graph"),
      expectedTitle: "Freezer Breakfast Burritos",
      expectedSourceName: "The Kitchn",
      expectedIngredientSectionNames: [],
      expectedInstructionSectionNames: [],
      expectedWarnings: [.noStructuredRecipeData, .noIngredients, .noInstructions]
    )
  }

  static func kingArthurUnicode() throws -> Self {
    Self(
      sourceURL: try #require(URL(string: "https://www.kingarthurbaking.com/recipes/almond-breakfast-buns")),
      fetchHTML: try fixtureHTML("king-arthur-unicode-json-ld"),
      expectedTitle: "杏仁 Breakfast Buns",
      expectedSourceName: "King Arthur Baking",
      expectedIngredientSectionNames: [nil],
      expectedInstructionSectionNames: [nil, nil, nil],
      expectedWarnings: []
    )
  }

  static func jsRenderedAllrecipes() throws -> Self {
    Self(
      sourceURL: try #require(URL(string: "https://www.allrecipes.com/skillet-noodles")),
      fetchHTML: try fixtureHTML("js-rendered-shell"),
      renderedHTML: try fixtureHTML("js-rendered-result"),
      expectedTitle: "Skillet Noodles",
      expectedSourceName: "Allrecipes",
      expectedIngredientSectionNames: [nil],
      expectedInstructionSectionNames: [nil, nil],
      expectedWarnings: [],
      expectsRenderedFallback: true
    )
  }

  init(
    sourceURL: URL,
    fetchHTML: String,
    renderedHTML: String? = nil,
    expectedTitle: String,
    expectedSourceName: String,
    expectedIngredientSectionNames: [String?],
    expectedInstructionSectionNames: [String?],
    expectedWarnings: [WebRecipeCaptureWarning],
    expectsRenderedFallback: Bool = false
  ) {
    self.sourceURL = sourceURL
    self.fetchHTML = fetchHTML
    self.renderedHTML = renderedHTML
    self.expectedTitle = expectedTitle
    self.expectedSourceName = expectedSourceName
    self.expectedIngredientSectionNames = expectedIngredientSectionNames
    self.expectedInstructionSectionNames = expectedInstructionSectionNames
    self.expectedWarnings = expectedWarnings
    self.expectsRenderedFallback = expectsRenderedFallback
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

  static let barrenShell = """
    <html><head><title></title></head><body>
    <main><div id="app"></div></main>
    </body></html>
    """
}
