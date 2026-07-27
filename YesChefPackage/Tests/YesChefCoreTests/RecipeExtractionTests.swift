import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Synchronization
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

      let callRecords = ModelCallRecordCollector()
      let (escalated, rerun) = try await withDependencies {
        $0.apiKeyStore = recipeExtractionAPIKeyStore([.anthropic: "sk-anthropic"])
        $0.modelCallRecordSink = .inMemory(callRecords)
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
      expectNoDifference(request?.tier, .frontier(.anthropic))
      expectNoDifference(request?.reasoningEffort, .high)
      expectNoDifference(request?.maxTokens, RecipeExtractionClient.maxTokens)
      #expect(request?.messages.first?.text.contains("## For the Sour Cream & Sumac Sauce") == true)
      expectNoDifference(requestCount, 2)

      let recordedCall = await callRecords.records().first
      expectNoDifference(recordedCall?.surface, .capture)
      expectNoDifference(recordedCall?.task, .recipeExtraction)
      expectNoDifference(recordedCall?.tierResolution, .configuredPreferences)
      expectNoDifference(recordedCall?.contextLayers, ModelCallContextLayers(included: [.structuredPageText]))
    }

    @Test
    func aFrontierPreferenceWithNoKeyDegradesOnDeviceAndSaysSo() async throws {
      let callRecords = ModelCallRecordCollector()
      let client = captureClient()
      let draft = client.browserCapture(
        html: try Fixture.saminMeatballs(),
        sourceURL: nil,
        capturedAt: .init(timeIntervalSinceReferenceDate: 900_200_000)
      )

      let escalated = try await withDependencies {
        $0.apiKeyStore = recipeExtractionAPIKeyStore([:])
        $0.recipeChatTierPreference = RecipeChatTierPreference(current: { true }, set: { _ in })
        $0.modelCallRecordSink = .inMemory(callRecords)
        $0.modelClient = StubModelClient { _ in ModelResponse(text: Self.saminExtractionJSON) }
        $0.recipeExtractionClient = .liveValue
      } operation: {
        try await client.escalate(draft: draft)
      }

      #expect(!escalated.page.ingredientSections.isEmpty)
      let recordedCall = await callRecords.records().first
      expectNoDifference(recordedCall?.tier, .onDevice)
      expectNoDifference(recordedCall?.tierResolution, .degradedToOnDevice)
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

    /// The model is deliberately given *reworded* ingredients here. Byte-identical
    /// lines dedupe on their own, so a fixture that echoes the deterministic wording
    /// cannot tell suppression from luck — and the merge must not depend on the model
    /// rewording nothing.
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
            ingredientSections: [.init(name: "Beans", lines: ["1 lb dried beans", "Water, for soaking"])],
            instructionSections: [.init(name: "Cook", steps: ["Soak the beans.", "Simmer until tender."])]
          )
        }
      } operation: {
        try await client.escalate(draft: draft)
      }

      expectNoDifference(escalated.page.title, "Partial Beans")
      expectNoDifference(escalated.page.ingredientSections, [.init(name: nil, lines: ["1 pound dried beans", "Water"])])
      expectNoDifference(escalated.page.modelExtractedIngredientSections, [])
      expectNoDifference(escalated.page.instructionSections, [
        .init(name: "Cook", steps: ["Soak the beans.", "Simmer until tender."]),
      ])
      expectNoDifference(escalated.page.modelExtractedInstructionSections, escalated.page.instructionSections)
    }

    @Test
    func deterministicInstructionsSurviveAModelIngredientMerge() async throws {
      let client = captureClient()
      let html = """
        <article itemscope itemtype="https://schema.org/Recipe">
          <h1 itemprop="name">Partial Broth</h1>
          <ol><li itemprop="recipeInstructions">Simmer the bones for six hours.</li></ol>
        </article>
        """
      let draft = client.browserCapture(html: html, sourceURL: nil, capturedAt: .init(timeIntervalSinceReferenceDate: 900_300_000))

      let escalated = try await withDependencies {
        $0.recipeExtractionClient = RecipeExtractionClient { _ in
          RecipeExtraction(
            ingredientSections: [.init(name: "Broth", lines: ["2 pounds beef bones", "1 onion"])],
            instructionSections: [.init(name: "Simmer", steps: ["Simmer bones for 6 hours."])]
          )
        }
      } operation: {
        try await client.escalate(draft: draft)
      }

      expectNoDifference(escalated.page.instructionSections, [
        .init(name: nil, steps: ["Simmer the bones for six hours."]),
      ])
      expectNoDifference(escalated.page.modelExtractedInstructionSections, [])
      expectNoDifference(escalated.page.ingredientSections, [
        .init(name: "Broth", lines: ["2 pounds beef bones", "1 onion"]),
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

private func recipeExtractionAPIKeyStore(_ keys: [FrontierProvider: String]) -> APIKeyStore {
  let storage = Mutex(keys)
  return APIKeyStore(
    read: { provider in storage.withLock { $0[provider] } },
    write: { provider, key in storage.withLock { $0[provider] = key } }
  )
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
