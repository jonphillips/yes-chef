import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeBrowserCaptureTests {
    @Test
    func browserCaptureParsesRenderedLoggedInRecipeDOM() throws {
      let sourceURL = try #require(URL(string: "https://cooking.nytimes.com/recipes/1020000-ginger-scallion-rice-bowl"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in "" },
        renderHTML: { _ in nil }
      )

      let draft = client.browserCapture(
        html: try BrowserCaptureFixtures.nytCookingRendered(),
        sourceURL: sourceURL,
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_250_000)
      )

      expectNoDifference(draft.isUsable, true)
      expectNoDifference(draft.capturedInBrowser, true)
      expectNoDifference(draft.usedRenderedFallback, false)
      expectNoDifference(draft.page.sourceURL?.absoluteString, sourceURL.absoluteString)
      expectNoDifference(draft.page.title, "Ginger Scallion Rice Bowl")
      expectNoDifference(draft.page.publisherName, "NYT Cooking")
      expectNoDifference(draft.page.ingredientSections.map(\.name), ["For the sauce", "For serving"])
      expectNoDifference(
        draft.page.ingredientSections.flatMap(\.lines),
        [
          "3 scallions, thinly sliced",
          "1 tablespoon grated ginger",
          "2 tablespoons neutral oil",
          "4 cups cooked rice",
          "1 cucumber, sliced",
        ]
      )
      expectNoDifference(draft.page.instructionSections.map(\.name), ["Make the sauce", "Assemble"])
      expectNoDifference(
        draft.page.instructionSections.flatMap(\.steps),
        [
          "Stir together scallions, ginger and oil.",
          "Spoon rice into bowls.",
          "Top with sauce and cucumber.",
        ]
      )
      expectNoDifference(draft.page.warnings, [])
    }

    @Test
    func browserCaptureTeaserPageIsNotUsable() throws {
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in "" },
        renderHTML: { _ in nil }
      )

      let draft = client.browserCapture(
        html: try BrowserCaptureFixtures.nytCookingTeaser(),
        sourceURL: URL(string: "https://cooking.nytimes.com/recipes/1020000-ginger-scallion-rice-bowl"),
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_260_000)
      )

      expectNoDifference(draft.capturedInBrowser, true)
      expectNoDifference(draft.isUsable, false)
      expectNoDifference(
        draft.page.warnings,
        [.noStructuredRecipeData, .untitledRecipe, .noIngredients, .noInstructions]
      )
    }

    @Test
    func browserCaptureKeepsPasteURLImportIdentity() async throws {
      let sourceURL = try #require(URL(string: "https://cooking.nytimes.com/recipes/1020000-ginger-scallion-rice-bowl"))
      let html = try BrowserCaptureFixtures.nytCookingRendered()
      let client = WebRecipeCaptureClient(
        fetchHTML: { url in
          expectNoDifference(url, sourceURL)
          return html
        },
        renderHTML: { _ in nil }
      )
      let capturedAt = Date(timeIntervalSinceReferenceDate: 804_270_000)

      let browserDraft = client.browserCapture(
        html: html,
        sourceURL: sourceURL,
        capturedAt: capturedAt
      )
      let urlDraft = try await client.capture(url: sourceURL, capturedAt: capturedAt)

      var browserUUIDs = SampleUUIDSequence(start: 28_000)
      var urlUUIDs = SampleUUIDSequence(start: 29_000)
      let browserBundle = try browserDraft.page.makeRecipeBundle(now: capturedAt, uuid: { browserUUIDs.next() })
      let urlBundle = try urlDraft.page.makeRecipeBundle(now: capturedAt, uuid: { urlUUIDs.next() })
      let browserKey = RecipeImportIdentityKey(
        sourceURL: browserBundle.source?.url,
        title: browserBundle.recipe.title
      )
      let urlKey = RecipeImportIdentityKey(
        sourceURL: urlBundle.source?.url,
        title: urlBundle.recipe.title
      )

      expectNoDifference(browserDraft.capturedInBrowser, true)
      expectNoDifference(urlDraft.capturedInBrowser, false)
      expectNoDifference(browserKey, urlKey)
      expectNoDifference(browserKey.isTitleOnly, false)
      expectNoDifference(browserKey.normalizedSourceURL, sourceURL.absoluteString)
      expectNoDifference(browserKey.normalizedTitle, "ginger scallion rice bowl")
    }
  }
}

private enum BrowserCaptureFixtures {
  static func nytCookingRendered() throws -> String {
    try fixtureHTML("nyt-cooking-rendered")
  }

  static func nytCookingTeaser() throws -> String {
    try fixtureHTML("nyt-cooking-teaser")
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
