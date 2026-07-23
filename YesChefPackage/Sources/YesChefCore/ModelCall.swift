import LLMClientKit

/// The declared provenance for one in-app model call.
///
/// This value deliberately travels with its request instead of trying to infer
/// intent from the assembled prompt at the `ModelClient` boundary.
public struct ModelCallRecord: Equatable, Sendable {
  public let surface: ModelCallSurface
  public let task: ModelCallTask
  public let tierResolution: ModelCallTierResolution
  public let tier: ModelTier
  public let contextLayers: Set<ModelCallContextLayer>
  public let inputCharacterCount: Int
  public let maxTokens: Int
  public let reasoningEffort: ReasoningEffort?

  public init(
    surface: ModelCallSurface,
    task: ModelCallTask,
    tierResolution: ModelCallTierResolution,
    tier: ModelTier,
    contextLayers: Set<ModelCallContextLayer>,
    inputCharacterCount: Int,
    maxTokens: Int,
    reasoningEffort: ReasoningEffort?
  ) {
    self.surface = surface
    self.task = task
    self.tierResolution = tierResolution
    self.tier = tier
    self.contextLayers = contextLayers
    self.inputCharacterCount = inputCharacterCount
    self.maxTokens = maxTokens
    self.reasoningEffort = reasoningEffort
  }
}

public enum ModelCallSurface: String, Equatable, Sendable {
  case grocery
  case mealPlan
  case menu
  case reader
  case recipe
  case workbench
}

public enum ModelCallTask: String, Equatable, Sendable {
  case categorization
  case chat
  case chefItUp
  case complement
  case depositAppend
  case depositRevise
  case feedbackCuration
  case makeAhead
  case makeAheadStrategy
  case noteHarvest
  case prepPlan
  case recipeAdjustment
  case serveWith
  case workbenchComparison
  case workbenchDraft
}

public enum ModelCallTierResolution: String, Equatable, Sendable {
  /// The surrounding chat surface resolved the requested tier before invoking this task.
  case callerProvided
  /// The task chose the configured provider, then the first available provider, then on-device.
  case preferredProviderOrFirstAvailable
}

public enum ModelCallContextLayer: String, CaseIterable, Hashable, Sendable {
  case candidates
  case conversation
  case currentNote
  case ingredientNames
  case intelligence
  case learnings
  case mealPlan
  case menu
  case readerComments
  case recipe
  case selection
  case systemInstructions
  case tasteProfile
  case workbench
}

/// The sole construction path for `ModelRequest` values owned by Yes Chef.
///
/// `ModelCall` retains the record for the request's lifetime. The existing
/// `LoggingModelClient` remains a completion-time diagnostic decorator; it
/// cannot recover this declaration from a finished prompt.
public struct ModelCall: Sendable {
  public let record: ModelCallRecord
  private let request: ModelRequest

  public init(
    surface: ModelCallSurface,
    task: ModelCallTask,
    tierResolution: ModelCallTierResolution,
    contextLayers: Set<ModelCallContextLayer>,
    tier: ModelTier,
    system: String? = nil,
    messages: [ModelMessage],
    tools: [ModelTool] = [],
    maxTokens: Int = 1024,
    webSearchMaxUses: Int? = nil,
    reasoningEffort: ReasoningEffort? = nil,
    promptPreferenceKey: String? = nil,
    continuationToken: ModelContinuationToken? = nil
  ) {
    let request = ModelRequest(
      tier: tier,
      system: system,
      messages: messages,
      tools: tools,
      maxTokens: maxTokens,
      webSearchMaxUses: webSearchMaxUses,
      reasoningEffort: reasoningEffort,
      promptPreferenceKey: promptPreferenceKey,
      continuationToken: continuationToken
    )
    self.request = request
    self.record = ModelCallRecord(
      surface: surface,
      task: task,
      tierResolution: tierResolution,
      tier: tier,
      contextLayers: contextLayers,
      inputCharacterCount: Self.inputCharacterCount(of: request),
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort
    )
  }

  public init(
    surface: ModelCallSurface,
    task: ModelCallTask,
    tierResolution: ModelCallTierResolution,
    contextLayers: Set<ModelCallContextLayer>,
    tier: ModelTier,
    system: String? = nil,
    prompt: String,
    tools: [ModelTool] = [],
    maxTokens: Int = 1024,
    webSearchMaxUses: Int? = nil,
    reasoningEffort: ReasoningEffort? = nil,
    promptPreferenceKey: String? = nil,
    continuationToken: ModelContinuationToken? = nil
  ) {
    self.init(
      surface: surface,
      task: task,
      tierResolution: tierResolution,
      contextLayers: contextLayers,
      tier: tier,
      system: system,
      messages: [.user(prompt)],
      tools: tools,
      maxTokens: maxTokens,
      webSearchMaxUses: webSearchMaxUses,
      reasoningEffort: reasoningEffort,
      promptPreferenceKey: promptPreferenceKey,
      continuationToken: continuationToken
    )
  }

  public func complete(using modelClient: any ModelClient) async throws -> ModelResponse {
    try await modelClient.complete(request)
  }

  public func stream(using modelClient: any ModelClient) -> AsyncThrowingStream<ModelChunk, any Error> {
    modelClient.stream(request)
  }

  private static func inputCharacterCount(of request: ModelRequest) -> Int {
    (request.system?.count ?? 0) + request.messages.reduce(into: 0) { count, message in
      count += message.text.count
    }
  }
}
