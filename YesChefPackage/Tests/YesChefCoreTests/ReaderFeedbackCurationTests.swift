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
    func parseKeepsAtomicPointsWithProvenanceAndDropsMalformedItems() {
      let tips = ReaderFeedbackCurationClient.parse(
        """
        [
          {
            "text": "Bake it on the lower rack so the bottom browns before the topping burns.",
            "kind": "consensusDistilled",
            "supportCount": 2,
            "commentNumbers": [1, 3]
          },
          {"text": "  "},
          {
            "text": "Bake it on the lower rack so the bottom browns before the topping burns.",
            "supportCount": 1,
            "commentNumbers": [1]
          },
          {
            "text": "Rest the dough overnight; same-day dough spread too much.",
            "kind": "singularPreserved",
            "commentNumbers": [2]
          }
        ]
        """,
        comments: [
          RawComment(text: "Lower rack gave me a browned bottom.", helpfulCount: 12),
          RawComment(text: "Same-day dough spread; overnight rest fixed it.", helpfulCount: 7),
          RawComment(text: "Another vote for the lower rack.", helpfulCount: 3),
        ]
      )

      expectNoDifference(
        tips,
        [
          ReaderFeedbackTip(
            text: "Bake it on the lower rack so the bottom browns before the topping burns.",
            provenanceKind: .consensusDistilled,
            supportCount: 2,
            backingComments: [
              ReaderFeedbackBackingComment(commentNumber: 1, text: "Lower rack gave me a browned bottom.", helpfulCount: 12),
              ReaderFeedbackBackingComment(commentNumber: 3, text: "Another vote for the lower rack.", helpfulCount: 3),
            ]
          ),
          ReaderFeedbackTip(
            text: "Rest the dough overnight; same-day dough spread too much.",
            provenanceKind: .singularPreserved,
            supportCount: 1,
            backingComments: [
              ReaderFeedbackBackingComment(
                commentNumber: 2,
                text: "Same-day dough spread; overnight rest fixed it.",
                helpfulCount: 7
              )
            ]
          ),
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
            text: """
              [
                {
                  "text": "Toast the spices briefly before adding the tomatoes.",
                  "kind": "consensusDistilled",
                  "supportCount": 2,
                  "commentNumbers": [1, 2]
                }
              ]
              """
          )
        }
      } operation: {
        let tips = try await ReaderFeedbackCurationClient.liveValue(
          comments: [
            RawComment(text: "My sauce was flat until I toasted the spices first.", helpfulCount: 18),
            RawComment(text: "Toasting the spice mix made it bloom.", helpfulCount: 9),
            RawComment(text: "   ", helpfulCount: 99),
          ],
          sourceURL: URL(string: "https://cooking.nytimes.com/recipes/example")
        )

        expectNoDifference(
          tips,
          [
            ReaderFeedbackTip(
              text: "Toast the spices briefly before adding the tomatoes.",
              provenanceKind: .consensusDistilled,
              supportCount: 2,
              backingComments: [
                ReaderFeedbackBackingComment(
                  commentNumber: 1,
                  text: "My sauce was flat until I toasted the spices first.",
                  helpfulCount: 18
                ),
                ReaderFeedbackBackingComment(
                  commentNumber: 2,
                  text: "Toasting the spice mix made it bloom.",
                  helpfulCount: 9
                ),
              ]
            )
          ]
        )
      }

      let request = try #require(await recorder.first())
      expectNoDifference(request.tier, .frontier(.openai))
      expectNoDifference(request.reasoningEffort, .high)
      expectNoDifference(request.maxTokens, 16_384)
      expectNoDifference(request.promptPreferenceKey, AIPromptPreferenceKind.readerFeedback.rawValue)
      #expect(request.messages.first?.text.contains("helpful count: 18") == true)
      #expect(request.messages.first?.text.contains("helpful count: 9") == true)
      #expect(request.messages.first?.text.contains("99") == false)
      #expect(request.system?.contains("synthesize WITHIN one point") == true)
    }

    @Test
    func liveClientSurfacesTruncatedResponses() async throws {
      await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(text: #"[]"#, stopReason: "length")
        }
      } operation: {
        await #expect(throws: ReaderFeedbackCurationError.responseTruncated) {
          _ = try await ReaderFeedbackCurationClient.liveValue(
            comments: [RawComment(text: "Use less honey.", helpfulCount: 4)],
            sourceURL: nil
          )
        }
      }
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
