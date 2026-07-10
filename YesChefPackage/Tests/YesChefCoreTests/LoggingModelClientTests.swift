import LLMClientKit
import Testing
import YesChefCore

@Suite
struct LoggingModelClientTests {
  @Test
  func completeForwardsRequestAndResponse() async throws {
    let recorder = RequestRecorder()
    let expectedRequest = ModelRequest(
      tier: .frontier(.anthropic),
      system: "You are concise.",
      prompt: "Return a prep plan.",
      maxTokens: 128,
      reasoningEffort: .high,
      promptPreferenceKey: "makeAheadPrepPlan"
    )
    let expectedResponse = ModelResponse(text: #"{"steps":[]}"#, stopReason: "end_turn")
    let client = LoggingModelClient(
      wrapping: StubModelClient { request in
        await recorder.append(request)
        return expectedResponse
      }
    )

    let response = try await client.complete(expectedRequest)

    #expect(response == expectedResponse)
    #expect(await recorder.request() == expectedRequest)
  }

  @Test
  func completeRethrowsWrappedError() async {
    let client = LoggingModelClient(
      wrapping: StubModelClient { _ in
        throw TestModelError.failed
      }
    )

    do {
      _ = try await client.complete(ModelRequest(prompt: "Prompt"))
      Issue.record("Expected the wrapped model error to be rethrown")
    } catch let error as TestModelError {
      #expect(error == .failed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}

private actor RequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func request() -> ModelRequest? {
    requests.first
  }
}

private enum TestModelError: Error, Sendable, Equatable {
  case failed
}
