import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public enum RecipeAdjustmentError: Error, Equatable, LocalizedError {
  case responseTruncated
  case responseUnreadable
  case emptyProposal
  case missingRecipe(Recipe.ID)
  case missingVariation(RecipeVariation.ID)
  case variationPayloadUnreadable(RecipeVariation.ID)
  case variationNeedsReview(String, String)
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
    case .missingVariation:
      "The variation could not be found."
    case .variationPayloadUnreadable:
      "The variation could not be read."
    case let .variationNeedsReview(name, reason):
      "\"\(name)\" needs review before this recipe can be overwritten: \(reason)"
    case let .unresolvedIngredient(text):
      "The adjustment references an ingredient that could not be matched: \(text)"
    case let .unresolvedInstructionStep(text):
      "The adjustment references an instruction step that could not be matched: \(text)"
    }
  }
}

public struct RecipeAdjustmentProposal: Codable, Equatable, Sendable {
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

public struct RecipeVariationPayload: Codable, Equatable, Sendable {
  public var ingredientOps: [RecipeIngredientDelta]
  public var methodStepReplacements: [RecipeMethodStepReplacement]

  public init(
    ingredientOps: [RecipeIngredientDelta],
    methodStepReplacements: [RecipeMethodStepReplacement]
  ) {
    self.ingredientOps = ingredientOps
    self.methodStepReplacements = methodStepReplacements
  }

  public init(proposal: RecipeAdjustmentProposal) {
    self.init(
      ingredientOps: proposal.ingredientOps,
      methodStepReplacements: proposal.methodStepReplacements
    )
  }

  public func encodedData() throws -> Data {
    try JSONEncoder().encode(self)
  }

  public static func decode(_ data: Data?, variationID: RecipeVariation.ID) throws -> Self {
    guard let data else { return Self(ingredientOps: [], methodStepReplacements: []) }
    do {
      return try JSONDecoder().decode(Self.self, from: data)
    } catch {
      throw RecipeAdjustmentError.variationPayloadUnreadable(variationID)
    }
  }
}

public enum RecipeVariationIngredientHighlight: Equatable, Sendable {
  case added
  case removed
  case changed
}

public enum RecipeIngredientDelta: Codable, Equatable, Sendable {
  case add(line: String, sectionName: String?)
  case remove(RecipeIngredientReference)
  case substitute(RecipeIngredientReference, line: String)
  case scale(RecipeIngredientReference, line: String)
}

public struct RecipeIngredientReference: Codable, Equatable, Sendable {
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

public struct RecipeMethodStepReplacement: Codable, Equatable, Sendable {
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
    let request = ModelCall(
      surface: .recipe,
      task: .recipeAdjustment,
      tierResolution: .callerProvided,
      contextLayers: [.systemInstructions, .tasteProfile, .recipe, .selection, .conversation],
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
    let response = try await request.complete(using: modelClient)
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
    try validateVariationsCanRebase(detail.variations, onto: proposedDetail)
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

  public static func keepAdjustmentProposalAsVariation(
    _ proposal: RecipeAdjustmentProposal,
    recipeID: Recipe.ID,
    name: String,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeVariation {
    guard let detail = try fetchDetail(recipeID: recipeID, in: db) else {
      throw RecipeAdjustmentError.missingRecipe(recipeID)
    }
    let variationID = uuid()
    let variation = RecipeVariation(
      id: variationID,
      recipeID: recipeID,
      name: variationName(name, fallback: proposal.summary),
      note: proposal.methodNote?.nonEmptyAdjustmentText,
      sortIndex: try nextVariationSortIndex(recipeID: recipeID, in: db),
      deltas: try RecipeVariationPayload(proposal: proposal).encodedData(),
      origin: .chat,
      dateCreated: now,
      dateModified: now
    )
    _ = try detail.resolved(applying: variation)
    try RecipeVariation.insert { variation }.execute(db)
    try setActiveVariation(variation.id, recipeID: recipeID, in: db, now: now, uuid: uuid)
    return variation
  }

  public static func setActiveVariation(
    _ variationID: RecipeVariation.ID?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    if let variationID {
      guard let variation = try RecipeVariation.find(variationID).fetchOne(db),
            variation.recipeID == recipeID
      else {
        throw RecipeAdjustmentError.missingVariation(variationID)
      }
    }

    try #sql("DELETE FROM \"recipeActiveVariations\" WHERE \"recipeID\" = \(bind: recipeID)")
      .execute(db)

    if let variationID {
      try RecipeActiveVariation.insert {
        RecipeActiveVariation(
          id: uuid(),
          recipeID: recipeID,
          variationID: variationID,
          dateModified: now
        )
      }
      .execute(db)
    }
  }

  public static func renameVariation(
    _ variationID: RecipeVariation.ID,
    to name: String,
    in db: Database,
    now: Date
  ) throws {
    guard let variation = try RecipeVariation.find(variationID).fetchOne(db) else {
      throw RecipeAdjustmentError.missingVariation(variationID)
    }
    try RecipeVariation.find(variationID).update {
      $0.name = variationName(name, fallback: variation.name)
      $0.dateModified = now
    }
    .execute(db)
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
      // Snapshots strip image bytes anyway (leanSnapshotPhotos); the restore path
      // never re-writes photo rows, so a metadata-only conversion is faithful.
      photos: detail.photos.map(\.leanRecipePhoto),
      equipment: detail.equipment,
      recipeEquipment: detail.recipeEquipment
    )
  }

  static func activeVariationID(
    recipeID: Recipe.ID,
    variations: [RecipeVariation],
    in db: Database
  ) throws -> RecipeVariation.ID? {
    let validVariationIDs = Set(variations.map(\.id))
    return try RecipeActiveVariation
      .where { $0.recipeID.eq(recipeID) }
      .fetchAll(db)
      .filter { validVariationIDs.contains($0.variationID) }
      .sorted(by: areActiveVariationsInDecreasingOrder)
      .first?
      .variationID
  }

  private static func validateVariationsCanRebase(
    _ variations: [RecipeVariation],
    onto proposedDetail: RecipeDetailData
  ) throws {
    for variation in variations {
      do {
        _ = try proposedDetail.resolved(applying: variation)
      } catch {
        throw RecipeAdjustmentError.variationNeedsReview(
          variation.name,
          (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        )
      }
    }
  }

  private static func nextVariationSortIndex(recipeID: Recipe.ID, in db: Database) throws -> Int {
    try RecipeVariation
      .where { $0.recipeID.eq(recipeID) }
      .fetchAll(db)
      .map(\.sortIndex)
      .max()
      .map { $0 + 1 }
      ?? 0
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

public extension RecipeDetailData {
  var activeVariation: RecipeVariation? {
    guard let activeVariationID else { return nil }
    return variations.first { $0.id == activeVariationID }
  }

  func resolved(applying variation: RecipeVariation) throws -> RecipeDetailData {
    #if DEBUG
      let clock = ContinuousClock()
      let start = clock.now
      defer {
        let duration = String(describing: start.duration(to: clock.now))
        AppLog.performance.log(
          "recipe-variation-resolve duration=\(duration, privacy: .public)"
        )
      }
    #endif
    let payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variation.id)
    var uuids = VariationUUIDSequence(variationID: variation.id)
    var detail = try RecipeAdjustmentProposal(
      summary: variation.name,
      ingredientOps: payload.ingredientOps,
      methodStepReplacements: payload.methodStepReplacements
    )
    .proposedDetail(applyingTo: self, now: recipe.dateModified, uuid: { uuids.next() })
    detail.variations = variations
    detail.activeVariationID = variation.id
    return detail
  }

  func variationIngredientHighlights(
    for variation: RecipeVariation
  ) throws -> [IngredientLine.ID: RecipeVariationIngredientHighlight] {
    #if DEBUG
      let clock = ContinuousClock()
      let start = clock.now
      defer {
        let duration = String(describing: start.duration(to: clock.now))
        AppLog.performance.log(
          "recipe-variation-highlights duration=\(duration, privacy: .public)"
        )
      }
    #endif
    let payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variation.id)
    let resolvedDetail = try resolved(applying: variation)
    let baseLineIDs = Set(ingredientLines.map(\.id))
    var highlights = Dictionary(
      uniqueKeysWithValues: resolvedDetail.ingredientLines
        .filter { !baseLineIDs.contains($0.id) }
        .map { ($0.id, RecipeVariationIngredientHighlight.added) }
    )

    for op in payload.ingredientOps {
      switch op {
      case .add:
        break
      case let .remove(reference):
        if let index = reference.index(in: ingredientLines) {
          highlights[ingredientLines[index].id] = .removed
        }
      case let .substitute(reference, _), let .scale(reference, _):
        if let index = reference.index(in: ingredientLines) {
          highlights[ingredientLines[index].id] = .changed
        }
      }
    }
    return highlights
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

private struct VariationUUIDSequence {
  private let variationID: RecipeVariation.ID
  private var offset = 0

  init(variationID: RecipeVariation.ID) {
    self.variationID = variationID
  }

  mutating func next() -> UUID {
    defer { offset += 1 }
    return deterministicVariationUUID(variationID: variationID, offset: offset)
  }
}

private func deterministicVariationUUID(variationID: RecipeVariation.ID, offset: Int) -> UUID {
  let uuid = variationID.uuid
  var bytes = [
    uuid.0, uuid.1, uuid.2, uuid.3,
    uuid.4, uuid.5, uuid.6, uuid.7,
    uuid.8, uuid.9, uuid.10, uuid.11,
    uuid.12, uuid.13, uuid.14, uuid.15,
  ]
  var value = UInt64(offset)
  for index in stride(from: bytes.indices.upperBound - 1, through: bytes.indices.upperBound - 8, by: -1) {
    bytes[index] ^= UInt8(value & 0xff)
    value >>= 8
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  return UUID(uuid: (
    bytes[0], bytes[1], bytes[2], bytes[3],
    bytes[4], bytes[5], bytes[6], bytes[7],
    bytes[8], bytes[9], bytes[10], bytes[11],
    bytes[12], bytes[13], bytes[14], bytes[15]
  ))
}

private func variationName(_ name: String, fallback: String) -> String {
  name.nonEmptyAdjustmentText
    ?? fallback.nonEmptyAdjustmentText
    ?? "Variation"
}

private func areActiveVariationsInDecreasingOrder(
  _ lhs: RecipeActiveVariation,
  _ rhs: RecipeActiveVariation
) -> Bool {
  if lhs.dateModified != rhs.dateModified {
    return lhs.dateModified > rhs.dateModified
  }
  return lhs.id.uuidString < rhs.id.uuidString
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
