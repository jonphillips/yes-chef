import Dependencies
import Foundation
import LLMClientKit

/// The payload for the ADR-0027 Amendment 1 "deposit" verb: chat intelligence (a Compare verdict, a
/// "here's how I'd change this" riff) reshaped into a single recipe note to append onto the recipe-kind
/// menu item you point at. A recipe note is body-only (no title), so the plan carries one `DepositedNote`.
public struct DepositNotePlan: Equatable, Sendable {
  public var note: DepositedNote

  public init(note: DepositedNote = DepositedNote()) {
    self.note = note
  }
}

public struct DepositedNote: Equatable, Sendable {
  public var text: String

  public init(text: String = "") {
    self.text = text
  }

  public func editableReviewText() -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func applyingEditableReviewText(_ text: String) -> DepositedNote {
    DepositedNote(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

public struct MenuDepositClient: Sendable {
  public var extract: @Sendable (
    _ intelligence: String,
    _ messages: [RecipeChatMessage],
    _ tier: ModelTier
  ) async throws -> DepositNotePlan

  public init(
    extract: @escaping @Sendable (
      _ intelligence: String,
      _ messages: [RecipeChatMessage],
      _ tier: ModelTier
    ) async throws -> DepositNotePlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    intelligence: String,
    messages: [RecipeChatMessage],
    tier: ModelTier
  ) async throws -> DepositNotePlan {
    try await extract(intelligence, messages, tier)
  }
}

extension MenuDepositClient: DependencyKey {
  public static let liveValue = MenuDepositClient { intelligence, messages, tier in
    @Dependency(\.modelClient) var modelClient
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(intelligence: intelligence, messages: messages),
      maxTokens: 1536,
      reasoningEffort: .medium,
      // Deposit is a sibling of the base capture verb (both write a note from chat content), so it
      // reuses the capture-to-note prompt preference rather than adding a new synced settings column.
      promptPreferenceKey: AIPromptPreferenceKind.captureToNote.rawValue
    )
    let response = try await modelClient.complete(request)
    return parse(response.text)
  }

  public static let testValue = MenuDepositClient { _, _, _ in
    DepositNotePlan()
  }

  static let instructions = """
    You turn a piece of cooking advice already stated in a chat into a single durable recipe note.
    Return ONLY a strict JSON object:
    {"text":"a tidy note a cook would keep on the recipe"}
    Reshape the advisory reasoning already present in the source into a clean, keepable note. Never
    invent an ingredient, quantity, technique, or other detail that is not in the source. Do not draw
    on general cooking knowledge or guesses. Return {"text":""} when the source has no keepable note.
    """

  static func prompt(intelligence: String, messages: [RecipeChatMessage]) -> String {
    let trimmed = intelligence.trimmingCharacters(in: .whitespacesAndNewlines)
    let source: String
    if !trimmed.isEmpty {
      source = trimmed
    } else {
      // No explicit selection: fall back to the latest assistant turn (the most recent intelligence).
      source = messages
        .last { $0.role == .assistant }?
        .text
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    let body = source.isEmpty ? "(No chat intelligence available.)" : source
    return """
      Source: the cooking advice below, already stated in the chat. Use only this; do not invent.

      Advice:
      \(body)

      Reshape it into a single recipe note to keep on the recipe.
      """
  }

  public static func parse(_ text: String) -> DepositNotePlan {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data),
      let object = raw as? [String: Any],
      let noteText = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !noteText.isEmpty
    else { return DepositNotePlan() }

    return DepositNotePlan(note: DepositedNote(text: noteText))
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }
}

extension DependencyValues {
  public var menuDepositClient: MenuDepositClient {
    get { self[MenuDepositClient.self] }
    set { self[MenuDepositClient.self] = newValue }
  }
}
