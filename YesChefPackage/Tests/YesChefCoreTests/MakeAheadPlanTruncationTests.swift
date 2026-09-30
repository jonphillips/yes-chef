import Dependencies
import LLMClientKit
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MakeAheadPlanTruncationTests {
    @Test
    func providerBlockReasonsAreTrimmedAndCaseInsensitive() {
      #expect(ModelResponse(text: "", stopReason: " content_filter ").wasBlockedByProvider)
      #expect(ModelResponse(text: "", stopReason: "REFUSAL").wasBlockedByProvider)
      #expect(!ModelResponse(text: "", stopReason: "stop").wasBlockedByProvider)
      #expect(!ModelResponse(text: "", stopReason: nil).wasBlockedByProvider)
    }

    @Test
    func makeAheadClientFailsLoudlyWhenAStrictResponseIsTruncated() async {
      await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(text: #"{"steps":["#, stopReason: "length")
        }
      } operation: {
        await #expect(throws: StructuredModelResponseError.responseTruncated) {
          _ = try await MakeAheadPlanClient.liveValue(
            selection: "Make the sauce ahead.",
            messages: [],
            context: "Recipe context",
            tier: .frontier(.openai)
          )
        }
      }
    }

    @Test
    func makeAheadClientSurfacesProviderBlocks() async {
      await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(text: "", stopReason: " CONTENT_FILTER ")
        }
      } operation: {
        await #expect(throws: StructuredModelResponseError.responseBlocked) {
          _ = try await MakeAheadPlanClient.liveValue(
            selection: "Make the sauce ahead.",
            messages: [],
            context: "Recipe context",
            tier: .frontier(.openai)
          )
        }
      }
    }
  }
}
