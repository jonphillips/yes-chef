import Foundation
import LLMClientKit

/// A strict structured result reached the provider's output budget. Parsing a partial response as
/// an empty plan would silently discard useful work, so callers surface this explicitly instead.
public enum StructuredModelResponseError: Error, Equatable, LocalizedError, Sendable {
  case responseTruncated
  case responseBlocked

  public var errorDescription: String? {
    switch self {
    case .responseTruncated:
      "The model stopped before finishing the requested plan. Try again."
    case .responseBlocked:
      "The AI provider stopped this response (content filter). Try again, or switch providers in Settings."
    }
  }
}

extension ModelResponse {
  /// Provider-agnostic budget-exhaustion signal: OpenAI reports `length`, Anthropic
  /// `max_tokens` when the completion is cut off at `max_completion_tokens`/`max_tokens`.
  ///
  /// Matched case-insensitively and whitespace-trimmed so a provider's casing or padding
  /// never slips a truncated response through as a clean stop.
  var wasTruncated: Bool {
    guard
      let stopReason = stopReason?.trimmingCharacters(in: .whitespacesAndNewlines),
      !stopReason.isEmpty
    else { return false }
    switch stopReason.lowercased() {
    case "length", "max_tokens": return true
    default: return false
    }
  }

  /// Provider moderation/refusal stops are distinct from budget exhaustion and malformed output.
  var wasBlockedByProvider: Bool {
    guard
      let stopReason = stopReason?.trimmingCharacters(in: .whitespacesAndNewlines),
      !stopReason.isEmpty
    else { return false }
    switch stopReason.lowercased() {
    case "content_filter", "refusal": return true
    default: return false
    }
  }
}
