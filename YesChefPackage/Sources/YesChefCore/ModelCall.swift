import Dependencies
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
  public let contextLayers: ModelCallContextLayers
  public let inputCharacterCount: Int
  public let maxTokens: Int
  public let reasoningEffort: ReasoningEffort?

  public init(
    surface: ModelCallSurface,
    task: ModelCallTask,
    tierResolution: ModelCallTierResolution,
    tier: ModelTier,
    contextLayers: ModelCallContextLayers,
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
  case workbench
}

/// Context supplied by a call site, including intentional omissions that a later
/// call shape may need to surface.
public struct ModelCallContextLayers: Equatable, Sendable, ExpressibleByArrayLiteral {
  public let included: Set<ModelCallContextLayer>
  public let omitted: Set<ModelCallContextLayer>

  public init(
    included: Set<ModelCallContextLayer>,
    omitted: Set<ModelCallContextLayer> = []
  ) {
    precondition(included.isDisjoint(with: omitted), "A context layer cannot be both included and omitted.")
    self.included = included
    self.omitted = omitted
  }

  public init(arrayLiteral elements: ModelCallContextLayer...) {
    self.init(included: Set(elements))
  }
}

/// Receives the provenance record when a model call starts.
///
/// S1's live value intentionally retains nothing. S2 can install an in-memory
/// collector without changing any construction site.
public struct ModelCallRecordSink: Sendable {
  public var record: @Sendable (ModelCallRecord) async -> Void

  public init(record: @escaping @Sendable (ModelCallRecord) async -> Void) {
    self.record = record
  }
}

/// An in-memory collector for an inspectable model-call inventory.
///
/// Values are append-only and deliberately unbounded for the lifetime of a debug
/// process. A future cap must add a cursor/reset contract for inventory readers.
public actor ModelCallRecordCollector {
  private var values: [ModelCallRecord] = []

  public init() {}

  public func append(_ record: ModelCallRecord) {
    values.append(record)
  }

  public func records() -> [ModelCallRecord] {
    values
  }
}

extension ModelCallRecordCollector: DependencyKey {
  public static let liveValue = ModelCallRecordCollector()
  public static let testValue = ModelCallRecordCollector()
}

extension ModelCallRecordSink {
  public static func inMemory(_ collector: ModelCallRecordCollector) -> Self {
    Self { record in
      await collector.append(record)
    }
  }
}

extension ModelCallRecordSink: DependencyKey {
  public static let liveValue = ModelCallRecordSink { _ in }
  public static let testValue = liveValue
}

extension DependencyValues {
  public var modelCallRecordSink: ModelCallRecordSink {
    get { self[ModelCallRecordSink.self] }
    set { self[ModelCallRecordSink.self] = newValue }
  }

  public var modelCallRecordCollector: ModelCallRecordCollector {
    get { self[ModelCallRecordCollector.self] }
    set { self[ModelCallRecordCollector.self] = newValue }
  }
}

/// A stable, append-only snapshot suitable for rendering the debug inventory.
public struct ModelCallInventory: Equatable, Sendable {
  public struct Entry: Equatable, Identifiable, Sendable {
    public let id: Int
    public let record: ModelCallRecord

    public init(id: Int, record: ModelCallRecord) {
      self.id = id
      self.record = record
    }
  }

  public private(set) var entries: [Entry] = []

  public init() {}

  /// Incorporates a collector snapshot without replacing entries already rendered.
  ///
  /// `ModelCallRecordCollector` is append-only and uncapped, so an entry's index
  /// remains a stable identity for this process. A capped collector must introduce
  /// a cursor/reset protocol before using this method.
  public mutating func appendNewRecords(from records: [ModelCallRecord]) {
    let firstNewEntryID = entries.count
    entries.append(contentsOf: records.dropFirst(firstNewEntryID).enumerated().map { offset, record in
      Entry(id: firstNewEntryID + offset, record: record)
    })
  }
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
    contextLayers: ModelCallContextLayers,
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
    contextLayers: ModelCallContextLayers,
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
    @Dependency(\.modelCallRecordSink) var recordSink
    await recordSink.record(record)
    return try await modelClient.complete(request)
  }

  public func stream(using modelClient: any ModelClient) async -> AsyncThrowingStream<ModelChunk, any Error> {
    @Dependency(\.modelCallRecordSink) var recordSink
    await recordSink.record(record)
    return modelClient.stream(request)
  }

  private static func inputCharacterCount(of request: ModelRequest) -> Int {
    (request.system?.count ?? 0) + request.messages.reduce(into: 0) { count, message in
      count += message.text.count
    }
  }
}
