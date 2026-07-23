import CustomDump
import Dependencies
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
      contextLayers: [.recipe, .selection, .conversation],
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
        contextLayers: [.recipe, .selection, .conversation],
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
      contextLayers: [.menu, .selection, .conversation],
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
  func completionPublishesItsRecordToTheInMemorySink() async throws {
    let recorder = ModelCallRecordCollector()
    let call = ModelCall(
      surface: .grocery,
      task: .categorization,
      tierResolution: .callerProvided,
      contextLayers: [.ingredientNames],
      tier: .onDevice,
      prompt: "flour"
    )

    try await withDependencies {
      $0.modelCallRecordSink = .inMemory(recorder)
    } operation: {
      _ = try await call.complete(using: StubModelClient.constant("{}"))
    }

    let records = await recorder.records()
    expectNoDifference(records, [call.record])
  }

  @Test
  func contextLayersCanDeclareAnIntentionalOmission() {
    let layers = ModelCallContextLayers(
      included: [.recipe],
      omitted: [.learnings]
    )

    expectNoDifference(layers.included, [.recipe])
    expectNoDifference(layers.omitted, [.learnings])
  }

  @Test
  func appAndCoreSourcesCannotBypassModelCallConstructionOrDispatch() throws {
    let packageDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let repositoryDirectory = packageDirectory.deletingLastPathComponent()
    let sourceFiles = sourceFiles(
      in: [
        packageDirectory.appending(path: "Sources"),
        repositoryDirectory.appending(path: "YesChefApp"),
      ]
    )
    #expect(sourceFiles.contains { $0.lastPathComponent == "WebRecipeCaptureClient.swift" })
    #expect(sourceFiles.contains { $0.lastPathComponent == "HandoffReviewCoordinator.swift" })
    let modelCallSource = packageDirectory.appending(path: "Sources/YesChefCore/ModelCall.swift")

    let rawRequestConstructionFiles = try sourceFiles.compactMap { file -> String? in
      guard file != modelCallSource else { return nil }
      return try String(contentsOf: file, encoding: .utf8).contains("ModelRequest(")
        ? file.lastPathComponent : nil
    }
    expectNoDifference(rawRequestConstructionFiles, [])

    let directDispatchFiles = try sourceFiles.compactMap { file -> String? in
      guard file != modelCallSource else { return nil }
      let source = try String(contentsOf: file, encoding: .utf8)
      return source.contains("modelClient.complete(") || source.contains("modelClient.stream(")
        ? file.lastPathComponent : nil
    }
    expectNoDifference(directDispatchFiles, [])
  }

  private func sourceFiles(in directories: [URL]) -> [URL] {
    directories.flatMap { directory in
      let files = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
      return files?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
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
