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
  /// Present only for a menu handoff initiated from one specific day.
  public var dayOffset: Int?
  /// Present only for a recipe-adjustment handoff initiated from one variation.
  public var variationID: RecipeVariation.ID?
  public var createdAt: Date
  public var importedAt: Date?
  public var status: AIHandoffStatus
  public var schemaVersion: Int
  public var regenerates: Bool
  public var exportedPrompt: String

  public init(
    id: UUID,
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    taskType: AIHandoffTaskType,
    dayOffset: Int? = nil,
    variationID: RecipeVariation.ID? = nil,
    createdAt: Date,
    importedAt: Date? = nil,
    status: AIHandoffStatus = .awaitingReturn,
    schemaVersion: Int = Self.initialSchemaVersion,
    regenerates: Bool = false,
    exportedPrompt: String
  ) {
    self.id = id
    self.sourceType = sourceType
    self.sourceID = sourceID
    self.taskType = taskType
    self.dayOffset = dayOffset
    self.variationID = variationID
    self.createdAt = createdAt
    self.importedAt = importedAt
    self.status = status
    self.schemaVersion = schemaVersion
    self.regenerates = regenerates
    self.exportedPrompt = exportedPrompt
  }

  public var prepPlanIntent: AIHandoffPrepPlanIntent {
    regenerates ? .regenerate : .refine
  }
}

public enum AIHandoffPrepPlanIntent: Equatable, Sendable {
  case refine
  case regenerate
}

public enum AIHandoffSourceType: String, Codable, QueryBindable, QueryDecodable, Sendable {
  /// A transient recipe-capture session. Its hand-off can only return to the
  /// still-open capture editor, so it is intentionally not an App Intent source.
  case capture
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
  case mealPlanComplement
  case menuComplement
  case readerFeedbackCuration
  case workbenchCompare
  case workbenchExperiments
  case workbenchDraft

  public var title: String {
    switch self {
    case .prepPlan: "Prep Plan"
    case .learning: "Learnings"
    case .recipeMakeAhead: "Make-ahead"
    case .chefItUp: "Chef It Up"
    case .serveWith: "Serve With"
    case .adjustRecipe: "Adjust Recipe"
    case .mealPlanMakeAheadStrategy: "Make-ahead Strategy"
    case .mealPlanComplement: "Meal-plan Complement"
    case .menuComplement: "Menu Complement"
    case .readerFeedbackCuration: "Reader Feedback"
    case .workbenchCompare: "Compare"
    case .workbenchExperiments: "Experiments"
    case .workbenchDraft: "Draft"
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

  public var deliverableFormat: AIHandoffToken.DeliverableFormat {
    switch self {
    case .makeAhead: .recipeMakeAhead
    case .chefItUp: .recipeChefItUp
    case .serveWith: .recipeServeWith
    }
  }
}

public extension AIHandoff {
  /// The token identifies a handoff row; its task type is the section key that keeps returns for sibling
  /// Playbook sections of one recipe from cross-routing.
  func matches(
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    taskType: AIHandoffTaskType,
    dayOffset: Int? = nil,
    variationID: RecipeVariation.ID? = nil
  ) -> Bool {
    self.sourceType == sourceType
      && self.sourceID == sourceID
      && self.taskType == taskType
      && self.dayOffset == dayOffset
      && self.variationID == variationID
  }
}

public enum AIHandoffStatus: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case awaitingReturn
  case imported
  case discarded
}

/// Whether a prompt is headed to the external hand-off transport or the in-app discussion panel.
/// Onboard prompts omit subject serialization because the chat system prompt already supplies it.
public enum AIHandoffPromptDestination: Equatable, Sendable {
  case outboard
  case onboard
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

public enum LearningOrdering {
  /// Leaves room for ordinary inserts and moves without rewriting every synced row in a Learning group.
  public static let rankStride = 1_024

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
    case menuComplement
    case recipeMakeAhead
    case recipeChefItUp
    case recipeServeWith
    case mealPlanMakeAheadStrategy
    case mealPlanComplement
    case readerFeedbackCuration
    case workbenchExperiments
    case workbenchDraft

    var discussInstruction: String {
      switch self {
      case .menuPrepPlan:
        "the paste-ready prep plan"
      case .menuComplement:
        "the paste-ready menu complements"
      case .recipeMakeAhead:
        "the paste-ready recipe make-ahead notes"
      case .recipeChefItUp:
        "the paste-ready Chef It Up notes"
      case .recipeServeWith:
        "paste-ready Serve With suggestions"
      case .mealPlanMakeAheadStrategy:
        "the paste-ready meal-plan make-ahead strategy"
      case .mealPlanComplement:
        "the paste-ready meal-plan complements"
      case .readerFeedbackCuration:
        "the paste-ready reader-feedback points"
      case .workbenchExperiments:
        "the proposed experiments"
      case .workbenchDraft:
        "the drafted recipe as the schema.org Recipe JSON-LD block described above, then its rationale as a separate block"
      }
    }

    var immediateInstruction: String {
      switch self {
      case .menuPrepPlan:
        "Return the completed prep plan in your first response when the menu needs one."
      case .menuComplement:
        "Return the completed menu complements in your first response when the menu needs them."
      case .recipeMakeAhead:
        "Return the completed recipe make-ahead notes in your first response when the recipe needs them."
      case .recipeChefItUp:
        "Return the completed Chef It Up notes in your first response when the recipe needs them."
      case .recipeServeWith:
        "Return the completed Serve With suggestions in your first response when the recipe needs them."
      case .mealPlanMakeAheadStrategy:
        "Return the completed meal-plan make-ahead strategy in your first response when the day needs one."
      case .mealPlanComplement:
        "Return the completed meal-plan complements in your first response when the day needs them."
      case .readerFeedbackCuration:
        "Return the completed reader-feedback curation in your first response when useful tips exist."
      case .workbenchExperiments:
        "Return the proposed experiments in your first response when the workbench needs them."
      case .workbenchDraft:
        "Return the drafted recipe as the schema.org Recipe JSON-LD block described above, then its rationale as a separate block, in your first response."
      }
    }

  }

  public struct RoutedText: Equatable, Sendable {
    public let handoffID: AIHandoff.ID
    public let payload: String

    public init(handoffID: AIHandoff.ID, payload: String) {
      self.handoffID = handoffID
      self.payload = payload
    }
  }

  public static let prefix = "YC-HANDOFF:"

  /// Assembles a hand-off whose body already carries its own return contract — the recipe-body
  /// adjustment prompt describes both of its finalize outcomes (revision brief vs. new-recipe
  /// JSON-LD) itself. Unlike `prompt(...)`, it appends no generic deliverable instruction: that
  /// single-deliverable tail is meaningless for a body with two finalize shapes, and its
  /// `.menuPrepPlan` default was leaking a stray "return a prep plan" line onto the recipe body.
  public static func selfContainedPrompt(
    handoffID: AIHandoff.ID,
    title: String = "",
    body: String
  ) -> String {
    let titleLine = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let titlePrefix = titleLine.isEmpty ? "" : "\(titleLine)\n"
    return "\(titlePrefix)\(header(handoffID: handoffID))\n\n\(body)"
  }

  public static func prompt(
    handoffID: AIHandoff.ID,
    title: String = "",
    context: String,
    mode: PromptMode = .discuss,
    deliverableFormat: DeliverableFormat = .menuPrepPlan
  ) -> String {
    let token = header(handoffID: handoffID)
    let titleLine = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let titlePrefix = titleLine.isEmpty ? "" : "\(titleLine)\n"
    switch mode {
    case .discuss:
      return "\(titlePrefix)\(token)\n\n\(discussAsk(context: context, deliverableFormat: deliverableFormat))"
    case .immediate:
      return """
      \(titlePrefix)\(token)

      \(context)

      \(deliverableFormat.immediateInstruction)
      """
    }
  }

  /// The conversational opening shared by external hand-offs and onboard seeded discussions.
  /// Transport-specific title and routing-token lines are intentionally added by `prompt` instead.
  public static func discussAsk(
    context: String,
    deliverableFormat: DeliverableFormat = .menuPrepPlan,
    destination: AIHandoffPromptDestination = .outboard
  ) -> String {
    switch destination {
    case .outboard:
      """
      \(context)

      You may discuss this freely. When the user asks you to finalize, return \(deliverableFormat.discussInstruction).
      """
    case .onboard:
      """
      \(context)

      You may discuss this freely. When the user asks you to finalize, return \(deliverableFormat.discussInstruction).

      The format above describes the finalized return, not this conversation — discuss conversationally until the cook asks you to finalize.
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
    return RoutedText(handoffID: handoffID, payload: lines.joined(separator: "\n"))
  }
}

public struct AIHandoffMenuComplementReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let menuID: Menu.ID
  public let plan: MenuComplementPlan
  public let unparsedBlocks: [String]

  public init(
    handoffID: AIHandoff.ID,
    menuID: Menu.ID,
    plan: MenuComplementPlan,
    unparsedBlocks: [String]
  ) {
    self.handoffID = handoffID
    self.menuID = menuID
    self.plan = plan
    self.unparsedBlocks = unparsedBlocks
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

public struct AIHandoffMealPlanComplementReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let mealPlanItemID: MealPlanItem.ID
  public let scheduledDate: Date
  public let plan: MealPlanComplementPlan
  public let unparsedBlocks: [String]

  public init(
    handoffID: AIHandoff.ID,
    mealPlanItemID: MealPlanItem.ID,
    scheduledDate: Date,
    plan: MealPlanComplementPlan,
    unparsedBlocks: [String]
  ) {
    self.handoffID = handoffID
    self.mealPlanItemID = mealPlanItemID
    self.scheduledDate = scheduledDate
    self.plan = plan
    self.unparsedBlocks = unparsedBlocks
  }
}

public struct AIHandoffReaderFeedbackReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let tips: [ReaderFeedbackTip]
  public let unparsedLines: [String]

  public init(
    handoffID: AIHandoff.ID,
    tips: [ReaderFeedbackTip],
    unparsedLines: [String] = []
  ) {
    self.handoffID = handoffID
    self.tips = tips
    self.unparsedLines = unparsedLines
  }
}

public struct AIHandoffWorkbenchCompareReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let workbenchID: Workbench.ID
  public let comparison: String
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    workbenchID: Workbench.ID,
    comparison: String,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.workbenchID = workbenchID
    self.comparison = comparison
    self.learnings = learnings
  }
}

public enum AIHandoffReview: Equatable, Sendable {
  case menuComplement(AIHandoffMenuComplementReview)
  case menuPrepPlan(AIHandoffMenuPrepPlanReview)
  case recipeMakeAhead(AIHandoffRecipeMakeAheadReview)
  case recipeChefItUp(AIHandoffRecipeSectionReview)
  case recipeServeWith(AIHandoffRecipeSectionReview)
  case recipeAdjustmentBrief(AIHandoffRecipeAdjustmentBriefReview)
  case mealPlanMakeAhead(AIHandoffMealPlanMakeAheadReview)
  case mealPlanComplement(AIHandoffMealPlanComplementReview)
  case workbenchCompare(AIHandoffWorkbenchCompareReview)
  case workbenchExperiments(AIHandoffWorkbenchExperimentsReview)
  case workbenchDraft(AIHandoffWorkbenchDraftReview)

  public var handoffID: AIHandoff.ID {
    switch self {
    case let .menuComplement(review): review.handoffID
    case let .menuPrepPlan(review): review.handoffID
    case let .recipeMakeAhead(review): review.handoffID
    case let .recipeChefItUp(review): review.handoffID
    case let .recipeServeWith(review): review.handoffID
    case let .recipeAdjustmentBrief(review): review.handoffID
    case let .mealPlanMakeAhead(review): review.handoffID
    case let .mealPlanComplement(review): review.handoffID
    case let .workbenchCompare(review): review.handoffID
    case let .workbenchExperiments(review): review.handoffID
    case let .workbenchDraft(review): review.handoffID
    }
  }
}

public enum AIHandoffReturn {
  public struct MenuPrepPlanReturn: Equatable, Sendable {
    public var plan: MenuPrepPlan
    public var learnings: [String]
    public var unparsedLines: [String]
  }

  public struct ReaderFeedbackReturn: Equatable, Sendable {
    public var tips: [ReaderFeedbackTip]
    public var unparsedLines: [String]
  }

  public struct PlainTextReturn: Equatable, Sendable {
    public var deliverable: String
    public var learnings: [String]
    public var unparsedLines: [String]
  }

  public struct LearningBulletsReturn: Equatable, Sendable {
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
    let learnings = learningBullets(from: split.learnings)
    return MenuPrepPlanReturn(
      plan: parsed.plan,
      learnings: learnings.learnings,
      unparsedLines: parsed.unparsedLines + learnings.unparsedLines
    )
  }

  public static func omittedCurrentPrepStepEvidence(
    proposedPlan: MenuPrepPlan,
    currentPlan: MenuPrepPlan
  ) -> [String] {
    var proposedByKey = Dictionary(grouping: proposedPlan.steps) { PrepPlanStepVisibleContent($0) }
    return currentPlan.steps.compactMap { step in
      let key = PrepPlanStepVisibleContent(step)
      var candidates = proposedByKey[key] ?? []
      guard !candidates.isEmpty else {
        let serves = step.serves.map { " → \($0)" } ?? ""
        return "Existing prep step missing from returned plan: \(step.session): \(step.task)\(serves)"
      }
      candidates.removeFirst()
      proposedByKey[key] = candidates
      return nil
    }
  }

  public static func droppedSourceDishEvidence(
    proposedPlan: MenuPrepPlan,
    currentPlan: MenuPrepPlan
  ) -> [String] {
    var proposedByContent = Dictionary(grouping: proposedPlan.steps) { PrepPlanStepVisibleContent($0) }
    return currentPlan.steps.compactMap { step in
      guard step.sourceDish != nil else { return nil }

      let content = PrepPlanStepVisibleContent(step)
      var candidates = proposedByContent[content] ?? []
      guard let proposedStep = candidates.first else { return nil }
      candidates.removeFirst()
      proposedByContent[content] = candidates
      guard proposedStep.sourceDish == nil else { return nil }

      let serves = step.serves.map { " → \($0)" } ?? ""
      return "Kept the step but dropped its recipe link (pasted plans can't carry links): \(step.session): \(step.task)\(serves)"
    }
  }

  public static func menuComplement(from text: String, dayCount: Int) -> MenuComplementHandoffParseResult {
    MenuComplementPlan.parsingHandoffText(splitting(text).deliverable, dayCount: dayCount)
  }

  public static func mealPlanComplement(from text: String) -> MealPlanComplementHandoffParseResult {
    MealPlanComplementPlan.parsingHandoffText(splitting(text).deliverable)
  }

  public static func readerFeedback(from text: String, comments: [RawComment] = []) -> [ReaderFeedbackTip] {
    readerFeedbackReturn(from: text, comments: comments).tips
  }

  public static func readerFeedbackReturn(
    from text: String,
    comments: [RawComment] = []
  ) -> ReaderFeedbackReturn {
    let deliverable = splitting(text).deliverable
    if let tips = ReaderFeedbackCurationClient.parseJSONReturn(
      deliverable,
      comments: ReaderFeedbackCurationClient.preparedComments(comments)
    ) {
      return ReaderFeedbackReturn(tips: tips, unparsedLines: [])
    }

    var seen = Set<String>()
    var tips: [ReaderFeedbackTip] = []
    var unparsedLines: [String] = []

    for rawLine in deliverable.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      guard line.lowercased().hasPrefix("tip:") else {
        unparsedLines.append(line)
        continue
      }
      let tipText = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !tipText.isEmpty else {
        unparsedLines.append(line)
        continue
      }
      guard seen.insert(tipText.lowercased()).inserted else { continue }
      tips.append(ReaderFeedbackTip(text: tipText))
    }

    return ReaderFeedbackReturn(tips: tips, unparsedLines: unparsedLines)
  }

  public static func plainText(from text: String) -> PlainTextReturn {
    let split = splitting(text)
    let learnings = learningBullets(from: split.learnings)
    return PlainTextReturn(
      deliverable: split.deliverable.trimmingCharacters(in: .whitespacesAndNewlines),
      learnings: learnings.learnings,
      unparsedLines: learnings.unparsedLines
    )
  }

  public static func learningBullets(from text: String) -> LearningBulletsReturn {
    var seen = Set<String>()
    var learnings: [String] = []
    var unparsedLines: [String] = []

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      let bullet: String?
      if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
        bullet = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        bullet = nil
      }

      guard let bullet, !bullet.isEmpty else {
        unparsedLines.append(line)
        continue
      }
      guard seen.insert(bullet).inserted else { continue }
      learnings.append(bullet)
    }

    return LearningBulletsReturn(learnings: learnings, unparsedLines: unparsedLines)
  }

  static func splitting(_ text: String) -> (deliverable: String, learnings: String) {
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

public enum AIHandoffReturnContractError: Error, Equatable, LocalizedError, Sendable {
  case instructionsOutOfDate

  public var errorDescription: String? {
    "This result uses a newer Yes Chef contract marker. Re-copy the current project instructions from Settings, then try again."
  }
}

public enum AIHandoffIntentImportError: Error, Equatable, LocalizedError, CustomStringConvertible, Sendable {
  case missingHandoffID
  case handoffNotFound(AIHandoff.ID)
  case wrongTask
  case duplicate
  case emptyPlan
  case unparsedPlanText([String])
  case unparsedExperimentBlocks([String])
  case unparsedReaderFeedbackLines([String])
  case unparsedLearningLines([String])

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
    case let .unparsedExperimentBlocks(blocks):
      "Could not import these experiment blocks: \(blocks.joined(separator: " | "))"
    case let .unparsedReaderFeedbackLines(lines):
      "Could not read these reader-feedback lines. Each tip must begin with `Tip:`: \(lines.joined(separator: " | "))"
    case let .unparsedLearningLines(lines):
      "Could not read these learning lines. Each learning must begin with a bullet: \(lines.joined(separator: " | "))"
    }
  }

  public var description: String { errorDescription ?? "The handoff result could not be imported." }
}

public enum AIHandoffIntentImport {}

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
