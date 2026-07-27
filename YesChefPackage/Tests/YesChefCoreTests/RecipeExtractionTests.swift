import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeExtractionTests {
    @Test
    func structuredSerializerPreservesSaminRecipeBoundaries() throws {
      let html = try Fixture.saminMeatballs()

      let text = try #require(RecipeStructuredTextSerializer.serialize(html: html))

      #expect(text.contains("## For the Sour Cream & Sumac Sauce"))
      #expect(text.contains("- 1 cup sour cream"))
      #expect(text.contains("## For the Turkey and Zucchini Meatballs"))
      #expect(text.contains("- 1 pound ground turkey"))
      #expect(text.contains("## Make the sour cream sauce"))
      #expect(text.contains("1. Stir the sour cream and sumac together."))
      #expect(text.contains("## Shape the meatballs"))
      #expect(text.contains("## Cook the meatballs"))
    }

    @Test
    func browserCaptureEscalatesTheSaminPageThroughTheModel() async throws {
      let recorder = RecipeExtractionRequestRecorder()
      let client = captureClient()
      let draft = client.browserCapture(
        html: try Fixture.saminMeatballs(),
        sourceURL: URL(string: "https://ciaosamin.substack.com/p/yotams-turkey-and-zucchini-meatballs"),
        capturedAt: .init(timeIntervalSinceReferenceDate: 900_000_000)
      )

      let (escalated, rerun) = try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: Self.saminExtractionJSON)
        }
        $0.recipeExtractionClient = .liveValue
      } operation: {
        let escalated = try await client.escalate(draft: draft)
        return (escalated, try await client.reextract(draft: escalated))
      }

      expectNoDifference(escalated.page.ingredientSections, [
        .init(name: "For the Sour Cream & Sumac Sauce", lines: ["1 cup sour cream", "1 teaspoon ground sumac"]),
        .init(name: "For the Turkey and Zucchini Meatballs", lines: ["1 pound ground turkey", "1 zucchini, grated"]),
      ])
      expectNoDifference(escalated.page.instructionSections, [
        .init(name: "Make the sour cream sauce", steps: ["Stir the sour cream and sumac together."]),
        .init(name: "Shape the meatballs", steps: ["Combine the turkey and zucchini, then form meatballs."]),
        .init(name: "Cook the meatballs", steps: ["Cook the meatballs until browned and cooked through."]),
      ])
      expectNoDifference(escalated.page.modelExtractedIngredientSections, escalated.page.ingredientSections)
      expectNoDifference(escalated.page.modelExtractedInstructionSections, escalated.page.instructionSections)
      expectNoDifference(rerun.page.ingredientSections, escalated.page.ingredientSections)

      let request = await recorder.first()
      let requestCount = await recorder.count
      expectNoDifference(request?.tier, .frontierPreferred)
      expectNoDifference(request?.reasoningEffort, .high)
      expectNoDifference(request?.maxTokens, RecipeExtractionClient.maxTokens)
      #expect(request?.messages.first?.text.contains("## For the Sour Cream & Sumac Sauce") == true)
      expectNoDifference(requestCount, 2)
    }

    @Test
    func contractBearingPageNeverInvokesTheModel() async throws {
      let client = captureClient()
      let page = WebRecipePageParser.parse(html: Fixture.jsonLDRecipe)
      let draft = WebRecipeCaptureDraft(page: page)

      let escalated = try await withDependencies {
        $0.recipeExtractionClient = RecipeExtractionClient { _ in
          Issue.record("Contract-bearing pages must not reach recipe extraction.")
          return RecipeExtraction()
        }
      } operation: {
        try await client.escalate(draft: draft)
      }

      expectNoDifference(escalated, draft)
    }

    @Test
    func deterministicIngredientsSurviveAModelInstructionMerge() async throws {
      let client = captureClient()
      let html = """
        <article itemscope itemtype="https://schema.org/Recipe">
          <h1 itemprop="name">Partial Beans</h1>
          <ul><li itemprop="recipeIngredient">1 pound dried beans</li><li itemprop="recipeIngredient">Water</li></ul>
        </article>
        """
      let draft = client.browserCapture(html: html, sourceURL: nil, capturedAt: .init(timeIntervalSinceReferenceDate: 900_100_000))

      let escalated = try await withDependencies {
        $0.recipeExtractionClient = RecipeExtractionClient { _ in
          RecipeExtraction(
            title: "Model Beans",
            ingredientSections: [.init(name: "Beans", lines: ["1 pound dried beans", "Water"])],
            instructionSections: [.init(name: "Cook", steps: ["Soak the beans.", "Simmer until tender."])]
          )
        }
      } operation: {
        try await client.escalate(draft: draft)
      }

      expectNoDifference(escalated.page.title, "Partial Beans")
      expectNoDifference(escalated.page.ingredientSections.flatMap(\.lines), ["1 pound dried beans", "Water"])
      expectNoDifference(escalated.page.instructionSections, [
        .init(name: "Cook", steps: ["Soak the beans.", "Simmer until tender."]),
      ])
    }

    @Test
    func truncatedModelResponseFailsLoudly() async throws {
      let client = captureClient()
      let draft = client.browserCapture(html: try Fixture.saminMeatballs(), sourceURL: nil, capturedAt: .now)

      await #expect(throws: RecipeExtractionError.responseTruncated) {
        try await withDependencies {
          $0.modelClient = StubModelClient { _ in ModelResponse(text: "{", stopReason: "max_tokens") }
          $0.recipeExtractionClient = .liveValue
        } operation: {
          try await client.escalate(draft: draft)
        }
      }
    }

    private static let saminExtractionJSON = """
      {
        "title":"Yotam's Turkey & Zucchini Meatballs",
        "summary":null,
        "author":null,
        "publisherName":null,
        "servingsText":null,
        "prepTime":null,
        "cookTime":null,
        "totalTime":null,
        "ingredientSections":[
          {"name":"For the Sour Cream & Sumac Sauce","lines":["1 cup sour cream","1 teaspoon ground sumac"]},
          {"name":"For the Turkey and Zucchini Meatballs","lines":["1 pound ground turkey","1 zucchini, grated"]}
        ],
        "instructionSections":[
          {"name":"Make the sour cream sauce","steps":["Stir the sour cream and sumac together."]},
          {"name":"Shape the meatballs","steps":["Combine the turkey and zucchini, then form meatballs."]},
          {"name":"Cook the meatballs","steps":["Cook the meatballs until browned and cooked through."]}
        ]
      }
      """

    private func captureClient() -> WebRecipeCaptureClient {
      WebRecipeCaptureClient(fetchHTML: { _ in "" }, renderHTML: { _ in nil })
    }
  }
}

private actor RecipeExtractionRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }

  var count: Int {
    requests.count
  }
}

private enum Fixture {
  static func saminMeatballs() throws -> String {
    try String(contentsOf: directory.appendingPathComponent("samin-meatballs.html"), encoding: .utf8)
  }

  static let jsonLDRecipe = """
    <script type="application/ld+json">
      {"@context":"https://schema.org","@type":"Recipe","name":"Structured Soup","recipeIngredient":["1 onion"],"recipeInstructions":["Cook the onion."]}
    </script>
    """

  private static var directory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/WebRecipeCapture/SanitizedSites", isDirectory: true)
  }
}
