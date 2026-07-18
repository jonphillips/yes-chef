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
}

public enum AIHandoffTaskType: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case prepPlan
  case learning
  case recipeMakeAhead
  case chefItUp
  case serveWith
  case adjustRecipe
  case mealPlanMakeAheadStrategy
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
  public var text: String
  public var provenance: LearningProvenance
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    sourceType: AIHandoffSourceType,
    sourceID: UUID,
    text: String,
    provenance: LearningProvenance,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.sourceType = sourceType
    self.sourceID = sourceID
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
    var inserted = 0
    for text in texts {
      let key = normalizedLearningText(text)
      guard !key.isEmpty, seen.insert(key).inserted else { continue }
      try create(
        Learning(
          id: uuid(),
          sourceType: sourceType,
          sourceID: sourceID,
          text: text,
          provenance: provenance,
          dateCreated: now,
          dateModified: now
        ),
        in: db
      )
      inserted += 1
    }
    return inserted
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
    learnings.sort(by: areLearningsInDescendingOrder)
    return learnings
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
        "return only the token line above as the first line, followed by the paste-ready prep plan"
      case .recipeMakeAhead:
        "return only the token line above as the first line, followed by the paste-ready recipe make-ahead notes"
      case .recipeChefItUp:
        "return only the token line above as the first line, followed by the paste-ready Chef It Up notes"
      case .recipeServeWith:
        "return only the token line above as the first line, followed by paste-ready Serve With suggestions"
      case .mealPlanMakeAheadStrategy:
        "return only the token line above as the first line, followed by the paste-ready meal-plan make-ahead strategy"
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

    public init(handoffID: AIHandoff.ID, payload: String) {
      self.handoffID = handoffID
      self.payload = payload
    }
  }

  public static let prefix = "YC-HANDOFF:"

  public static func prompt(
    handoffID: AIHandoff.ID,
    context: String,
    mode: PromptMode = .discuss,
    deliverableFormat: DeliverableFormat = .menuPrepPlan
  ) -> String {
    let token = header(handoffID: handoffID)
    switch mode {
    case .discuss:
      return """
      \(token)

      \(context)

      You may discuss this freely. When the user asks you to finalize, \(deliverableFormat.discussInstruction), then a YC-LEARNINGS: line and a distinct bullet list of durable knowledge established during the discussion. A learning-only return is valid: leave the deliverable portion empty and include the marker plus bullets. Preserve that token and marker exactly; never merge learnings into a prose summary; do not use a Markdown code fence.

      Keep the deliverable practical, atomic, and grounded in the provided context. Never write choreography or a merged mega-recipe: recipe cooking instructions stay with their recipes.
      """
    case .immediate:
      return """
      \(token)

      \(context)

      \(deliverableFormat.immediateInstruction) Preserve the token above as the first line. Return only the token, formatted deliverable, and a YC-LEARNINGS: section of distinct durable-learning bullets: no preamble and no Markdown code fence. A learning-only return is valid: leave the deliverable portion empty and include the marker plus bullets. Keep the deliverable practical, atomic, and grounded in the provided context; never choreography or a merged mega-recipe. Use this exact format:
      \(deliverableFormat.example)
      YC-LEARNINGS:
      - durable learning
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
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    recipeID: Recipe.ID,
    makeAhead: String,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.recipeID = recipeID
    self.makeAhead = makeAhead
    self.learnings = learnings
  }
}

public struct AIHandoffRecipeSectionReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let recipeID: Recipe.ID
  public let section: PlaybookSectionKind
  public let text: String
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    recipeID: Recipe.ID,
    section: PlaybookSectionKind,
    text: String,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.recipeID = recipeID
    self.section = section
    self.text = text
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

public enum AIHandoffReview: Equatable, Sendable {
  case menuPrepPlan(AIHandoffMenuPrepPlanReview)
  case recipeMakeAhead(AIHandoffRecipeMakeAheadReview)
  case recipeChefItUp(AIHandoffRecipeSectionReview)
  case recipeServeWith(AIHandoffRecipeSectionReview)
  case mealPlanMakeAhead(AIHandoffMealPlanMakeAheadReview)

  public var handoffID: AIHandoff.ID {
    switch self {
    case let .menuPrepPlan(review): review.handoffID
    case let .recipeMakeAhead(review): review.handoffID
    case let .recipeChefItUp(review): review.handoffID
    case let .recipeServeWith(review): review.handoffID
    case let .mealPlanMakeAhead(review): review.handoffID
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
            learnings: returned.learnings
          )
        )
      case .prepPlan, .adjustRecipe, .mealPlanMakeAheadStrategy:
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
    for text in returned.learnings {
      try LearningRepository.create(
        Learning(
          id: uuid(),
          sourceType: .menu,
          sourceID: menuID,
          text: text,
          provenance: .externalHandoff,
          dateCreated: now,
          dateModified: now
        ),
        in: db
      )
    }
  }
}
