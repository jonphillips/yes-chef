import Foundation
import LLMClientKit

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
