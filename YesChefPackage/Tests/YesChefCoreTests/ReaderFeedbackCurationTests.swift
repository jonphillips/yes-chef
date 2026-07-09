import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Synchronization
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct ReaderFeedbackCurationTests {
    @Test
    func parseKeepsDistinctTipsAndDropsMalformedItems() {
      let tips = ReaderFeedbackCurationClient.parse(
        """
        {
          "tips": [
            {"text": "Bake it on the lower rack so the bottom browns before the topping burns."},
            {"text": "  "},
            {"text": "Bake it on the lower rack so the bottom browns before the topping burns."},
            {"text": "Rest the dough overnight; same-day dough spread too much."}
          ]
        }
        """
      )

      expectNoDifference(
        tips,
        [
          ReaderFeedbackTip(text: "Bake it on the lower rack so the bottom browns before the topping burns."),
          ReaderFeedbackTip(text: "Rest the dough overnight; same-day dough spread too much."),
        ]
      )
    }

    @Test
    func liveClientUsesConfiguredFrontierProviderAndHighEffort() async throws {
      let recorder = ReaderFeedbackModelRequestRecorder()

      try await withDependencies {
        $0.apiKeyStore = readerFeedbackAPIKeyStore([.openai: "sk-openai"])
        $0.recipeChatProviderPreference = RecipeChatProviderPreference(
          current: { .openai },
          set: { _ in }
        )
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(
            text: #"{"tips":[{"text":"Toast the spices briefly before adding the tomatoes."}]}"#
          )
        }
      } operation: {
        let tips = try await ReaderFeedbackCurationClient.liveValue(
          comments: [
            RawComment(text: "My sauce was flat until I toasted the spices first.", helpfulCount: 18)
          ],
          sourceURL: URL(string: "https://cooking.nytimes.com/recipes/example")
        )

        expectNoDifference(
          tips,
          [ReaderFeedbackTip(text: "Toast the spices briefly before adding the tomatoes.")]
        )
      }

      let request = try #require(await recorder.first())
      expectNoDifference(request.tier, .frontier(.openai))
      expectNoDifference(request.reasoningEffort, .high)
      expectNoDifference(request.maxTokens, 2048)
      expectNoDifference(request.promptPreferenceKey, nil)
      #expect(request.messages.first?.text.contains("helpful count: 18") == true)
      #expect(request.system?.contains("never merge multiple readers into a summary") == true)
    }

    @Test
    func parsedPageBundleWritesAcceptedReaderFeedbackNotes() throws {
      var uuids = SampleUUIDSequence(start: 9_100)
      let now = Date(timeIntervalSinceReferenceDate: 802_200_000)
      let bundle = try ParsedRecipePage(
        title: "Tomato Pasta",
        ingredientSections: [ParsedRecipeIngredientSection(lines: ["1 pound tomatoes"])],
        instructionSections: [ParsedRecipeInstructionSection(steps: ["Cook the sauce."])],
        readerFeedbackBlocks: [
          ParsedRecipeReaderFeedbackBlock(text: "Use a wide skillet so the sauce reduces quickly."),
          ParsedRecipeReaderFeedbackBlock(text: "  "),
          ParsedRecipeReaderFeedbackBlock(text: "Add basil off heat so it stays bright."),
        ],
        capturedAt: now
      )
      .makeRecipeBundle(now: now, uuid: { uuids.next() })

      expectNoDifference(bundle.recipeNotes.map(\.noteType), [.readerFeedback, .readerFeedback])
      expectNoDifference(
        bundle.recipeNotes.map(\.text),
        [
          "Use a wide skillet so the sauce reduces quickly.",
          "Add basil off heat so it stays bright.",
        ]
      )
    }
  }
}

private func readerFeedbackAPIKeyStore(_ keys: [FrontierProvider: String]) -> APIKeyStore {
  let storage = Mutex(keys)
  return APIKeyStore(
    read: { provider in storage.withLock { $0[provider] } },
    write: { provider, key in storage.withLock { $0[provider] = key } }
  )
}

private actor ReaderFeedbackModelRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
