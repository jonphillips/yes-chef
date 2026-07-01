import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeCaptureImageHydrationTests {
    @Test
    func captureClientHydratesHeroImageBeforeCommit() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://example.com/recipes/lemon-chicken-with-photo"))
      let heroURL = try #require(URL(string: "https://example.com/images/lemon-chicken.jpg"))
      let imageData = try Self.heroImageData()
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Self.jsonLDRecipe },
        renderHTML: { _ in nil },
        fetchImageData: { url in
          expectNoDifference(url, heroURL)
          return imageData
        }
      )
      let capturedAt = Date(timeIntervalSinceReferenceDate: 804_350_000)

      let capturedDraft = try await client.capture(url: sourceURL, capturedAt: capturedAt)
      let draft = await client.hydrateHeroImage(in: capturedDraft)

      let processedHero = try #require(draft.page.processedImages[heroURL])
      expectNoDifference(processedHero.thumbnailData != nil, true)

      let uuids = LockedSampleUUIDSequence(start: 27_500)
      let result = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: capturedAt,
          uuid: { uuids.next() }
        )
      }

      try await database.read { db in
        let photos = try RecipePhoto.fetchAll(db).filter { $0.recipeID == result.recipeID }
        let hero = try #require(photos.first)
        expectNoDifference(hero.sourceURL, heroURL.absoluteString)
        expectNoDifference(hero.kind, .hero)
        expectNoDifference(hero.displayData != nil, true)
        expectNoDifference(hero.thumbnailData != nil, true)
        expectNoDifference(hero.mediaType, "image/jpeg")
        expectNoDifference(hero.pixelWidth, 1_200)
        expectNoDifference(hero.pixelHeight, 900)
        expectNoDifference(hero.displayData != nil || hero.thumbnailData != nil, true)
      }
    }

    @Test
    func failingHeroImageFetchStillImportsSourceURLOnlyPhoto() async throws {
      let sourceURL = try #require(URL(string: "https://example.com/recipes/lemon-chicken-image-failure"))
      let heroURL = try #require(URL(string: "https://example.com/images/lemon-chicken.jpg"))
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in Self.jsonLDRecipe },
        renderHTML: { _ in nil },
        fetchImageData: { _ in throw URLError(.badServerResponse) }
      )
      let capturedAt = Date(timeIntervalSinceReferenceDate: 804_360_000)

      let capturedDraft = try await client.capture(url: sourceURL, capturedAt: capturedAt)
      let draft = await client.hydrateHeroImage(in: capturedDraft)

      expectNoDifference(draft.page.processedImages, [:])

      var uuids = SampleUUIDSequence(start: 27_600)
      let bundle = try draft.page.makeRecipeBundle(now: capturedAt, uuid: { uuids.next() })
      let hero = try #require(bundle.photos.first)
      expectNoDifference(hero.sourceURL, heroURL.absoluteString)
      expectNoDifference(hero.displayData, nil)
      expectNoDifference(hero.thumbnailData, nil)
    }

    @Test
    func sharePayloadHydratesHeroImageBeforeCommit() async throws {
      @Dependency(\.defaultDatabase) var database
      let sourceURL = try #require(URL(string: "https://example.com/recipes/shared-lemon-chicken-with-photo"))
      let heroURL = try #require(URL(string: "https://example.com/images/lemon-chicken.jpg"))
      let imageData = try Self.heroImageData()
      let client = WebRecipeCaptureClient(
        fetchHTML: { _ in throw WebRecipeCaptureClientError.unimplementedFetch },
        renderHTML: { _ in nil },
        fetchImageData: { url in
          expectNoDifference(url, heroURL)
          return imageData
        }
      )
      let capturedAt = Date(timeIntervalSinceReferenceDate: 804_370_000)

      let capturedDraft = try await client.capture(
        sharePayload: WebRecipeSharePayload(
          sourceURL: sourceURL,
          renderedHTML: Self.jsonLDRecipe
        ),
        capturedAt: capturedAt
      )
      let draft = await client.hydrateHeroImage(in: capturedDraft)

      let uuids = LockedSampleUUIDSequence(start: 27_700)
      let result = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: capturedAt,
          uuid: { uuids.next() }
        )
      }

      try await database.read { db in
        let photos = try RecipePhoto.fetchAll(db).filter { $0.recipeID == result.recipeID }
        let hero = try #require(photos.first)
        expectNoDifference(hero.sourceURL, heroURL.absoluteString)
        expectNoDifference(hero.displayData != nil, true)
        expectNoDifference(hero.thumbnailData != nil, true)
      }
    }

    @Test
    func declaredOversizedHeroImageResponseIsRejectedBeforeReadingBody() throws {
      let url = try #require(URL(string: "https://example.com/images/huge.jpg"))
      let response = URLResponse(
        url: url,
        mimeType: "image/jpeg",
        expectedContentLength: 13,
        textEncodingName: nil
      )

      do {
        try WebRecipeCaptureClient.validateImageContentLength(response, maxBytes: 12)
      } catch let error as WebRecipeCaptureClientError {
        expectNoDifference(error, .imageTooLarge(maxBytes: 12))
        return
      }
      Issue.record("Expected oversized image response to be rejected.")
    }

    private static func heroImageData() throws -> Data {
      try Data(contentsOf: fixtureURL.appendingPathComponent("PaprikaHTML/SanitizedRealExport/Recipes/Images/simple/hero.jpg"))
    }

    private static let jsonLDRecipe = """
      <html><head>
      <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": "Lemon Chicken",
        "image": "https://example.com/images/lemon-chicken.jpg",
        "recipeYield": "Serves 4",
        "recipeIngredient": ["1 1/2 pounds chicken thighs"],
        "recipeInstructions": ["Roast until browned."]
      }
      </script>
      </head><body></body></html>
      """

    private static var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
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
