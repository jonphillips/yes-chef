import Foundation
import LLMClientKit

/// A strict structured result reached the provider's output budget. Parsing a partial response as
/// an empty plan would silently discard useful work, so callers surface this explicitly instead.
public enum StructuredModelResponseError: Error, Equatable, LocalizedError, Sendable {
  case responseTruncated

  public var errorDescription: String? {
    "The model stopped before finishing the requested plan. Try again."
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
}
