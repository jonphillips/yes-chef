import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

public enum ServeWithCoding {
  public static func encode(_ items: [ServeWithItem]) throws -> Data? {
    guard !items.isEmpty else { return nil }
    return try JSONEncoder().encode(items)
  }

  public static func decode(
    _ data: Data?,
    recipeID: Recipe.ID
  ) throws(ServeWithCodingError) -> [ServeWithItem] {
    guard let data else { return [] }
    do {
      return try JSONDecoder().decode([ServeWithItem].self, from: data)
    } catch {
      throw ServeWithCodingError.malformedData(recipeID: recipeID)
    }
  }

}

public enum ServeWithCodingError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
  case malformedData(recipeID: Recipe.ID)

  public var recipeID: Recipe.ID {
    switch self {
    case let .malformedData(recipeID): recipeID
    }
  }

  public var errorDescription: String? {
    "Couldn't read Serve With. Its stored data was left unchanged."
  }

  public var description: String { errorDescription ?? "Couldn't read Serve With." }
}

public struct ChefItUpPlan: Equatable, Sendable {
  public var text: String

  public init(text: String) {
    self.text = text
  }
}

/// Presentation-ready text for the prose Playbook sections.
///
/// Multi-line paragraphs read as a list in the Playbook, while a single-line paragraph remains prose.
/// This also normalizes common pasted list markers before applying the app's consistent bullet treatment.
public struct PlaybookEnrichmentDisplayText: Equatable, Sendable {
  public var text: String
  public var hasBulletedLines: Bool

  public init(text: String, hasBulletedLines: Bool) {
    self.text = text
    self.hasBulletedLines = hasBulletedLines
  }
}

public enum PlaybookEnrichmentText {
  public static func displayText(for text: String) -> PlaybookEnrichmentDisplayText {
    let paragraphs = text
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .split(omittingEmptySubsequences: true) { line in
        line.allSatisfy(\.isWhitespace)
      }

    var hasBulletedLines = false
    let renderedParagraphs = paragraphs.map { paragraph in
      guard paragraph.count > 1 else {
        return paragraph.map(String.init).joined(separator: "\n")
      }

      hasBulletedLines = true
      return paragraph
        .map { "• \(strippingLeadingBullet(from: String($0)))" }
        .joined(separator: "\n")
    }

    return PlaybookEnrichmentDisplayText(
      text: renderedParagraphs.joined(separator: "\n\n"),
      hasBulletedLines: hasBulletedLines
    )
  }

  private static func strippingLeadingBullet(from line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let marker = trimmed.first, ["-", "*", "•", "–"].contains(String(marker)) else {
      return trimmed
    }

    let remainder = trimmed.dropFirst()
    guard remainder.first?.isWhitespace == true else { return trimmed }
    return String(remainder.drop(while: \.isWhitespace))
  }
}

public struct ServeWithPlan: Equatable, Sendable {
  public var items: [ServeWithSuggestion]

  public init(items: [ServeWithSuggestion] = []) {
    self.items = items
  }

  public func rendered() -> String {
    items
      .map { item in
        guard let note = item.note else { return item.title }
        return "\(item.title): \(note)"
      }
      .joined(separator: "\n")
  }

  public func editableReviewText() -> String {
    rendered()
  }

  public func applyingEditableReviewText(_ text: String) -> ServeWithPlan {
    ServeWithPlan(
      items: text
        .editableReviewLines
        .compactMap(Self.suggestion(fromEditableReviewLine:))
    )
  }

  /// Keeps every existing suggestion at the top of a handoff review while adding only genuinely new returns.
  public func unioning(_ returnedPlan: ServeWithPlan) -> ServeWithPlan {
    var seen = Set<ServeWithSuggestion>()
    let items = (items + returnedPlan.items).filter { seen.insert($0).inserted }
    return ServeWithPlan(items: items)
  }

  private static func suggestion(fromEditableReviewLine line: String) -> ServeWithSuggestion? {
    let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard let title = String(pieces[0]).removingMarkdownEmphasis.cleanedEnrichmentText else { return nil }
    return ServeWithSuggestion(
      title: title,
      note: pieces.count > 1 ? String(pieces[1]).cleanedEnrichmentText : nil
    )
  }
}

private extension String {
  var removingMarkdownEmphasis: String {
    replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
  }
}

public struct ServeWithSuggestion: Hashable, Sendable {
  public var title: String
  public var note: String?

  public init(title: String, note: String? = nil) {
    self.title = title
    self.note = note
  }
}

public struct ChefItUpPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> ChefItUpPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> ChefItUpPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> ChefItUpPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension ChefItUpPlanClient: DependencyKey {
  public static let liveValue = ChefItUpPlanClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .recipe,
      task: .chefItUp,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 4096,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.chefItUp.rawValue
    )
    let response = try await call.complete(using: modelClient)
    guard !response.wasTruncated else { throw StructuredModelResponseError.responseTruncated }
    return parse(response.text)
  }

  public static let testValue = ChefItUpPlanClient { _, _, _, _ in ChefItUpPlan(text: "") }

  static let instructions = """
    You distill a cooking conversation into practical ways to make one recipe more impressive.
    Return ONLY strict JSON: {"text":"short concrete upgrade plan"}.
    Use only the provided recipe and conversation. Prefer useful technique and flavor upgrades over vague praise.
    Return {"text":""} when there is nothing useful to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    enrichmentPrompt(
      selection: selection,
      messages: messages,
      context: context,
      task: "Distill the selected subject into a concise Chef It Up plan."
    )
  }

  public static func parse(_ text: String) -> ChefItUpPlan {
    let object = jsonObject(text)
    let value = object?["text"] as? String ?? text
    return ChefItUpPlan(text: value.cleanedEnrichmentText ?? "")
  }
}

public struct ServeWithPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ tier: ModelTier
  ) async throws -> ServeWithPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ tier: ModelTier
    ) async throws -> ServeWithPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    tier: ModelTier
  ) async throws -> ServeWithPlan {
    try await extract(selection, messages, context, tier)
  }
}

extension ServeWithPlanClient: DependencyKey {
  public static let liveValue = ServeWithPlanClient { selection, messages, context, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .recipe,
      task: .serveWith,
      tierResolution: .callerProvided,
      contextLayers: [.recipe, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 4096,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.serveWith.rawValue
    )
    let response = try await call.complete(using: modelClient)
    guard !response.wasTruncated else { throw StructuredModelResponseError.responseTruncated }
    return parse(response.text)
  }

  public static let testValue = ServeWithPlanClient { _, _, _, _ in ServeWithPlan() }

  static let instructions = """
    You distill a cooking conversation into accompaniment ideas for one recipe.
    Return ONLY strict JSON: {"items":[{"title":"short accompaniment name","note":"optional one-sentence note"}]}.
    Do not write full recipes. Keep each item small enough to live as an accompaniment on the parent recipe.
    Return {"items":[]} when there is nothing useful to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    enrichmentPrompt(
      selection: selection,
      messages: messages,
      context: context,
      task: "Distill the selected subject into Serve With accompaniment items."
    )
  }

  public static func parse(_ text: String) -> ServeWithPlan {
    guard let raw = jsonObject(text) else { return ServeWithPlan() }
    let elements = raw["items"] as? [[String: Any]] ?? []
    return ServeWithPlan(
      items: elements.compactMap { element in
        guard let title = (element["title"] as? String)?.cleanedEnrichmentText else { return nil }
        return ServeWithSuggestion(
          title: title,
          note: (element["note"] as? String)?.cleanedEnrichmentText
        )
      }
    )
  }
}

extension DependencyValues {
  public var chefItUpPlanClient: ChefItUpPlanClient {
    get { self[ChefItUpPlanClient.self] }
    set { self[ChefItUpPlanClient.self] = newValue }
  }

  public var serveWithPlanClient: ServeWithPlanClient {
    get { self[ServeWithPlanClient.self] }
    set { self[ServeWithPlanClient.self] = newValue }
  }
}

extension RecipeRepository {
  public static func applyChefItUpPlan(
    _ plan: ChefItUpPlan,
    to recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try updateChefItUp(plan.text.nonEmptyEnrichmentText, recipeID: recipeID, in: db, now: now)
  }

  public static func updateChefItUp(
    _ chefItUp: String?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try Recipe.find(recipeID).update {
      $0.chefItUp = chefItUp
      $0.dateModified = now
    }
    .execute(db)
  }

  public static func clearChefItUp(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try updateChefItUp(nil, recipeID: recipeID, in: db, now: now)
  }

  public static func appendServeWithPlan(
    _ plan: ServeWithPlan,
    to recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    try RecipeServeWithRepository.append(
      plan.items,
      to: recipeID,
      provenance: .model,
      in: db,
      now: now,
      uuid: uuid
    )
  }

  public static func replaceServeWithPlan(
    _ plan: ServeWithPlan,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    try RecipeServeWithRepository.replaceModelSuggestions(
      plan.items,
      for: recipeID,
      in: db,
      now: now,
      uuid: uuid
    )
  }

  public static func removeServeWithItem(
    _ itemID: ServeWithItem.ID,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try RecipeServeWithRepository.delete(id: itemID, in: db, now: now)
  }

  public static func clearServeWith(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try RecipeServeWithRepository.deleteAll(for: recipeID, in: db, now: now)
  }

  /// Replaces an unreadable Serve With blob only after the cook's edited bytes decode as a complete list.
  /// The data is stored exactly as supplied: this recovery path must not silently normalize or discard it.
  public static func repairServeWith(
    _ data: Data,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    _ = try ServeWithCoding.decode(data, recipeID: recipeID)
    try updateServeWithData(data, recipeID: recipeID, in: db, now: now)
  }

  private static func updateServeWithData(
    _ data: Data?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try Recipe.find(recipeID).update {
      $0.serveWith = data
      $0.dateModified = now
    }
    .execute(db)
  }
}

public enum ServeWithReorderDestination: Equatable, Sendable {
  case before(RecipeServeWith.ID)
  case end
}

public enum RecipeServeWithRepository {
  public static func serveWith(for recipeID: Recipe.ID, in db: Database) throws -> [RecipeServeWith] {
    try RecipeServeWith
      .where { $0.recipeID.eq(recipeID) }
      .fetchAll(db)
      .sorted(by: areServeWithInDisplayOrder)
  }

  public static func append(
    _ suggestions: [ServeWithSuggestion],
    to recipeID: Recipe.ID,
    provenance: ServeWithProvenance,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let existing = try serveWith(for: recipeID, in: db)
    let firstSortOrder = (existing.last?.sortOrder ?? -LearningOrdering.rankStride) + LearningOrdering.rankStride
    for (index, suggestion) in suggestions.enumerated() {
      try RecipeServeWith.insert {
        RecipeServeWith(
          id: uuid(),
          recipeID: recipeID,
          title: suggestion.title,
          note: suggestion.note,
          sortOrder: firstSortOrder + LearningOrdering.rankStride * index,
          provenance: provenance,
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
    }
    try touchRecipe(recipeID, in: db, now: now)
  }

  /// Replaces model output by retained row identity while preserving every hand-authored row and its rank.
  public static func replaceModelSuggestions(
    _ suggestions: [ServeWithSuggestion],
    for recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let existing = try serveWith(for: recipeID, in: db)
    var unmatchedModelRows = Dictionary(grouping: existing.filter { $0.provenance == .model }) {
      ServeWithSuggestion(title: $0.title, note: $0.note)
    }
    var retainedIDs = Set<RecipeServeWith.ID>()
    let nextSortOrder = (existing.map(\.sortOrder).max() ?? -LearningOrdering.rankStride) + LearningOrdering.rankStride
    var newItemOffset = 0

    for suggestion in suggestions {
      var candidates = unmatchedModelRows[suggestion] ?? []
      if let existing = candidates.first {
        candidates.removeFirst()
        unmatchedModelRows[suggestion] = candidates
        retainedIDs.insert(existing.id)
        continue
      }
      let row = RecipeServeWith(
        id: uuid(),
        recipeID: recipeID,
        title: suggestion.title,
        note: suggestion.note,
        sortOrder: nextSortOrder + LearningOrdering.rankStride * newItemOffset,
        provenance: .model,
        dateCreated: now,
        dateModified: now
      )
      newItemOffset += 1
      retainedIDs.insert(row.id)
      try RecipeServeWith.insert { row }.execute(db)
    }

    for row in existing where row.provenance == .model && !retainedIDs.contains(row.id) {
      try RecipeServeWith.find(row.id).delete().execute(db)
    }
    try touchRecipe(recipeID, in: db, now: now)
  }

  public static func update(
    id: RecipeServeWith.ID,
    title: String,
    in db: Database,
    now: Date
  ) throws {
    guard let existing = try RecipeServeWith.find(id).fetchOne(db) else { return }
    try RecipeServeWith.find(id).update {
      $0.title = #bind(title)
      $0.dateModified = #bind(now)
    }
    .execute(db)
    try touchRecipe(existing.recipeID, in: db, now: now)
  }

  public static func delete(id: RecipeServeWith.ID, in db: Database, now: Date) throws {
    guard let existing = try RecipeServeWith.find(id).fetchOne(db) else { return }
    try RecipeServeWith.find(id).delete().execute(db)
    try touchRecipe(existing.recipeID, in: db, now: now)
  }

  public static func deleteAll(for recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try RecipeServeWith.where { $0.recipeID.eq(recipeID) }.delete().execute(db)
    try touchRecipe(recipeID, in: db, now: now)
  }

  @discardableResult
  public static func reorder(
    movingIDs: [RecipeServeWith.ID],
    destination: ServeWithReorderDestination,
    for recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws -> Bool {
    let rows = try serveWith(for: recipeID, in: db)
    let movingIDSet = Set(movingIDs)
    let moving = rows.filter { movingIDSet.contains($0.id) }
    guard !moving.isEmpty else { return false }
    var reordered = rows.filter { !movingIDSet.contains($0.id) }
    switch destination {
    case let .before(id):
      reordered.insert(contentsOf: moving, at: reordered.firstIndex { $0.id == id } ?? reordered.endIndex)
    case .end:
      reordered.append(contentsOf: moving)
    }
    guard reordered != rows else { return false }

    let movingIndexes = reordered.indices.filter { movingIDSet.contains(reordered[$0].id) }
    let changedOrders = sparseReorderOrders(rows: reordered, movingIndexes: movingIndexes)
    for row in rows {
      guard let sortOrder = changedOrders[row.id], sortOrder != row.sortOrder else { continue }
      try RecipeServeWith.find(row.id).update {
        $0.sortOrder = #bind(sortOrder)
        $0.dateModified = #bind(now)
      }
      .execute(db)
    }
    try touchRecipe(recipeID, in: db, now: now)
    return true
  }

  private static func touchRecipe(_ recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try Recipe.find(recipeID).update { $0.dateModified = #bind(now) }.execute(db)
  }

  private static func sparseReorderOrders(
    rows: [RecipeServeWith],
    movingIndexes: [Int]
  ) -> [RecipeServeWith.ID: Int] {
    guard let first = movingIndexes.first, let last = movingIndexes.last else { return [:] }
    let movingCount = movingIndexes.count
    let precedingOrder = rows[..<first].last?.sortOrder
    let followingOrder = rows[(last + 1)...].first?.sortOrder

    if let precedingOrder, let followingOrder {
      let step = (followingOrder - precedingOrder) / (movingCount + 1)
      if step > 0 {
        return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
          (rows[index].id, precedingOrder + step * (offset + 1))
        })
      }
    } else if let precedingOrder {
      return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
        (rows[index].id, precedingOrder + LearningOrdering.rankStride * (offset + 1))
      })
    } else if let followingOrder {
      return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
        (rows[index].id, followingOrder - LearningOrdering.rankStride * (movingCount - offset))
      })
    } else {
      return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
        (rows[index].id, LearningOrdering.rankStride * offset)
      })
    }

    return Dictionary(uniqueKeysWithValues: rows.enumerated().map { index, row in
      (row.id, LearningOrdering.rankStride * index)
    })
  }
}

func areServeWithInDisplayOrder(_ lhs: RecipeServeWith, _ rhs: RecipeServeWith) -> Bool {
  lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
}

private func enrichmentPrompt(
  selection: String,
  messages: [RecipeChatMessage],
  context: String,
  task: String
) -> String {
  let conversation = messages.isEmpty
    ? "(No conversation yet.)"
    : messages.map { "\($0.role.promptLabel): \($0.text)" }.joined(separator: "\n")
  return """
    Recipe context:
    \(context)

    User-selected subject:
    \(selection)

    Conversation so far:
    \(conversation)

    \(task)
    """
}

private func jsonObject(_ text: String) -> [String: Any]? {
  guard
    let open = text.firstIndex(of: "{"),
    let close = text.lastIndex(of: "}"),
    open < close,
    let data = String(text[open...close]).data(using: .utf8)
  else { return nil }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
  var editableReviewLines: [String] {
    components(separatedBy: .newlines)
      .map(\.cleanedEditableReviewLine)
      .filter { !$0.isEmpty }
  }

  var cleanedEditableReviewLine: String {
    var line = trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
      line.removeFirst(2)
    } else if line.hasPrefix("• ") {
      line.removeFirst(2)
    } else if let periodIndex = line.firstIndex(of: ".") {
      let prefix = line[..<periodIndex]
      if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
        line = String(line[line.index(after: periodIndex)...])
      }
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedEnrichmentText: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyEnrichmentText
  }

  var nonEmptyEnrichmentText: String? {
    isEmpty ? nil : self
  }
}
