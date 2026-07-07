import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public enum RecipeAdjustmentError: Error, Equatable, LocalizedError {
  case responseTruncated
  case responseUnreadable
  case emptyProposal
  case missingRecipe(Recipe.ID)
  case unresolvedIngredient(String)
  case unresolvedInstructionStep(String)

  public var errorDescription: String? {
    switch self {
    case .responseTruncated:
      "The model ran out of room before it finished the adjustment. Try again."
    case .responseUnreadable:
      "The model's response couldn't be read as a recipe adjustment. Try again."
    case .emptyProposal:
      "The assistant did not find a concrete recipe adjustment to review."
    case .missingRecipe:
      "The recipe could not be found."
    case let .unresolvedIngredient(text):
      "The adjustment references an ingredient that could not be matched: \(text)"
    case let .unresolvedInstructionStep(text):
      "The adjustment references an instruction step that could not be matched: \(text)"
    }
  }
}

public struct RecipeAdjustmentProposal: Equatable, Sendable {
  public var summary: String
  public var ingredientOps: [RecipeIngredientDelta]
  public var methodNote: String?
  public var methodStepReplacements: [RecipeMethodStepReplacement]

  public init(
    summary: String = "",
    ingredientOps: [RecipeIngredientDelta] = [],
    methodNote: String? = nil,
    methodStepReplacements: [RecipeMethodStepReplacement] = []
  ) {
    self.summary = summary
    self.ingredientOps = ingredientOps
    self.methodNote = methodNote
    self.methodStepReplacements = methodStepReplacements
  }

  public var isEmpty: Bool {
    ingredientOps.isEmpty
      && methodStepReplacements.isEmpty
      && (methodNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  public func reviewSummary() -> String {
    var lines: [String] = []
    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSummary.isEmpty {
      lines.append(trimmedSummary)
    }
    if !ingredientOps.isEmpty {
      lines.append("\(ingredientOps.count) ingredient \(ingredientOps.count == 1 ? "change" : "changes").")
    }
    if !methodStepReplacements.isEmpty {
      lines.append("\(methodStepReplacements.count) instruction \(methodStepReplacements.count == 1 ? "change" : "changes").")
    }
    if let methodNote = methodNote?.trimmingCharacters(in: .whitespacesAndNewlines), !methodNote.isEmpty {
      lines.append("Method note: \(methodNote)")
    }
    return lines.joined(separator: "\n")
  }

  public func proposedDetail(
    applyingTo detail: RecipeDetailData,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeDetailData {
    var ingredientSections = detail.ingredientSections
    var ingredientLines = sortedIngredientLines(detail.ingredientLines, sections: ingredientSections)
    for op in ingredientOps {
      switch op {
      case let .add(line, sectionName):
        guard let section = targetIngredientSection(
          named: sectionName,
          sections: &ingredientSections,
          recipeID: detail.recipe.id,
          uuid: uuid
        ) else { continue }
        if let line = newIngredientLine(
          line,
          recipeID: detail.recipe.id,
          sectionID: section.id,
          sortOrder: nextIngredientSortOrder(in: section.id, lines: ingredientLines),
          uuid: uuid
        ) {
          ingredientLines.append(line)
        }

      case let .remove(reference):
        guard let index = reference.index(in: ingredientLines) else {
          throw RecipeAdjustmentError.unresolvedIngredient(reference.displayText)
        }
        ingredientLines.remove(at: index)

      case let .substitute(reference, line), let .scale(reference, line):
        guard let index = reference.index(in: ingredientLines) else {
          throw RecipeAdjustmentError.unresolvedIngredient(reference.displayText)
        }
        ingredientLines[index] = ingredientLines[index].replacingOriginalText(with: line)
      }
      ingredientLines = sortedIngredientLines(ingredientLines, sections: ingredientSections)
    }

    var instructionSteps = sortedInstructionSteps(detail.instructionSteps, sections: detail.instructionSections)
    for replacement in methodStepReplacements {
      guard let index = replacement.index(in: instructionSteps) else {
        throw RecipeAdjustmentError.unresolvedInstructionStep(replacement.displayText)
      }
      instructionSteps[index].text = replacement.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let notes = notesWithMethodNote(
      existing: detail.notes,
      methodNote: methodNote,
      recipeID: detail.recipe.id,
      now: now,
      uuid: uuid
    )
    var recipe = detail.recipe
    recipe.dateModified = now
    return RecipeDetailData(
      recipe: recipe,
      source: detail.source,
      ingredientSections: ingredientSections.sorted { $0.sortOrder < $1.sortOrder },
      ingredientLines: ingredientLines,
      instructionSections: detail.instructionSections.sorted { $0.sortOrder < $1.sortOrder },
      instructionSteps: instructionSteps,
      notes: notes,
      photos: detail.photos,
      tags: detail.tags,
      categories: detail.categories,
      categoryDisplayNames: detail.categoryDisplayNames,
      equipment: detail.equipment,
      recipeEquipment: detail.recipeEquipment
    )
  }
}

public enum RecipeIngredientDelta: Equatable, Sendable {
  case add(line: String, sectionName: String?)
  case remove(RecipeIngredientReference)
  case substitute(RecipeIngredientReference, line: String)
  case scale(RecipeIngredientReference, line: String)
}

public struct RecipeIngredientReference: Equatable, Sendable {
  public var id: IngredientLine.ID?
  public var originalText: String?

  public init(id: IngredientLine.ID? = nil, originalText: String? = nil) {
    self.id = id
    self.originalText = originalText
  }

  public var displayText: String {
    originalText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAdjustmentText
      ?? id?.uuidString
      ?? "unknown ingredient"
  }

  fileprivate func index(in lines: [IngredientLine]) -> Int? {
    if let id, let existingIndex = lines.firstIndex(where: { $0.id == id }) {
      return existingIndex
    }
    guard let originalText = originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !originalText.isEmpty else {
      return nil
    }
    return lines.firstIndex { $0.originalText.trimmingCharacters(in: .whitespacesAndNewlines) == originalText }
  }
}

public struct RecipeMethodStepReplacement: Equatable, Sendable {
  public var id: InstructionStep.ID?
  public var stepNumber: Int?
  public var originalText: String?
  public var replacementText: String

  public init(
    id: InstructionStep.ID? = nil,
    stepNumber: Int? = nil,
    originalText: String? = nil,
    replacementText: String
  ) {
    self.id = id
    self.stepNumber = stepNumber
    self.originalText = originalText
    self.replacementText = replacementText
  }

  public var displayText: String {
    originalText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAdjustmentText
      ?? stepNumber.map { "step \($0)" }
      ?? id?.uuidString
      ?? "unknown step"
  }

  fileprivate func index(in steps: [InstructionStep]) -> Int? {
    if let id, let existingIndex = steps.firstIndex(where: { $0.id == id }) {
      return existingIndex
    }
    if let stepNumber {
      let index = stepNumber - 1
      if steps.indices.contains(index) { return index }
    }
    guard let originalText = originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !originalText.isEmpty else {
      return nil
    }
    return steps.firstIndex { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == originalText }
  }
}

public struct RecipeAdjustmentClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ detail: RecipeDetailData,
    _ tier: ModelTier
  ) async throws -> RecipeAdjustmentProposal

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ detail: RecipeDetailData,
      _ tier: ModelTier
    ) async throws -> RecipeAdjustmentProposal
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    detail: RecipeDetailData,
    tier: ModelTier
  ) async throws -> RecipeAdjustmentProposal {
    try await extract(selection, messages, detail, tier)
  }
}

extension RecipeAdjustmentClient: DependencyKey {
  public static let liveValue = RecipeAdjustmentClient { selection, messages, detail, tier in
    @Dependency(\.modelClient) var modelClient
    let request = ModelRequest(
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, detail: detail),
      // Same ceiling as WorkbenchDraftRecipe: reasoning models share this budget between thinking and
      // output, and the extractor must have enough room to emit complete strict JSON instead of a
      // partial delta. Billing is for tokens used, so the high ceiling avoids truncation without
      // forcing high spend on small adjustments.
      maxTokens: 16_384,
      reasoningEffort: .high
    )
    let response = try await modelClient.complete(request)
    let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if response.wasTruncated || trimmed.isEmpty {
      throw RecipeAdjustmentError.responseTruncated
    }
    guard jsonObject(in: response.text) != nil else {
      throw RecipeAdjustmentError.responseUnreadable
    }
    let proposal = parse(response.text)
    guard !proposal.isEmpty else {
      throw RecipeAdjustmentError.emptyProposal
    }
    return proposal
  }

  public static let testValue = RecipeAdjustmentClient { _, _, _, _ in RecipeAdjustmentProposal() }

  static let instructions = """
    You extract a proposed edit to one existing recipe from a cooking conversation.

    Return ONLY strict JSON:
    {"summary":"brief rationale","ingredientOps":[{"op":"add","line":"new ingredient line","sectionName":"optional existing section name or null"},{"op":"remove","baseIngredientID":"uuid-or-null","originalText":"exact current line"},{"op":"substitute","baseIngredientID":"uuid-or-null","originalText":"exact current line","line":"replacement ingredient line"},{"op":"scale","baseIngredientID":"uuid-or-null","originalText":"exact current line","line":"full replacement ingredient line"}],"methodNote":"optional prose note","methodStepReplacements":[{"baseStepID":"uuid-or-null","stepNumber":1,"originalText":"exact current step","replacementText":"full replacement step text"}]}.

    Emit a structured delta only. Do not return a rewritten recipe. For ingredient edits use only add,
    remove, substitute, and scale. For method edits either write a concise methodNote or replace whole
    step text; do not merge, reorder, or rewrite the whole procedure. Ingredient edits may target any
    section; when adding to a specific section, set sectionName to the exact existing section name. Use
    exact IDs or exact current text from the recipe context when changing existing rows. Return empty
    arrays and null methodNote when there is no concrete edit to review.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], detail: RecipeDetailData) -> String {
    let conversation = messages.isEmpty
      ? "(No conversation yet.)"
      : messages.map { "\($0.role.adjustmentPromptLabel): \($0.text)" }.joined(separator: "\n")
    return """
      Current recipe:
      \(adjustmentContext(detail))

      User-selected subject:
      \(selection.isEmpty ? "(No selected subject.)" : selection)

      Conversation so far:
      \(conversation)

      Extract only the concrete recipe edit the user is asking to review.
      """
  }

  public static func parse(_ text: String) -> RecipeAdjustmentProposal {
    guard let object = jsonObject(in: text) else { return RecipeAdjustmentProposal() }
    return RecipeAdjustmentProposal(
      summary: string("summary", in: object) ?? "",
      ingredientOps: ingredientOps(in: object),
      methodNote: string("methodNote", in: object),
      methodStepReplacements: methodStepReplacements(in: object)
    )
  }

  private static func ingredientOps(in object: [String: Any]) -> [RecipeIngredientDelta] {
    let elements = object["ingredientOps"] as? [[String: Any]] ?? []
    return elements.compactMap { element in
      guard let op = string("op", in: element) else { return nil }
      let reference = RecipeIngredientReference(
        id: uuid("baseIngredientID", in: element),
        originalText: string("originalText", in: element)
      )
      switch op {
      case "add":
        return string("line", in: element).map { .add(line: $0, sectionName: string("sectionName", in: element)) }
      case "remove":
        return .remove(reference)
      case "substitute":
        return string("line", in: element).map { .substitute(reference, line: $0) }
      case "scale":
        return string("line", in: element).map { .scale(reference, line: $0) }
      default:
        return nil
      }
    }
  }

  private static func methodStepReplacements(in object: [String: Any]) -> [RecipeMethodStepReplacement] {
    let elements = object["methodStepReplacements"] as? [[String: Any]] ?? []
    return elements.compactMap { element in
      guard let replacementText = string("replacementText", in: element) else { return nil }
      return RecipeMethodStepReplacement(
        id: uuid("baseStepID", in: element),
        stepNumber: integer("stepNumber", in: element),
        originalText: string("originalText", in: element),
        replacementText: replacementText
      )
    }
  }

  private static func jsonObject(in text: String) -> [String: Any]? {
    guard
      let open = text.firstIndex(of: "{"),
      let close = text.lastIndex(of: "}"),
      open < close,
      let data = String(text[open...close]).data(using: .utf8)
    else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func string(_ key: String, in object: [String: Any]) -> String? {
    if object[key] is NSNull { return nil }
    return (object[key] as? String)?.nonEmptyAdjustmentText
  }

  private static func uuid(_ key: String, in object: [String: Any]) -> UUID? {
    string(key, in: object).flatMap(UUID.init(uuidString:))
  }

  private static func integer(_ key: String, in object: [String: Any]) -> Int? {
    if let int = object[key] as? Int { return int }
    if let double = object[key] as? Double { return Int(double) }
    return string(key, in: object).flatMap(Int.init)
  }
}

extension DependencyValues {
  public var recipeAdjustmentClient: RecipeAdjustmentClient {
    get { self[RecipeAdjustmentClient.self] }
    set { self[RecipeAdjustmentClient.self] = newValue }
  }
}

extension RecipeRepository {
  public static func overwriteRecipeWithAdjustmentProposal(
    _ proposal: RecipeAdjustmentProposal,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Data {
    guard let detail = try fetchDetail(recipeID: recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(recipeID)
    }
    let restorePoint = try adjustmentRestorePoint(for: detail)
    let proposedDetail = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: uuid)
    try Recipe.upsert { proposedDetail.recipe }.execute(db)
    try replaceEditableChildren(
      recipeID: recipeID,
      ingredientSections: proposedDetail.ingredientSections,
      ingredientLines: proposedDetail.ingredientLines,
      instructionSections: proposedDetail.instructionSections,
      instructionSteps: proposedDetail.instructionSteps,
      generalNotes: proposedDetail.notes.filter { $0.noteType == .general },
      in: db
    )
    return restorePoint
  }

  public static func restoreRecipeAdjustment(
    _ restorePoint: Data,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let snapshot = try RecipeBundleCoding.decodeSnapshot(restorePoint)
    var recipe = snapshot.recipe
    recipe.dateModified = now
    try Recipe.upsert { recipe }.execute(db)
    try replaceEditableChildren(
      recipeID: recipeID,
      ingredientSections: snapshot.ingredientSections,
      ingredientLines: snapshot.ingredientLines,
      instructionSections: snapshot.instructionSections,
      instructionSteps: snapshot.instructionSteps,
      generalNotes: snapshot.recipeNotes.filter { $0.noteType == .general },
      in: db
    )
    _ = uuid
  }

  public static func adjustmentRestorePoint(for detail: RecipeDetailData) throws -> Data {
    try RecipeBundleCoding.snapshotData(
      recipe: detail.recipe,
      source: detail.source,
      ingredientSections: detail.ingredientSections,
      ingredientLines: detail.ingredientLines,
      instructionSections: detail.instructionSections,
      instructionSteps: detail.instructionSteps,
      notes: detail.notes,
      tagNames: detail.tags.map(\.name),
      categoryNames: detail.categoryDisplayNames,
      photos: detail.photos,
      equipment: detail.equipment,
      recipeEquipment: detail.recipeEquipment
    )
  }

  private static func replaceEditableChildren(
    recipeID: Recipe.ID,
    ingredientSections: [IngredientSection],
    ingredientLines: [IngredientLine],
    instructionSections: [InstructionSection],
    instructionSteps: [InstructionStep],
    generalNotes: [RecipeNote],
    in db: Database
  ) throws {
    try #sql("DELETE FROM \"ingredientLines\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("DELETE FROM \"ingredientSections\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("DELETE FROM \"instructionSteps\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("DELETE FROM \"instructionSections\" WHERE \"recipeID\" = \(bind: recipeID)").execute(db)
    try #sql("""
      DELETE FROM "recipeNotes"
      WHERE "recipeID" = \(bind: recipeID)
        AND "noteType" = 'general'
      """)
      .execute(db)

    for section in ingredientSections {
      try IngredientSection.insert { section }.execute(db)
    }
    for line in ingredientLines {
      try IngredientLine.insert { line }.execute(db)
    }
    for section in instructionSections {
      try InstructionSection.insert { section }.execute(db)
    }
    for step in instructionSteps {
      try InstructionStep.insert { step }.execute(db)
    }
    for note in generalNotes {
      try RecipeNote.insert { note }.execute(db)
    }
  }
}

private func adjustmentContext(_ detail: RecipeDetailData) -> String {
  let ingredientLinesBySection = Dictionary(grouping: detail.ingredientLines) { $0.sectionID }
  let instructionStepsBySection = Dictionary(grouping: detail.instructionSteps) { $0.sectionID }
  var stepNumber = 1
  var lines: [String] = []
  lines.append("- Title: \(detail.recipe.title)")
  if let summary = detail.recipe.summary { lines.append("- Summary: \(summary)") }
  if let servings = detail.recipe.servingsText { lines.append("- Servings: \(servings)") }
  if let yield = detail.recipe.yieldText { lines.append("- Yield: \(yield)") }
  lines.append("Ingredients:")
  for section in detail.ingredientSections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
    if let name = section.name { lines.append("- Section: \(name)") }
    for line in (ingredientLinesBySection[section.id] ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
      lines.append("  - id=\(line.id.uuidString) text=\(line.originalText)")
    }
  }
  lines.append("Instructions:")
  for section in detail.instructionSections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
    if let name = section.name { lines.append("- Section: \(name)") }
    for step in (instructionStepsBySection[section.id] ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) {
      lines.append("  - id=\(step.id.uuidString) step=\(stepNumber) text=\(step.text)")
      stepNumber += 1
    }
  }
  return lines.joined(separator: "\n")
}

private func targetIngredientSection(
  named sectionName: String?,
  sections: inout [IngredientSection],
  recipeID: Recipe.ID,
  uuid: () -> UUID
) -> IngredientSection? {
  let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }
  if let sectionName,
    let section = sortedSections.first(where: { $0.name?.caseInsensitiveCompare(sectionName) == .orderedSame })
  {
    return section
  }
  if let firstSection = sortedSections.first {
    return firstSection
  }
  let section = IngredientSection(id: uuid(), recipeID: recipeID, sortOrder: 0)
  sections.append(section)
  return section
}

private func newIngredientLine(
  _ text: String,
  recipeID: Recipe.ID,
  sectionID: IngredientSection.ID,
  sortOrder: Int,
  uuid: () -> UUID
) -> IngredientLine? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  var line = IngredientParser.lines(
    from: trimmed,
    recipeID: recipeID,
    sectionID: sectionID,
    uuid: uuid
  ).first ?? IngredientLine(
    id: uuid(),
    recipeID: recipeID,
    sectionID: sectionID,
    originalText: trimmed,
    sortOrder: sortOrder
  )
  line.sortOrder = sortOrder
  return line
}

private func nextIngredientSortOrder(in sectionID: IngredientSection.ID, lines: [IngredientLine]) -> Int {
  lines
    .filter { $0.sectionID == sectionID }
    .map(\.sortOrder)
    .max()
    .map { $0 + 1 }
    ?? 0
}

private func sortedIngredientLines(
  _ lines: [IngredientLine],
  sections: [IngredientSection]
) -> [IngredientLine] {
  let sectionSortOrders = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.sortOrder) })
  return lines.sorted { lhs, rhs in
    let lhsSectionSortOrder = sectionSortOrders[lhs.sectionID] ?? Int.max
    let rhsSectionSortOrder = sectionSortOrders[rhs.sectionID] ?? Int.max
    if lhsSectionSortOrder != rhsSectionSortOrder {
      return lhsSectionSortOrder < rhsSectionSortOrder
    }
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

private func sortedInstructionSteps(
  _ steps: [InstructionStep],
  sections: [InstructionSection]
) -> [InstructionStep] {
  let sectionSortOrders = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.sortOrder) })
  return steps.sorted { lhs, rhs in
    let lhsSectionSortOrder = sectionSortOrders[lhs.sectionID] ?? Int.max
    let rhsSectionSortOrder = sectionSortOrders[rhs.sectionID] ?? Int.max
    if lhsSectionSortOrder != rhsSectionSortOrder {
      return lhsSectionSortOrder < rhsSectionSortOrder
    }
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

private func notesWithMethodNote(
  existing: [RecipeNote],
  methodNote: String?,
  recipeID: Recipe.ID,
  now: Date,
  uuid: () -> UUID
) -> [RecipeNote] {
  guard let methodNote = methodNote?.trimmingCharacters(in: .whitespacesAndNewlines), !methodNote.isEmpty else {
    return existing
  }
  return existing + [
    RecipeNote(id: uuid(), recipeID: recipeID, text: methodNote, noteType: .general, dateCreated: now, dateModified: now)
  ]
}

private extension IngredientLine {
  func replacingOriginalText(with text: String) -> IngredientLine {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var replacement = IngredientParser.lines(
      from: trimmed,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { id }
    ).first ?? IngredientLine(
      id: id,
      recipeID: recipeID,
      sectionID: sectionID,
      originalText: trimmed,
      sortOrder: sortOrder
    )
    replacement.sortOrder = sortOrder
    replacement.comment = comment
    replacement.shoppingCategory = shoppingCategory
    return replacement
  }
}

private extension RecipeChatMessage.Role {
  var adjustmentPromptLabel: String {
    switch self {
    case .user: "User"
    case .assistant: "Assistant"
    }
  }
}

private extension String {
  var nonEmptyAdjustmentText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
