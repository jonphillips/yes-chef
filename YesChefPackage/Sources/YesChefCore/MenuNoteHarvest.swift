import Dependencies
import Foundation
import LLMClientKit

public struct MenuNoteHarvestPlan: Equatable, Sendable {
  public var notes: [HarvestedNote]

  public init(notes: [HarvestedNote] = []) {
    self.notes = notes
  }
}

public struct HarvestedNote: Equatable, Sendable {
  public var title: String
  public var body: String

  public init(title: String, body: String = "") {
    self.title = title
    self.body = body
  }

  public func rendered() -> String {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return title }
    return "\(title)\n\(body)"
  }

  public func editableReviewText() -> String {
    rendered()
  }

  public func applyingEditableReviewText(_ text: String) -> HarvestedNote {
    let lines = text.components(separatedBy: .newlines)
    guard let titleIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      return self
    }

    let title = lines[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    let body = lines[(titleIndex + 1)...]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return HarvestedNote(title: title, body: body)
  }
}

public struct MenuNoteHarvestClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ tier: ModelTier
  ) async throws -> MenuNoteHarvestPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ tier: ModelTier
    ) async throws -> MenuNoteHarvestPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    tier: ModelTier
  ) async throws -> MenuNoteHarvestPlan {
    try await extract(selection, messages, tier)
  }
}

extension MenuNoteHarvestClient: DependencyKey {
  public static let liveValue = MenuNoteHarvestClient { selection, messages, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .menu,
      task: .noteHarvest,
      tierResolution: .callerProvided,
      contextLayers: [.selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages),
      maxTokens: 1536,
      reasoningEffort: .medium,
      promptPreferenceKey: AIPromptPreferenceKind.captureToNote.rawValue
    )
    let response = try await call.complete(using: modelClient)
    return parse(response.text)
  }

  public static let testValue = MenuNoteHarvestClient { _, _, _ in
    MenuNoteHarvestPlan()
  }

  static let instructions = """
    You extract durable cooking notes from content already present in a cooking chat.
    Return ONLY a strict JSON array:
    [{"title":"short note title","body":"tidy recipe-like details already stated in the source"}]
    Find one or more distinct dishes or notes present in the source. Reshape rambling prose into a
    clean, recipe-looking note with a short title and a tidy body. Never invent a dish, ingredient,
    quantity, technique, or other detail that is not in the source. Do not use the surrounding menu,
    general cooking knowledge, or guesses as source material. Return [] when the source has no
    distinct note-worthy cooking content. The body may be an empty string when the source contains
    no detail beyond the title.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage]) -> String {
    let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSelection.isEmpty {
      return """
        Source mode: explicit user selection. Use only the selected text below; do not use any other chat turn.

        Selected text:
        \(trimmedSelection)

        Extract distinct notes from this selected text.
        """
    }

    let assistantTranscript = messages
      .filter { $0.role == .assistant }
      .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .enumerated()
      .map { "Assistant turn \($0.offset + 1):\n\($0.element)" }
      .joined(separator: "\n\n")
    let source = assistantTranscript.isEmpty ? "(No assistant content yet.)" : assistantTranscript

    return """
      Source mode: transcript scan. Use only the assistant turns below; do not invent content from user requests.

      Assistant transcript:
      \(source)

      Extract distinct, note-worthy cooking notes from this transcript. Precision is more important than recall.
      """
  }

  public static func parse(_ text: String) -> MenuNoteHarvestPlan {
    guard
      let json = jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data),
      let elements = raw as? [[String: Any]]
    else { return MenuNoteHarvestPlan() }

    return MenuNoteHarvestPlan(
      notes: elements.compactMap { element in
        guard let title = (element["title"] as? String)?.nonEmptyHarvestText else { return nil }
        let body = (element["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HarvestedNote(title: title, body: body)
      }
    )
  }

  private static func jsonArraySlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close
    else { return nil }
    return String(text[open...close])
  }
}

extension DependencyValues {
  public var menuNoteHarvestClient: MenuNoteHarvestClient {
    get { self[MenuNoteHarvestClient.self] }
    set { self[MenuNoteHarvestClient.self] = newValue }
  }
}

private extension String {
  var nonEmptyHarvestText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
