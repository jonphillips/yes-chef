import Dependencies
import Foundation
import LLMClientKit

public struct WorkbenchDraftRecipe: Equatable, Sendable {
  public var title: String
  public var subtitle: String?
  public var summary: String?
  public var servingsText: String?
  public var yieldText: String?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var cuisine: String?
  public var course: String?
  public var ingredientSectionName: String?
  public var ingredientLines: [String]
  public var instructionLines: [String]
  public var notes: [String]
  public var rationale: String

  public init(
    title: String,
    subtitle: String? = nil,
    summary: String? = nil,
    servingsText: String? = nil,
    yieldText: String? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    cuisine: String? = nil,
    course: String? = nil,
    ingredientSectionName: String? = nil,
    ingredientLines: [String] = [],
    instructionLines: [String] = [],
    notes: [String] = [],
    rationale: String
  ) {
    self.title = title
    self.subtitle = subtitle
    self.summary = summary
    self.servingsText = servingsText
    self.yieldText = yieldText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.cuisine = cuisine
    self.course = course
    self.ingredientSectionName = ingredientSectionName
    self.ingredientLines = ingredientLines
    self.instructionLines = instructionLines
    self.notes = notes
    self.rationale = rationale
  }

  public var isEmpty: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || (ingredientLines.isEmpty && instructionLines.isEmpty)
      || rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public func renderedReview() -> String {
    var lines: [String] = []
    if !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines.append("Rationale: \(rationale)")
    }
    lines.append("Title: \(title)")
    if let subtitle { lines.append("Subtitle: \(subtitle)") }
    if let summary { lines.append("Summary: \(summary)") }
    if let servingsText { lines.append("Servings: \(servingsText)") }
    if let yieldText { lines.append("Yield: \(yieldText)") }
    if let prepTimeMinutes { lines.append("Prep: \(prepTimeMinutes) min") }
    if let cookTimeMinutes { lines.append("Cook: \(cookTimeMinutes) min") }
    if !ingredientLines.isEmpty {
      lines.append("")
      lines.append("Ingredients:")
      lines.append(contentsOf: ingredientLines.map { "- \($0)" })
    }
    if !instructionLines.isEmpty {
      lines.append("")
      lines.append("Instructions:")
      lines.append(contentsOf: instructionLines.enumerated().map { index, step in "\(index + 1). \(step)" })
    }
    if !notes.isEmpty {
      lines.append("")
      lines.append("Notes:")
      lines.append(contentsOf: notes.map { "- \($0)" })
    }
    return lines.joined(separator: "\n")
  }

  public func editorDraft(libraryPlacement: RecipeLibraryPlacement) -> RecipeEditorDraft {
    let noteParagraphs = (["Draft rationale: \(rationale)"] + notes)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    return RecipeEditorDraft(
      title: title,
      subtitle: subtitle ?? "",
      summary: summary ?? "",
      servingsText: servingsText ?? "",
      yieldText: yieldText ?? "",
      prepTimeMinutes: prepTimeMinutes ?? 0,
      cookTimeMinutes: cookTimeMinutes ?? 0,
      cuisine: cuisine ?? "",
      course: course ?? "",
      libraryPlacement: libraryPlacement,
      ingredientSectionName: ingredientSectionName ?? "",
      ingredientText: ingredientLines.joined(separator: "\n"),
      instructionText: instructionLines.joined(separator: "\n\n"),
      noteText: noteParagraphs.joined(separator: "\n\n")
    )
  }
}

public struct WorkbenchDraftRecipeClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> WorkbenchDraftRecipe

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> WorkbenchDraftRecipe
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> WorkbenchDraftRecipe {
    try await extract(selection, messages, context, tier)
  }
}

extension WorkbenchDraftRecipeClient: DependencyKey {
  public static let liveValue = WorkbenchDraftRecipeClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 4096,
      reasoningEffort: .high
    )
    let response = try await modelClient.complete(request)
    return parse(response.text)
  }

  public static let testValue = WorkbenchDraftRecipeClient { _, _, _, _ in
    WorkbenchDraftRecipe(title: "", rationale: "")
  }

  static let instructions = """
    You draft one working recipe from a recipe workbench conversation.

    \(RecipeChatContext.workbenchTaskFraming)

    Return ONLY strict JSON:
    {"title":"working recipe title","subtitle":null,"summary":"short summary","servingsText":null,"yieldText":null,"prepTimeMinutes":0,"cookTimeMinutes":0,"cuisine":null,"course":null,"ingredientSectionName":null,"ingredientLines":["line"],"instructionLines":["step"],"notes":["optional note or deliberate variation"],"rationale":"brief rationale that names the candidate choices this draft borrows from or rejects"}.

    The draft must be a coherent editorial choice with a rationale referencing candidates. Do not average every
    candidate together. It may include a base recipe plus deliberate variations inside notes or method steps.
    Use only the provided workbench context and conversation. Return an empty title, empty arrays, and empty rationale
    when there is no concrete working recipe to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    let conversation = messages.isEmpty
      ? "(No conversation yet.)"
      : messages.map { "\($0.role.promptLabel): \($0.text)" }.joined(separator: "\n")
    return """
      Workbench context:
      \(context)

      User-selected subject:
      \(selection)

      Conversation so far:
      \(conversation)

      Draft the working recipe JSON object. Use the selected subject as the main instruction when it is specific;
      otherwise use the conversation and workbench context to choose the most coherent draft.
      """
  }

  public static func parse(_ text: String) -> WorkbenchDraftRecipe {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return WorkbenchDraftRecipe(title: "", rationale: "")
    }

    return WorkbenchDraftRecipe(
      title: string("title", in: object) ?? "",
      subtitle: string("subtitle", in: object),
      summary: string("summary", in: object),
      servingsText: string("servingsText", in: object),
      yieldText: string("yieldText", in: object),
      prepTimeMinutes: integer("prepTimeMinutes", in: object),
      cookTimeMinutes: integer("cookTimeMinutes", in: object),
      cuisine: string("cuisine", in: object),
      course: string("course", in: object),
      ingredientSectionName: string("ingredientSectionName", in: object),
      ingredientLines: stringArray("ingredientLines", in: object),
      instructionLines: stringArray("instructionLines", in: object),
      notes: stringArray("notes", in: object),
      rationale: string("rationale", in: object) ?? ""
    )
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }

  private static func string(_ key: String, in object: [String: Any]) -> String? {
    (object[key] as? String)?.cleanedWorkbenchDraftText
  }

  private static func stringArray(_ key: String, in object: [String: Any]) -> [String] {
    if let strings = object[key] as? [String] {
      return strings.compactMap(\.cleanedWorkbenchDraftText)
    }
    if let text = string(key, in: object) {
      return [text]
    }
    return []
  }

  private static func integer(_ key: String, in object: [String: Any]) -> Int? {
    if let int = object[key] as? Int {
      return int == 0 ? nil : int
    }
    if let double = object[key] as? Double {
      let int = Int(double)
      return int == 0 ? nil : int
    }
    if let text = string(key, in: object), let int = Int(text) {
      return int == 0 ? nil : int
    }
    return nil
  }
}

extension DependencyValues {
  public var workbenchDraftRecipeClient: WorkbenchDraftRecipeClient {
    get { self[WorkbenchDraftRecipeClient.self] }
    set { self[WorkbenchDraftRecipeClient.self] = newValue }
  }
}

private extension RecipeChatMessage.Role {
  var promptLabel: String {
    switch self {
    case .user: "User"
    case .assistant: "Assistant"
    }
  }
}

private extension String {
  var cleanedWorkbenchDraftText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
