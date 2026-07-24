import Dependencies
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MakeAheadPlanTruncationTests {
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
  }
}
