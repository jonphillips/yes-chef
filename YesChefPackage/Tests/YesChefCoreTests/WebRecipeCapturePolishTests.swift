import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeCapturePolishTests {
    @Test
    func incomingSourceURLStripsQueryAndFragmentButCanonicalStaysPreferred() async throws {
      let incomingURL = try #require(URL(string: "https://example.com/recipes/fallback?utm_source=newsletter#comments"))
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

      expectNoDifference(fallbackDraft.page.sourceURL?.absoluteString, "https://example.com/recipes/fallback")
    }

    @Test
    func importIdentityIgnoresTrackingQueryAndFragment() {
      let first = RecipeImportIdentityKey(
        sourceURL: "https://example.com/recipes/tacos?utm_source=newsletter#comments",
        title: "Tacos"
      )
      let second = RecipeImportIdentityKey(
        sourceURL: "https://example.com/recipes/tacos",
        title: "Tacos"
      )

      expectNoDifference(first, second)
      expectNoDifference(first.normalizedSourceURL, "https://example.com/recipes/tacos")
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
