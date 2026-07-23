import CustomDump
import Foundation
import LLMClientKit
import Testing
import YesChefCore

@Suite
struct ModelCallTests {
  @Test
  func recordDeclaresCallProvenanceAndAssembledInputSize() {
    let call = ModelCall(
      surface: .recipe,
      task: .makeAhead,
      tierResolution: .callerProvided,
      contextLayers: [.systemInstructions, .tasteProfile, .recipe, .selection, .conversation],
      tier: .frontier(.anthropic),
      system: "Use the recipe.",
      messages: [.user("Make a plan."), .assistant("I need timing.")],
      maxTokens: 2048,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.makeAheadPrepPlan.rawValue
    )

    expectNoDifference(
      call.record,
      ModelCallRecord(
        surface: .recipe,
        task: .makeAhead,
        tierResolution: .callerProvided,
        tier: .frontier(.anthropic),
        contextLayers: [.systemInstructions, .tasteProfile, .recipe, .selection, .conversation],
        inputCharacterCount: "Use the recipe.".count + "Make a plan.".count + "I need timing.".count,
        maxTokens: 2048,
        reasoningEffort: .high
      )
    )
  }

  @Test
  func completionForwardsTheUnchangedRequest() async throws {
    let recorder = RequestRecorder()
    let call = ModelCall(
      surface: .menu,
      task: .prepPlan,
      tierResolution: .callerProvided,
      contextLayers: [.systemInstructions, .tasteProfile, .menu, .selection, .conversation],
      tier: .frontier(.openai),
      system: "Plan ahead.",
      prompt: "Menu context",
      maxTokens: 2048,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.makeAheadPrepPlan.rawValue
    )

    _ = try await call.complete(
      using: StubModelClient { request in
        await recorder.append(request)
        return ModelResponse(text: "done")
      }
    )

    let request = await recorder.request()
    expectNoDifference(
      request,
      ModelRequest(
        tier: .frontier(.openai),
        system: "Plan ahead.",
        prompt: "Menu context",
        maxTokens: 2048,
        reasoningEffort: .high,
        promptPreferenceKey: AIPromptPreferenceKind.makeAheadPrepPlan.rawValue
      )
    )
  }

  @Test
  func coreSourcesCannotBypassModelCallConstructionOrDispatch() throws {
    let sourceDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/YesChefCore")
    let sourceFiles = try FileManager.default.contentsOfDirectory(
      at: sourceDirectory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "swift" }

    let rawRequestConstructionFiles = try sourceFiles.compactMap { file -> String? in
      guard file.lastPathComponent != "ModelCall.swift" else { return nil }
      return try String(contentsOf: file, encoding: .utf8).contains("ModelRequest(")
        ? file.lastPathComponent : nil
    }
    expectNoDifference(rawRequestConstructionFiles, [])

    let directDispatchFiles = try sourceFiles.compactMap { file -> String? in
      guard file.lastPathComponent != "ModelCall.swift" else { return nil }
      let source = try String(contentsOf: file, encoding: .utf8)
      return source.contains("modelClient.complete(") || source.contains("modelClient.stream(")
        ? file.lastPathComponent : nil
    }
    expectNoDifference(directDispatchFiles, [])
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
