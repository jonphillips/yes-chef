import Dependencies
import Foundation
import LLMClientKit

public struct ReaderFeedbackTip: Equatable, Sendable, Identifiable {
  public var id: String { text }
  public var text: String
  public var provenanceKind: ReaderFeedbackProvenanceKind
  public var supportCount: Int
  public var backingComments: [ReaderFeedbackBackingComment]

  public init(
    text: String,
    provenanceKind: ReaderFeedbackProvenanceKind = .singularPreserved,
    supportCount: Int = 1,
    backingComments: [ReaderFeedbackBackingComment] = []
  ) {
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    self.provenanceKind = provenanceKind
    self.supportCount = max(supportCount, backingComments.count, 1)
    self.backingComments = backingComments
  }
}

public enum ReaderFeedbackProvenanceKind: String, Equatable, Sendable {
  case consensusDistilled
  case singularPreserved

  public var displayName: String {
    switch self {
    case .consensusDistilled: "Consensus"
    case .singularPreserved: "Single Comment"
    }
  }
}

public struct ReaderFeedbackBackingComment: Equatable, Sendable, Identifiable {
  public var id: Int { commentNumber }
  public var commentNumber: Int
  public var text: String
  public var helpfulCount: Int

  public init(commentNumber: Int, text: String, helpfulCount: Int) {
    self.commentNumber = commentNumber
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    self.helpfulCount = helpfulCount
  }
}

public enum ReaderFeedbackCurationError: Error, Equatable, Sendable {
  case responseTruncated
}

public struct ReaderFeedbackCurationClient: Sendable {
  public var curate: @Sendable (_ comments: [RawComment], _ sourceURL: URL?) async throws -> [ReaderFeedbackTip]

  public init(
    curate: @escaping @Sendable (_ comments: [RawComment], _ sourceURL: URL?) async throws -> [ReaderFeedbackTip]
  ) {
    self.curate = curate
  }

  public func callAsFunction(comments: [RawComment], sourceURL: URL?) async throws -> [ReaderFeedbackTip] {
    try await curate(comments, sourceURL)
  }
}

extension ReaderFeedbackCurationClient: DependencyKey {
  public static let liveValue = ReaderFeedbackCurationClient { comments, sourceURL in
    let comments = comments.compactMap(\.cleanedForReaderFeedbackCuration)
    guard !comments.isEmpty else { return [] }
    @Dependency(\.modelClient) var modelClient
    @Dependency(\.apiKeyStore) var apiKeyStore
    @Dependency(\.recipeChatProviderPreference) var providerPreference

    let availableProviders = FrontierProvider.allCases.filter { apiKeyStore.key($0) != nil }
    let preferredProvider = providerPreference.current()
    let tier: ModelTier
    if let preferredProvider, availableProviders.contains(preferredProvider) {
      tier = .frontier(preferredProvider)
    } else if let provider = availableProviders.first {
      tier = .frontier(provider)
    } else {
      tier = .onDevice
    }

    let call = ModelCall(
      surface: .reader,
      task: .feedbackCuration,
      tierResolution: .preferredProviderOrFirstAvailable,
      contextLayers: ModelCallContextLayers(
        included: [.readerComments],
        omitted: [.tasteProfile]
      ),
      tier: tier,
      system: instructions,
      prompt: prompt(comments: comments, sourceURL: sourceURL),
      maxTokens: maxTokens,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.readerFeedback.rawValue
    )
    let response = try await call.complete(using: modelClient)
    if response.wasTruncated {
      throw ReaderFeedbackCurationError.responseTruncated
    }
    return parse(response.text, comments: comments)
  }

  public static let testValue = ReaderFeedbackCurationClient { _, _ in [] }

  static let maxTokens = 16_384

  static let instructions = """
    You curate reader comments for a recipe app. Your primary job is ruthless selectivity.
    Most comments are noise: praise, nostalgia, sourcing complaints, obvious substitutions, or taste-only notes.
    Keep only distinct, non-obvious, genuinely useful cooking tips: technique corrections, timing or temperature fixes,
    ratio tweaks, failure warnings, or result-changing improvements the recipe did not already make clear.

    Return a JSON array of atomic recipe-change points. You may synthesize WITHIN one point when several commenters
    converge on the same change, and you must keep distinct changes as separate entries. Do not blend separate changes
    into one paragraph.

    Two provenance kinds are both first-class:
    - consensusDistilled: many comments support the same atomic point. Return one point with a support count.
    - singularPreserved: one rich, specific comment is worth preserving largely intact.

    Bias toward precision over recall. Returning a few strong points is correct. Returning an empty array is correct
    when nothing clears the bar.

    Return ONLY strict JSON:
    [
      {
        "text": "one atomic reader-feedback point",
        "kind": "consensusDistilled or singularPreserved",
        "supportCount": 2,
        "commentNumbers": [1, 7]
      }
    ]
    """

  static func prompt(comments: [RawComment], sourceURL: URL?) -> String {
    let renderedComments = comments
      .enumerated()
      .map { index, comment in
        """
        Comment \(index + 1) (helpful count: \(comment.helpfulCount)):
        \(comment.text)
        """
      }
      .joined(separator: "\n\n")
    return """
      Source URL: \(sourceURL?.absoluteString ?? "(unknown)")

      Reader comments, already sorted by the site/playbook toward Most Helpful:
      \(renderedComments)

      Select only comments that carry durable, specific cooking value. Keep redundancy intact as the consensus signal:
      when several comments say the same useful thing, emit one consensusDistilled point with the backing commentNumbers.
      When one comment has a useful specific contribution, emit one singularPreserved point. Return JSON only.
      """
  }

  public static func parse(_ text: String, comments: [RawComment] = []) -> [ReaderFeedbackTip] {
    guard
      let json = jsonSlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return [] }

    let elements: [[String: Any]]
    if let object = raw as? [String: Any] {
      elements = object["tips"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    var seen: Set<String> = []
    return elements.compactMap { element in
      guard let text = (element["text"] as? String)?.cleanedReaderFeedbackText else { return nil }
      let key = text.lowercased()
      guard seen.insert(key).inserted else { return nil }
      let backingComments = backingComments(from: element, comments: comments)
      let supportCount = element["supportCount"] as? Int ?? backingComments.count
      return ReaderFeedbackTip(
        text: text,
        provenanceKind: provenanceKind(from: element, supportCount: supportCount),
        supportCount: supportCount,
        backingComments: backingComments
      )
    }
  }

  private static func backingComments(
    from element: [String: Any],
    comments: [RawComment]
  ) -> [ReaderFeedbackBackingComment] {
    let commentNumbers = (element["commentNumbers"] as? [Int])
      ?? (element["backingCommentNumbers"] as? [Int])
      ?? (element["sourceCommentNumbers"] as? [Int])
      ?? []
    let numberedComments = commentNumbers.compactMap { commentNumber -> ReaderFeedbackBackingComment? in
      let index = commentNumber - 1
      guard comments.indices.contains(index) else { return nil }
      let comment = comments[index]
      return ReaderFeedbackBackingComment(
        commentNumber: commentNumber,
        text: comment.text,
        helpfulCount: comment.helpfulCount
      )
    }
    if !numberedComments.isEmpty {
      return numberedComments
    }
    let inlineComments = (element["comments"] as? [String]) ?? (element["backingComments"] as? [String]) ?? []
    return inlineComments.enumerated().compactMap { index, text in
      guard let cleanedText = text.cleanedReaderFeedbackText else { return nil }
      return ReaderFeedbackBackingComment(
        commentNumber: index + 1,
        text: cleanedText,
        helpfulCount: 0
      )
    }
  }

  private static func provenanceKind(
    from element: [String: Any],
    supportCount: Int
  ) -> ReaderFeedbackProvenanceKind {
    guard let kind = element["kind"] as? String else {
      return supportCount > 1 ? .consensusDistilled : .singularPreserved
    }
    switch kind {
    case ReaderFeedbackProvenanceKind.consensusDistilled.rawValue:
      return .consensusDistilled
    case ReaderFeedbackProvenanceKind.singularPreserved.rawValue:
      return .singularPreserved
    default:
      return supportCount > 1 ? .consensusDistilled : .singularPreserved
    }
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }

  private static func jsonArraySlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close
    else { return nil }
    return String(text[open...close])
  }

  private static func jsonSlice(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let objectOpen = trimmed.firstIndex(of: "{")
    let arrayOpen = trimmed.firstIndex(of: "[")
    if let arrayOpen, objectOpen.map({ arrayOpen < $0 }) ?? true {
      return jsonArraySlice(trimmed)
    }
    return jsonObjectSlice(trimmed) ?? jsonArraySlice(trimmed)
  }
}

extension DependencyValues {
  public var readerFeedbackCurationClient: ReaderFeedbackCurationClient {
    get { self[ReaderFeedbackCurationClient.self] }
    set { self[ReaderFeedbackCurationClient.self] = newValue }
  }
}

private extension String {
  var cleanedReaderFeedbackText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension RawComment {
  var cleanedForReaderFeedbackCuration: RawComment? {
    guard let text = text.cleanedReaderFeedbackText else { return nil }
    return RawComment(text: text, helpfulCount: helpfulCount)
  }
}
