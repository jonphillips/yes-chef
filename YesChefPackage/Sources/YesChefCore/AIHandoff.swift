import Foundation
import SQLiteData

@Table("aiHandoffs")
public struct AIHandoff: Codable, Identifiable, Equatable, Sendable {
  /// The first version of the handoff token and prompt contract.
  public static let initialSchemaVersion = 1

  public let id: UUID
  public var sourceType: AIHandoffSourceType
  public var sourceID: UUID
  public var taskType: AIHandoffTaskType
  public var createdAt: Date
  public var importedAt: Date?
  public var status: AIHandoffStatus
  public var schemaVersion: Int
  public var exportedPrompt: String

  public init(
    id: UUID,
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    taskType: AIHandoffTaskType,
    createdAt: Date,
    importedAt: Date? = nil,
    status: AIHandoffStatus = .awaitingReturn,
    schemaVersion: Int = Self.initialSchemaVersion,
    exportedPrompt: String
  ) {
    self.id = id
    self.sourceType = sourceType
    self.sourceID = sourceID
    self.taskType = taskType
    self.createdAt = createdAt
    self.importedAt = importedAt
    self.status = status
    self.schemaVersion = schemaVersion
    self.exportedPrompt = exportedPrompt
  }
}

public enum AIHandoffSourceType: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case recipe
  case menu
  case mealPlan
  case workbench
}

public enum AIHandoffTaskType: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case prepPlan
  case learning
  case recipeMakeAhead
  case chefItUp
  case serveWith
  case adjustRecipe
  case mealPlanMakeAheadStrategy
  case workbenchCompare

  public func handoffTitle(for objectName: String) -> String {
    "\(handoffTitlePrefix): \(objectName)"
  }

  private var handoffTitlePrefix: String {
    switch self {
    case .prepPlan: "Prep Plan"
    case .learning: "Learnings"
    case .recipeMakeAhead: "Make-ahead"
    case .chefItUp: "Chef It Up"
    case .serveWith: "Serve With"
    case .adjustRecipe: "Adjust Recipe"
    case .mealPlanMakeAheadStrategy: "Make-ahead Strategy"
    case .workbenchCompare: "Compare"
    }
  }
}

/// An independently actionable section of a recipe's Playbook. The content remains in the recipe's
/// existing fields; this identity lets hand-offs and future section metadata stay correctly scoped.
public enum PlaybookSectionKind: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable, Identifiable {
  case makeAhead
  case chefItUp
  case serveWith

  public var id: Self { self }

  public var handoffTaskType: AIHandoffTaskType {
    switch self {
    case .makeAhead: .recipeMakeAhead
    case .chefItUp: .chefItUp
    case .serveWith: .serveWith
    }
  }
}

public extension AIHandoff {
  /// The token identifies a handoff row; its task type is the section key that keeps returns for sibling
  /// Playbook sections of one recipe from cross-routing.
  func matches(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    taskType: AIHandoffTaskType
  ) -> Bool {
    self.sourceType == sourceType && self.sourceID == sourceID && self.taskType == taskType
  }
}

public enum AIHandoffStatus: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case awaitingReturn
  case imported
  case discarded
}

@Table("learnings")
public struct Learning: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var sourceType: AIHandoffSourceType
  public var sourceID: UUID
  /// Sparse ranks are intentional: a human moves one Learning at a time across synced devices, so normal
  /// reorders update only the moved rows. Other `sortOrder` tables are contiguous because they rewrite a
  /// whole generated collection; do not normalize these gaps without changing that sync-conflict tradeoff.
  public var sortOrder: Int
  public var text: String
  public var provenance: LearningProvenance
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    sortOrder: Int = 0,
    text: String,
    provenance: LearningProvenance,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.sourceType = sourceType
    self.sourceID = sourceID
    self.sortOrder = sortOrder
    self.text = text
    self.provenance = provenance
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

public enum LearningProvenance: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case externalHandoff
  case inApp
}

public enum LearningReorderDestination: Equatable, Sendable {
  case before(Learning.ID)
  case end
}

private enum LearningOrdering {
  /// Leaves room for ordinary inserts and moves without rewriting every synced row in a Learning group.
  static let rankStride = 1_024

  static func prependOrders(count: Int, before leadingOrder: Int?) -> [Int] {
    guard count > 0 else { return [] }
    // A first insertion receives rank 0. Every later prepend is negative (for example, -1024 before 0),
    // preserving the pre-ordering newest-first behavior without colliding with the migration backfill.
    let upperBound = leadingOrder ?? rankStride
    let first = upperBound - rankStride * count
    return (0..<count).map { first + rankStride * $0 }
  }

  static func reordered(
    _ learnings: [Learning],
    movingIDs: [Learning.ID],
    destination: LearningReorderDestination
  ) -> [Learning] {
    let movingIDSet = Set(movingIDs)
    let moving = learnings.filter { movingIDSet.contains($0.id) }
    guard !moving.isEmpty else { return learnings }

    var remaining = learnings.filter { !movingIDSet.contains($0.id) }
    switch destination {
    case let .before(id):
      let destinationIndex = remaining.firstIndex { $0.id == id } ?? remaining.endIndex
      remaining.insert(contentsOf: moving, at: destinationIndex)
    case .end:
      remaining.append(contentsOf: moving)
    }
    return remaining
  }

  static func changedOrders(
    for reordered: [Learning],
    movingIDs: [Learning.ID]
  ) -> [Learning.ID: Int] {
    let movingIDSet = Set(movingIDs)
    let movingIndexes = reordered.indices.filter { movingIDSet.contains(reordered[$0].id) }
    guard let firstMovingIndex = movingIndexes.first, let lastMovingIndex = movingIndexes.last else { return [:] }

    let precedingOrder = reordered[..<firstMovingIndex]
      .last(where: { !movingIDSet.contains($0.id) })?
      .sortOrder
    let followingOrder = reordered[(lastMovingIndex + 1)...]
      .first(where: { !movingIDSet.contains($0.id) })?
      .sortOrder
    let movingCount = movingIndexes.count

    if let precedingOrder, let followingOrder {
      let step = (followingOrder - precedingOrder) / (movingCount + 1)
      if step > 0 {
        return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
          (reordered[index].id, precedingOrder + step * (offset + 1))
        })
      }
    } else if let precedingOrder {
      return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
        (reordered[index].id, precedingOrder + rankStride * (offset + 1))
      })
    } else if let followingOrder {
      return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
        (reordered[index].id, followingOrder - rankStride * (movingCount - offset))
      })
    } else {
      return Dictionary(uniqueKeysWithValues: movingIndexes.enumerated().map { offset, index in
        (reordered[index].id, rankStride * offset)
      })
    }

    // No gap remains between neighbors. This rare scoped rebalance is the only time one drag rewrites a
    // whole Learning group; it restores sparse ranks for future one-row moves.
    return Dictionary(uniqueKeysWithValues: reordered.enumerated().map { index, learning in
      (learning.id, rankStride * index)
    })
  }
}

public enum LearningRepository {
  public static func create(_ learning: Learning, in db: Database) throws {
    try Learning.insert { learning }.execute(db)
  }

  /// Inserts only the `texts` whose normalized form is not already stored for `(sourceType, sourceID)`,
  /// also collapsing exact duplicates within the incoming batch. A deterministic exact-match floor against
  /// the append-only dupes ADR-0038 Amd 4 describes — it does not catch paraphrases. Returns the count
  /// actually inserted.
  @discardableResult
  public static func insertNew(
    texts: [String],
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    provenance: LearningProvenance,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Int {
    let existing = try learnings(sourceType: sourceType, sourceID: sourceID, in: db)
    var seen = Set(existing.map { normalizedLearningText($0.text) })
    let newTexts = texts.filter { text in
      let key = normalizedLearningText(text)
      return !key.isEmpty && seen.insert(key).inserted
    }
    let sortOrders = LearningOrdering.prependOrders(count: newTexts.count, before: existing.first?.sortOrder)
    for (text, sortOrder) in zip(newTexts, sortOrders) {
      try create(
        Learning(
          id: uuid(),
          sourceType: sourceType,
          sourceID: sourceID,
          sortOrder: sortOrder,
          text: text,
          provenance: provenance,
          dateCreated: now,
          dateModified: now
        ),
        in: db
      )
    }
    return newTexts.count
  }

  static func normalizedLearningText(_ text: String) -> String {
    text
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  public static func learnings(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    in db: Database
  ) throws -> [Learning] {
    var learnings = try Learning
      .where { $0.sourceType.eq(sourceType) }
      .where { $0.sourceID.eq(sourceID) }
      .fetchAll(db)
    learnings.sort(by: areLearningsInDisplayOrder)
    return learnings
  }

  /// Used by the additive `sortOrder` migration to preserve today's newest-first display before anyone
  /// manually reorders a group.
  public static func backfillSortOrders(in db: Database) throws {
    let learnings = try Learning.fetchAll(db)
    let scopes = Dictionary(grouping: learnings) { learning in
      "\(learning.sourceType.rawValue):\(learning.sourceID.uuidString)"
    }
    for learnings in scopes.values {
      for (index, learning) in learnings.sorted(by: areLearningsInDescendingOrder).enumerated() {
        try Learning.find(learning.id).update {
          $0.sortOrder = #bind(LearningOrdering.rankStride * index)
        }
        .execute(db)
      }
    }
  }

  @discardableResult
  public static func reorder(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    movingIDs: [Learning.ID],
    destination: LearningReorderDestination,
    in db: Database,
    now: Date
  ) throws -> Bool {
    let learnings = try learnings(sourceType: sourceType, sourceID: sourceID, in: db)
    let reordered = LearningOrdering.reordered(learnings, movingIDs: movingIDs, destination: destination)
    guard reordered != learnings else { return false }

    let changedOrders = LearningOrdering.changedOrders(for: reordered, movingIDs: movingIDs)
    for learning in reordered {
      guard let sortOrder = changedOrders[learning.id], sortOrder != learning.sortOrder else { continue }
      try Learning.find(learning.id).update {
        $0.sortOrder = #bind(sortOrder)
        $0.dateModified = #bind(now)
      }
      .execute(db)
    }
    return true
  }

  public static func update(
    id: Learning.ID,
    text: String,
    in db: Database,
    now: Date
  ) throws {
    try Learning.find(id).update {
      $0.text = #bind(text)
      $0.dateModified = #bind(now)
    }
    .execute(db)
  }

  public static func delete(id: Learning.ID, in db: Database) throws {
    try Learning.find(id).delete().execute(db)
  }

  public static func deleteAll(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    in db: Database
  ) throws {
    try Learning
      .where { $0.sourceType.eq(sourceType) }
      .where { $0.sourceID.eq(sourceID) }
      .delete()
      .execute(db)
  }
}

func areLearningsInDescendingOrder(_ lhs: Learning, _ rhs: Learning) -> Bool {
  if lhs.dateCreated != rhs.dateCreated { return lhs.dateCreated > rhs.dateCreated }
  return lhs.id.uuidString > rhs.id.uuidString
}

func areLearningsInDisplayOrder(_ lhs: Learning, _ rhs: Learning) -> Bool {
  if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
  return areLearningsInDescendingOrder(lhs, rhs)
}

public enum AIHandoffRepository {
  public static func create(_ handoff: AIHandoff, in db: Database) throws {
    try AIHandoff.insert { handoff }.execute(db)
  }

  public static func handoff(id: AIHandoff.ID, in db: Database) throws -> AIHandoff? {
    try AIHandoff.find(id).fetchOne(db)
  }

  public static func markImported(id: AIHandoff.ID, at date: Date, in db: Database) throws {
    try AIHandoff.find(id).update {
      $0.importedAt = #bind(date)
      $0.status = #bind(AIHandoffStatus.imported)
    }
    .execute(db)
  }
}

public enum AIHandoffToken {
  public enum PromptMode: Sendable {
    case discuss
    case immediate
  }

  public enum DeliverableFormat: Sendable {
    case menuPrepPlan
    case recipeMakeAhead
    case recipeChefItUp
    case recipeServeWith
    case mealPlanMakeAheadStrategy

    var discussInstruction: String {
      switch self {
      case .menuPrepPlan:
        "return the paste-ready prep plan"
      case .recipeMakeAhead:
        "return the paste-ready recipe make-ahead notes"
      case .recipeChefItUp:
        "return the paste-ready Chef It Up notes"
      case .recipeServeWith:
        "return the paste-ready Serve With suggestions"
      case .mealPlanMakeAheadStrategy:
        "return the paste-ready meal-plan make-ahead strategy"
      }
    }

    var immediateInstruction: String {
      switch self {
      case .menuPrepPlan:
        "Return the completed prep plan in your first response when the menu needs one."
      case .recipeMakeAhead:
        "Return the completed recipe make-ahead notes in your first response when the recipe needs them."
      case .recipeChefItUp:
        "Return the completed Chef It Up notes in your first response when the recipe needs them."
      case .recipeServeWith:
        "Return the completed Serve With suggestions in your first response when the recipe needs them."
      case .mealPlanMakeAheadStrategy:
        "Return the completed meal-plan make-ahead strategy in your first response when the day needs one."
      }
    }

    var example: String {
      switch self {
      case .menuPrepPlan:
        """
        session:
        - task → serves
        """
      case .recipeMakeAhead:
        "- Complete the sauce up to two days ahead and refrigerate."
      case .recipeChefItUp:
        "Bloom the spices in oil before adding the tomatoes."
      case .recipeServeWith:
        "Cilantro-lime rice: Finish with fresh lime juice."
      case .mealPlanMakeAheadStrategy:
        """
        Make-ahead strategy - Dinner
        Two days ahead: Make the sauce.
        """
      }
    }
  }

  public struct RoutedText: Equatable, Sendable {
    public let handoffID: AIHandoff.ID
    public let payload: String
    public let contractVersion: String?

    public init(handoffID: AIHandoff.ID, payload: String, contractVersion: String?) {
      self.handoffID = handoffID
      self.payload = payload
      self.contractVersion = contractVersion
    }
  }

  public static let prefix = "YC-HANDOFF:"

  public static func prompt(
    handoffID: AIHandoff.ID,
    title: String,
    context: String,
    mode: PromptMode = .discuss,
    deliverableFormat: DeliverableFormat = .menuPrepPlan
  ) -> String {
    let token = header(handoffID: handoffID)
    switch mode {
    case .discuss:
      return """
      \(title)

      \(token)

      \(context)

      You may discuss this freely. When the user asks you to finalize, \(deliverableFormat.discussInstruction). Follow the Yes Chef project instructions for the terminal return block.

      Keep the deliverable practical, atomic, and grounded in the provided context. Never write choreography or a merged mega-recipe: recipe cooking instructions stay with their recipes.
      """
    case .immediate:
      return """
      \(title)

      \(token)

      \(context)

      \(deliverableFormat.immediateInstruction) Follow the Yes Chef project instructions for the terminal return block. Keep the deliverable practical, atomic, and grounded in the provided context; never choreography or a merged mega-recipe. Use this exact format:
      \(deliverableFormat.example)
      """
    }
  }

  public static func header(handoffID: AIHandoff.ID) -> String {
    "\(prefix) \(handoffID.uuidString)"
  }

  public static func stripping(from text: String) -> RoutedText? {
    var lines = text.components(separatedBy: .newlines)
    guard let firstLine = lines.first else { return nil }
    let trimmedHeader = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedHeader.hasPrefix(prefix) else { return nil }

    let rawID = trimmedHeader.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    guard let handoffID = UUID(uuidString: String(rawID)) else { return nil }

    lines.removeFirst()
    let contractVersion = AIHandoffProjectContract.returnedVersion(in: lines)
    lines.removeAll(where: AIHandoffProjectContract.isVersionMarker)
    return RoutedText(
      handoffID: handoffID,
      payload: lines.joined(separator: "\n"),
      contractVersion: contractVersion
    )
  }
}

/// The v1 instructions that the cook pastes into the shared Yes Chef project. Keeping the exact return
/// contract here lets the app reject a stale paste instead of silently accepting a differently-shaped return.
public enum AIHandoffProjectContract {
  public static let version = "v1"
  public static let versionMarker = "YC-CONTRACT: \(version)"

  public static let instructions = """
  You are the external deliberation partner for Yes Chef. The first line of each prompt is its suggested thread title; preserve that title when your chat app allows it, but never treat it as data.

  Discuss the request normally. Only when the user says to finalize, emit a terminal return block and nothing else:
  1. First line: repeat the prompt's `YC-HANDOFF: <UUID>` token exactly.
  2. Second line: `\(versionMarker)`.
  3. Then emit the requested deliverable. If the prompt permits learnings, put them after a `YC-LEARNINGS:` line as distinct bullets. A learning-only return may leave the deliverable empty.

  In a terminal return block: no preamble, sign-off, headings, or nesting; do not assess what is already good; do not merge distinct requested items into a summary; and omit an item rather than inventing a partial answer.
  """

  public static func isCurrent(version: String?) -> Bool {
    version == Self.version
  }

  static func returnedVersion(in lines: [String]) -> String? {
    lines.first(where: isVersionMarker).map { line in
      line
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .dropFirst("YC-CONTRACT:".count)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  static func isVersionMarker(_ line: String) -> Bool {
    line
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .hasPrefix("YC-CONTRACT:")
  }
}

public struct AIHandoffMenuPrepPlanReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let menuID: Menu.ID
  public let plan: MenuPrepPlan
  public let learnings: [String]
  public let unparsedPlanLines: [String]

  public init(
    handoffID: AIHandoff.ID,
    menuID: Menu.ID,
    plan: MenuPrepPlan,
    learnings: [String],
    unparsedPlanLines: [String] = []
  ) {
    self.handoffID = handoffID
    self.menuID = menuID
    self.plan = plan
    self.learnings = learnings
    self.unparsedPlanLines = unparsedPlanLines
  }
}

public struct AIHandoffRecipeMakeAheadReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let recipeID: Recipe.ID
  public let makeAhead: String
  public let currentMakeAhead: String?
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    recipeID: Recipe.ID,
    makeAhead: String,
    currentMakeAhead: String? = nil,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.recipeID = recipeID
    self.makeAhead = makeAhead
    self.currentMakeAhead = currentMakeAhead
    self.learnings = learnings
  }
}

public struct AIHandoffRecipeSectionReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let recipeID: Recipe.ID
  public let section: PlaybookSectionKind
  public let text: String
  public let currentText: String?
  public let currentServeWith: [ServeWithItem]
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    recipeID: Recipe.ID,
    section: PlaybookSectionKind,
    text: String,
    currentText: String? = nil,
    currentServeWith: [ServeWithItem] = [],
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.recipeID = recipeID
    self.section = section
    self.text = text
    self.currentText = currentText
    self.currentServeWith = currentServeWith
    self.learnings = learnings
  }
}

public struct AIHandoffMealPlanMakeAheadReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let mealPlanItemID: MealPlanItem.ID
  public let scheduledDate: Date
  public let strategy: MealPlanMakeAheadStrategy
  public let learnings: [String]
  public let unparsedStrategyLines: [String]

  public init(
    handoffID: AIHandoff.ID,
    mealPlanItemID: MealPlanItem.ID,
    scheduledDate: Date,
    strategy: MealPlanMakeAheadStrategy,
    learnings: [String],
    unparsedStrategyLines: [String]
  ) {
    self.handoffID = handoffID
    self.mealPlanItemID = mealPlanItemID
    self.scheduledDate = scheduledDate
    self.strategy = strategy
    self.learnings = learnings
    self.unparsedStrategyLines = unparsedStrategyLines
  }
}

public struct AIHandoffWorkbenchCompareReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let workbenchID: Workbench.ID
  public let text: String

  public init(handoffID: AIHandoff.ID, workbenchID: Workbench.ID, text: String) {
    self.handoffID = handoffID
    self.workbenchID = workbenchID
    self.text = text
  }
}

public enum AIHandoffReview: Equatable, Sendable {
  case menuPrepPlan(AIHandoffMenuPrepPlanReview)
  case recipeMakeAhead(AIHandoffRecipeMakeAheadReview)
  case recipeChefItUp(AIHandoffRecipeSectionReview)
  case recipeServeWith(AIHandoffRecipeSectionReview)
  case mealPlanMakeAhead(AIHandoffMealPlanMakeAheadReview)
  case workbenchCompare(AIHandoffWorkbenchCompareReview)

  public var handoffID: AIHandoff.ID {
    switch self {
    case let .menuPrepPlan(review): review.handoffID
    case let .recipeMakeAhead(review): review.handoffID
    case let .recipeChefItUp(review): review.handoffID
    case let .recipeServeWith(review): review.handoffID
    case let .mealPlanMakeAhead(review): review.handoffID
    case let .workbenchCompare(review): review.handoffID
    }
  }
}

public enum AIHandoffReturn {
  public struct MenuPrepPlanReturn: Equatable, Sendable {
    public var plan: MenuPrepPlan
    public var learnings: [String]
    public var unparsedLines: [String]
  }

  public static let learningsMarker = "YC-LEARNINGS:"

  public static func menuPrepPlan(
    from text: String,
    currentPlan: MenuPrepPlan
  ) -> MenuPrepPlanReturn {
    let split = splitting(text)
    let parsed = currentPlan.parsingEditableReviewText(split.deliverable)
    return MenuPrepPlanReturn(
      plan: parsed.plan,
      learnings: learningBullets(from: split.learnings),
      unparsedLines: parsed.unparsedLines
    )
  }

  public static func plainText(from text: String) -> (deliverable: String, learnings: [String]) {
    let split = splitting(text)
    return (
      split.deliverable.trimmingCharacters(in: .whitespacesAndNewlines),
      learningBullets(from: split.learnings)
    )
  }

  public static func learningBullets(from text: String) -> [String] {
    var seen = Set<String>()
    return text.components(separatedBy: .newlines).compactMap { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      let bullet: String?
      if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
        bullet = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        bullet = nil
      }
      guard let bullet, !bullet.isEmpty, seen.insert(bullet).inserted else { return nil }
      return bullet
    }
  }

  private static func splitting(_ text: String) -> (deliverable: String, learnings: String) {
    let lines = text.components(separatedBy: .newlines)
    guard let markerIndex = lines.firstIndex(where: isLearningsMarker) else {
      return (text, "")
    }
    return (
      lines[..<markerIndex].joined(separator: "\n"),
      lines[lines.index(after: markerIndex)...].joined(separator: "\n")
    )
  }

  private static func isLearningsMarker(_ line: String) -> Bool {
    line
      .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#*")))
      .caseInsensitiveCompare(learningsMarker) == .orderedSame
  }
}

public enum AIHandoffIntentImportError: Error, Equatable, LocalizedError, CustomStringConvertible, Sendable {
  case missingHandoffID
  case handoffNotFound(AIHandoff.ID)
  case wrongTask
  case duplicate
  case emptyPlan
  case unparsedPlanText([String])
  case outdatedProjectInstructions

  public var errorDescription: String? {
    switch self {
    case .missingHandoffID:
      "This result does not include a Yes Chef handoff ID."
    case .handoffNotFound:
      "This handoff is not available on this device."
    case .wrongTask:
      "This handoff does not contain a prep plan."
    case .duplicate:
      "This handoff result was already imported for review."
    case .emptyPlan:
      "The returned handoff needs a deliverable or at least one learning bullet."
    case let .unparsedPlanText(lines):
      "Could not import these prep-plan lines: \(lines.joined(separator: " | "))"
    case .outdatedProjectInstructions:
      "Your Yes Chef project instructions are out of date. Re-copy them from Settings and try again."
    }
  }

  public var description: String { errorDescription ?? "The handoff result could not be imported." }
}

public enum AIHandoffIntentImport {
  /// Stages a returned menu prep plan exactly once. Marking the local session imported before opening the
  /// review sheet is deliberate: a shortcut can deliver the same result twice, while the sheet remains the
  /// only place that writes the durable menu artifact.
  public static func stageMenuPrepPlanReview(
    handoffID: AIHandoff.ID?,
    result: String,
    in db: Database,
    now: Date
  ) throws -> AIHandoffMenuPrepPlanReview {
    guard case let .menuPrepPlan(review) = try stageReview(
      handoffID: handoffID,
      result: result,
      in: db,
      now: now
    ) else {
      throw AIHandoffIntentImportError.wrongTask
    }
    return review
  }

  public static func stageReview(
    handoffID: AIHandoff.ID?,
    result: String,
    in db: Database,
    now: Date
  ) throws -> AIHandoffReview {
    let routedText = AIHandoffToken.stripping(from: result)
    guard let resolvedHandoffID = handoffID ?? routedText?.handoffID else {
      throw AIHandoffIntentImportError.missingHandoffID
    }
    guard let handoff = try AIHandoffRepository.handoff(id: resolvedHandoffID, in: db) else {
      throw AIHandoffIntentImportError.handoffNotFound(resolvedHandoffID)
    }
    guard AIHandoffProjectContract.isCurrent(version: routedText?.contractVersion) else {
      throw AIHandoffIntentImportError.outdatedProjectInstructions
    }
    guard handoff.status == .awaitingReturn, handoff.importedAt == nil else {
      throw AIHandoffIntentImportError.duplicate
    }
    let payload = routedText?.payload ?? result
    let review: AIHandoffReview
    switch handoff.sourceType {
    case .menu:
      guard handoff.taskType == .prepPlan || handoff.taskType == .learning,
        let menu = try Menu.find(handoff.sourceID).fetchOne(db)
      else {
        throw AIHandoffIntentImportError.wrongTask
      }
      let currentSteps = try PrepPlanStepRepository.steps(for: menu.id, in: db)
      let returned = AIHandoffReturn.menuPrepPlan(
        from: payload,
        currentPlan: MenuPrepPlan(steps: currentSteps.map { PrepPlanStep($0) })
      )
      guard !returned.plan.steps.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      review = .menuPrepPlan(
        AIHandoffMenuPrepPlanReview(
          handoffID: handoff.id,
          menuID: menu.id,
          plan: returned.plan,
          learnings: returned.learnings,
          unparsedPlanLines: returned.unparsedLines
        )
      )

    case .recipe:
      guard
        handoff.taskType == .recipeMakeAhead || handoff.taskType == .chefItUp
          || handoff.taskType == .serveWith || handoff.taskType == .learning,
        let recipe = try Recipe.find(handoff.sourceID).fetchOne(db), !recipe.archived
      else {
        throw AIHandoffIntentImportError.wrongTask
      }
      let returned = AIHandoffReturn.plainText(from: payload)
      guard !returned.deliverable.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      switch handoff.taskType {
      case .recipeMakeAhead, .learning:
        review = .recipeMakeAhead(
          AIHandoffRecipeMakeAheadReview(
            handoffID: handoff.id,
            recipeID: recipe.id,
            makeAhead: returned.deliverable,
            currentMakeAhead: recipe.makeAhead,
            learnings: returned.learnings
          )
        )
      case .chefItUp:
        review = .recipeChefItUp(
          AIHandoffRecipeSectionReview(
            handoffID: handoff.id,
            recipeID: recipe.id,
            section: .chefItUp,
            text: returned.deliverable,
            currentText: recipe.chefItUp,
            learnings: returned.learnings
          )
        )
      case .serveWith:
        review = .recipeServeWith(
          AIHandoffRecipeSectionReview(
            handoffID: handoff.id,
            recipeID: recipe.id,
            section: .serveWith,
            text: returned.deliverable,
            currentServeWith: ServeWithCoding.decode(recipe.serveWith),
            learnings: returned.learnings
          )
        )
      case .prepPlan, .adjustRecipe, .mealPlanMakeAheadStrategy, .workbenchCompare:
        throw AIHandoffIntentImportError.wrongTask
      }

    case .mealPlan:
      guard handoff.taskType == .mealPlanMakeAheadStrategy || handoff.taskType == .learning,
        let item = try MealPlanItem.find(handoff.sourceID).fetchOne(db)
      else {
        throw AIHandoffIntentImportError.wrongTask
      }
      let returned = AIHandoffReturn.plainText(from: payload)
      let parsed = MealPlanMakeAheadStrategy.parsingEditableReviewText(returned.deliverable)
      guard !parsed.strategy.steps.isEmpty || !returned.learnings.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      review = .mealPlanMakeAhead(
        AIHandoffMealPlanMakeAheadReview(
          handoffID: handoff.id,
          mealPlanItemID: item.id,
          scheduledDate: item.scheduledDate,
          strategy: parsed.strategy,
          learnings: returned.learnings,
          unparsedStrategyLines: parsed.unparsedLines
        )
      )

    case .workbench:
      guard handoff.taskType == .workbenchCompare,
        try Workbench.find(handoff.sourceID).fetchOne(db) != nil
      else {
        throw AIHandoffIntentImportError.wrongTask
      }
      let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        throw AIHandoffIntentImportError.emptyPlan
      }
      review = .workbenchCompare(
        AIHandoffWorkbenchCompareReview(
          handoffID: handoff.id,
          workbenchID: handoff.sourceID,
          text: text
        )
      )
    }

    try AIHandoffRepository.markImported(id: handoff.id, at: now, in: db)
    return review
  }
}

public enum AIHandoffMenuPrepPlanImportResult: Equatable, Sendable {
  case applied
  case imported
  case duplicate
}

public enum AIHandoffMenuPrepPlanImportError: Error, Equatable, LocalizedError, CustomStringConvertible, Sendable {
  case emptyPlan
  case wrongMenu
  case wrongTask
  case unparsedPlanText([String])

  public var errorDescription: String? {
    switch self {
    case .emptyPlan:
      "The pasted handoff needs prep steps or at least one learning bullet."
    case .wrongMenu:
      "This handoff belongs to a different menu."
    case .wrongTask:
      "This handoff does not contain a supported result."
    case let .unparsedPlanText(lines):
      "Could not import these prep-plan lines: \(lines.joined(separator: " | "))"
    }
  }

  public var description: String { errorDescription ?? "The handoff could not be imported." }
}

public enum AIHandoffMenuPrepPlanImport {
  public static func apply(
    text: String,
    to menuID: Menu.ID,
    currentPlan: MenuPrepPlan,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> AIHandoffMenuPrepPlanImportResult {
    let routedText = AIHandoffToken.stripping(from: text)

    if let routedText, let handoff = try AIHandoffRepository.handoff(id: routedText.handoffID, in: db) {
      guard handoff.sourceType == .menu, handoff.sourceID == menuID else {
        throw AIHandoffMenuPrepPlanImportError.wrongMenu
      }
      guard handoff.taskType == .prepPlan || handoff.taskType == .learning else {
        throw AIHandoffMenuPrepPlanImportError.wrongTask
      }
      guard handoff.status == .awaitingReturn, handoff.importedAt == nil else {
        return .duplicate
      }

      let returned = AIHandoffReturn.menuPrepPlan(
        from: routedText.payload,
        currentPlan: currentPlan
      )
      try apply(returned, to: menuID, in: db, now: now, uuid: uuid)
      try AIHandoffRepository.markImported(id: handoff.id, at: now, in: db)
      return .imported
    }

    let returned = AIHandoffReturn.menuPrepPlan(
      from: routedText?.payload ?? text,
      currentPlan: currentPlan
    )
    try apply(returned, to: menuID, in: db, now: now, uuid: uuid)
    return .applied
  }

  private static func apply(
    _ returned: AIHandoffReturn.MenuPrepPlanReturn,
    to menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard returned.unparsedLines.isEmpty else {
      throw AIHandoffMenuPrepPlanImportError.unparsedPlanText(returned.unparsedLines)
    }
    guard !returned.plan.steps.isEmpty || !returned.learnings.isEmpty else {
      throw AIHandoffMenuPrepPlanImportError.emptyPlan
    }
    if !returned.plan.steps.isEmpty {
      try MenuRepository.applyPrepPlan(returned.plan, to: menuID, in: db, now: now, uuid: uuid)
    }
    try LearningRepository.insertNew(
      texts: returned.learnings,
      sourceType: .menu,
      sourceID: menuID,
      provenance: .externalHandoff,
      in: db,
      now: now,
      uuid: uuid
    )
  }
}
