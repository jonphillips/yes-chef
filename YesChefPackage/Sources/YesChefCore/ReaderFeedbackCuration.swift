import Dependencies
import Foundation
import LLMClientKit

public struct ReaderFeedbackTip: Equatable, Sendable, Identifiable {
  public var id: String { text }
  public var text: String

  public init(text: String) {
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
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

    let response = try await modelClient.complete(
      ModelRequest(
        tier: tier,
        system: instructions,
        prompt: prompt(comments: comments, sourceURL: sourceURL),
        maxTokens: maxTokens,
        reasoningEffort: .high
      )
    )
    return parse(response.text)
  }

  public static let testValue = ReaderFeedbackCurationClient { _, _ in [] }

  static let maxComments = 80
  static let maxTokens = 2048

  static let instructions = """
    You curate reader comments for a recipe app. Your primary job is ruthless selectivity.
    Most comments are noise: praise, nostalgia, sourcing complaints, obvious substitutions, or taste-only notes.
    Keep only distinct, non-obvious, genuinely useful cooking tips: technique corrections, timing or temperature fixes,
    ratio tweaks, failure warnings, or result-changing improvements the recipe did not already make clear.

    Preserve distinct tips. Select and lightly trim individual comments; never merge multiple readers into a summary.
    Bias toward precision over recall. Returning a few strong tips is correct. Returning an empty list is correct when
    nothing clears the bar.

    Return ONLY strict JSON:
    {"tips":[{"text":"one selected, lightly trimmed reader tip"}]}
    """

  static func prompt(comments: [RawComment], sourceURL: URL?) -> String {
    let renderedComments = comments
      .prefix(maxComments)
      .enumerated()
      .map { index, comment in
        """
        Comment \(index + 1) (helpful count: \(comment.helpfulCount)):
        \(comment.text)
        """
      }
      .joined(separator: "\n\n")
    let omittedCount = max(0, comments.count - maxComments)
    let omittedLine = omittedCount == 0
      ? ""
      : "\n\n\(omittedCount) lower-priority comment(s) were omitted to keep the request bounded."
    return """
      Source URL: \(sourceURL?.absoluteString ?? "(unknown)")

      Reader comments, already sorted by the site/playbook toward Most Helpful:
      \(renderedComments)\(omittedLine)

      Select only the comments that carry durable, specific cooking value. Return JSON only.
      """
  }

  public static func parse(_ text: String) -> [ReaderFeedbackTip] {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
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
      return ReaderFeedbackTip(text: text)
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
