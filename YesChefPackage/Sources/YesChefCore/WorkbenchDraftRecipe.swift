import Dependencies
import Foundation
import LLMClientKit

public enum WorkbenchDraftRecipeError: Error, Equatable, LocalizedError {
  /// The model exhausted its token budget (usually on reasoning) before finishing the recipe.
  case responseTruncated
  /// The model returned text, but no recipe could be read from it.
  case responseUnreadable

  public var errorDescription: String? {
    switch self {
    case .responseTruncated:
      "The model ran out of room before it finished the working recipe. Try again."
    case .responseUnreadable:
      "The model's response couldn't be read as a working recipe. Try again."
    }
  }
}

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

  public func editableProseReviewText() -> String {
    var lines = [
      WorkbenchDraftRecipeEditableField.rationale.render(rationale),
      WorkbenchDraftRecipeEditableField.title.render(title),
      WorkbenchDraftRecipeEditableField.subtitle.render(subtitle ?? ""),
      WorkbenchDraftRecipeEditableField.summary.render(summary ?? ""),
      WorkbenchDraftRecipeEditableField.servings.render(servingsText ?? ""),
      WorkbenchDraftRecipeEditableField.yield.render(yieldText ?? ""),
      WorkbenchDraftRecipeEditableField.cuisine.render(cuisine ?? ""),
      WorkbenchDraftRecipeEditableField.course.render(course ?? ""),
      WorkbenchDraftRecipeEditableField.ingredientSection.render(ingredientSectionName ?? ""),
      WorkbenchDraftRecipeEditableField.notes.render(""),
    ]
    if !notes.isEmpty {
      lines.append(contentsOf: notes.map { "- \($0)" })
    }
    return lines.joined(separator: "\n")
  }

  public func applyingEditableProseReviewText(_ text: String) -> WorkbenchDraftRecipe {
    let fields = WorkbenchDraftRecipeEditableField.parse(text)
    var draft = self
    draft.rationale = fields.text(for: .rationale) ?? rationale
    draft.title = fields.text(for: .title) ?? title
    draft.subtitle = fields.optionalText(for: .subtitle, default: subtitle)
    draft.summary = fields.optionalText(for: .summary, default: summary)
    draft.servingsText = fields.optionalText(for: .servings, default: servingsText)
    draft.yieldText = fields.optionalText(for: .yield, default: yieldText)
    draft.cuisine = fields.optionalText(for: .cuisine, default: cuisine)
    draft.course = fields.optionalText(for: .course, default: course)
    draft.ingredientSectionName = fields.optionalText(for: .ingredientSection, default: ingredientSectionName)
    draft.notes = fields.notes ?? notes
    return draft
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

private enum WorkbenchDraftRecipeEditableField: CaseIterable, Hashable {
  case rationale
  case title
  case subtitle
  case summary
  case servings
  case yield
  case cuisine
  case course
  case ingredientSection
  case notes

  var label: String {
    switch self {
    case .rationale: "Rationale"
    case .title: "Title"
    case .subtitle: "Subtitle"
    case .summary: "Summary"
    case .servings: "Servings"
    case .yield: "Yield"
    case .cuisine: "Cuisine"
    case .course: "Course"
    case .ingredientSection: "Ingredient section"
    case .notes: "Notes"
    }
  }

  func render(_ value: String) -> String {
    "\(label): \(value)"
  }

  static func parse(_ text: String) -> WorkbenchDraftRecipeEditableFields {
    var values: [WorkbenchDraftRecipeEditableField: [String]] = [:]
    var currentField: WorkbenchDraftRecipeEditableField?

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      if let fieldValue = fieldValue(from: line) {
        currentField = fieldValue.field
        values[fieldValue.field] = fieldValue.value.isEmpty ? [] : [fieldValue.value]
      } else if let currentField {
        values[currentField, default: []].append(line)
      }
    }

    return WorkbenchDraftRecipeEditableFields(values: values)
  }

  private static func fieldValue(from line: String) -> (field: WorkbenchDraftRecipeEditableField, value: String)? {
    let normalized = line.lowercased()
    for field in allCases {
      let prefix = "\(field.label.lowercased()):"
      guard normalized.hasPrefix(prefix) else { continue }
      let valueStart = line.index(line.startIndex, offsetBy: prefix.count)
      return (
        field,
        String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    return nil
  }
}

private struct WorkbenchDraftRecipeEditableFields {
  var values: [WorkbenchDraftRecipeEditableField: [String]]

  var notes: [String]? {
    guard let lines = values[.notes] else { return nil }
    return lines
      .map(\.cleanedWorkbenchDraftEditableListLine)
      .filter { !$0.isEmpty }
  }

  func text(for field: WorkbenchDraftRecipeEditableField) -> String? {
    guard let lines = values[field] else { return nil }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func optionalText(
    for field: WorkbenchDraftRecipeEditableField,
    default defaultValue: String?
  ) -> String? {
    guard let text = text(for: field) else { return defaultValue }
    return text.isEmpty ? nil : text
  }
}

private extension String {
  var cleanedWorkbenchDraftEditableListLine: String {
    var line = trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
      line.removeFirst(2)
    } else if line.hasPrefix("• ") {
      line.removeFirst(2)
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
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
      // A reasoning model shares `max_completion_tokens` between thinking and output, so the draft
      // needs headroom for both — 4096 let reasoning starve the JSON body. Billing is per token
      // *used*, not the ceiling, so this generous cap only removes truncation, it doesn't raise cost.
      // Effort is `.high` deliberately: drafting the working recipe is a user-initiated synthesis where
      // a good answer is worth a slow one — this is a personal app, not a request-bound server, so the
      // frontier session grants a generous request timeout to match (LLMClientKit `URLSession.frontier`).
      // Surfacing effort as a user control is the real fix (see efforts/recipe-workbench.md).
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 16_384,
      reasoningEffort: .high
    )
    let response = try await modelClient.complete(request)
    let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Distinguish a real failure from a deliberate "no recipe yet" (which comes back as valid
    // JSON with an empty title). A budget-exhausted or empty response is a retryable failure;
    // a non-empty response with no decodable JSON object is an unreadable one.
    if response.wasTruncated || trimmed.isEmpty {
      throw WorkbenchDraftRecipeError.responseTruncated
    }
    guard jsonObject(in: response.text) != nil else {
      throw WorkbenchDraftRecipeError.responseUnreadable
    }
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

      Draft the working recipe JSON object by synthesizing the workbench candidates and the full conversation
      above. Treat the user-selected subject, if any, only as an optional focus hint — never as the sole
      instruction — and ignore it entirely when it is a greeting, acknowledgement, or otherwise not a
      substantive request about the dish.
      """
  }

  static func jsonObject(in text: String) -> [String: Any]? {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return nil
    }
    return object
  }

  public static func parse(_ text: String) -> WorkbenchDraftRecipe {
    guard let object = jsonObject(in: text) else {
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
