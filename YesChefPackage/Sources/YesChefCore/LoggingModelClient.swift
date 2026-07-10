import Foundation
import LLMClientKit

/// Diagnostic decorator for the shared model-client seam.
///
/// Apply-action verbs all use one-shot completions, so logging here exposes the
/// exact request and response without changing any verb client's parsing logic.
public struct LoggingModelClient: ModelClient {
  private let wrapped: any ModelClient

  public init(wrapping wrapped: any ModelClient) {
    self.wrapped = wrapped
  }

  public func complete(_ request: ModelRequest) async throws -> ModelResponse {
    let preferenceKey = request.promptPreferenceKey ?? "unknown"
    let tier = request.tier.logDescription
    let prompt = request.logPrompt

    AppLog.llm.info(
      "request preference=\(preferenceKey, privacy: .public) tier=\(tier, privacy: .public) maxTokens=\(request.maxTokens, privacy: .public) prompt=\(prompt, privacy: .public)"
    )

    let startedAt = ContinuousClock.now
    do {
      let response = try await wrapped.complete(request)
      let elapsedMilliseconds = Self.elapsedMilliseconds(since: startedAt)
      let latency = String(format: "%.1f", elapsedMilliseconds)
      let stopReason = response.stopReason ?? "unknown"
      let responseShape = Self.responseShape(response.text)

      AppLog.llm.info(
        "response preference=\(preferenceKey, privacy: .public) tier=\(tier, privacy: .public) latencyMs=\(latency, privacy: .public) stopReason=\(stopReason, privacy: .public) shape=\(responseShape, privacy: .public) text=\(response.text, privacy: .public)"
      )
      return response
    } catch {
      let elapsedMilliseconds = Self.elapsedMilliseconds(since: startedAt)
      let latency = String(format: "%.1f", elapsedMilliseconds)
      let errorDescription = String(describing: error)
      AppLog.llm.error(
        "error preference=\(preferenceKey, privacy: .public) tier=\(tier, privacy: .public) latencyMs=\(latency, privacy: .public) error=\(errorDescription, privacy: .public)"
      )
      throw error
    }
  }

  public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelChunk, any Error> {
    wrapped.stream(request)
  }

  private static func elapsedMilliseconds(since startedAt: ContinuousClock.Instant) -> Double {
    let components = startedAt.duration(to: .now).components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func responseShape(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "empty" }
    switch first {
    case "{": return "json-object-or-truncated"
    case "[": return "json-array-or-truncated"
    default: return "non-JSON-prose-or-other"
    }
  }
}

private extension ModelTier {
  var logDescription: String {
    switch self {
    case .onDevice:
      "on-device"
    case let .frontier(provider):
      "frontier/\(provider.rawValue)"
    case .frontierPreferred:
      "frontier-preferred"
    }
  }
}

private extension ModelRequest {
  var logPrompt: String {
    var sections: [String] = []
    if let system, !system.isEmpty {
      sections.append("system:\n\(system)")
    }
    if !messages.isEmpty {
      sections.append(
        messages.enumerated().map { index, message in
          "message[\(index)] \(message.role.rawValue):\n\(message.text)"
        }.joined(separator: "\n\n")
      )
    }
    return sections.joined(separator: "\n\n")
  }
}
