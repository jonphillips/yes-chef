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
  case adjustRecipe
  case mealPlanMakeAheadStrategy
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
    mode: PromptMode = .discuss
  ) -> String {
    let token = header(handoffID: handoffID)
    switch mode {
    case .discuss:
      return """
      \(token)

      \(context)

      You may discuss this freely. When the user asks you to finalize, return only the token line above as the first line, followed by the paste-ready prep plan, then a YC-LEARNINGS: line and a distinct bullet list of durable knowledge established during the discussion. A learning-only return is valid: leave the prep-plan portion empty and include the marker plus bullets. Preserve that token and marker exactly; never merge learnings into a prose summary; do not use a Markdown code fence.

      Prep-plan bullets must be separable, atomic, context-free tasks such as "Salt the chicken Wednesday". Never write choreography or a merged mega-recipe: recipe cooking instructions stay with their recipes.
      """
    case .immediate:
      return """
      \(token)

      \(context)

      Return the completed prep plan in your first response when the menu needs one. Preserve the token above as the first line. Return only the token, formatted prep plan, and a YC-LEARNINGS: section of distinct durable-learning bullets: no preamble and no Markdown code fence. A learning-only return is valid: leave the prep-plan portion empty and include the marker plus bullets. Prep-plan bullets must be separable, atomic, context-free tasks, never choreography or a merged mega-recipe; recipe cooking instructions stay with their recipes. Use this exact format:
      session:
      - task → serves
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

  public init(
    handoffID: AIHandoff.ID,
    menuID: Menu.ID,
    plan: MenuPrepPlan,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.menuID = menuID
    self.plan = plan
    self.learnings = learnings
  }
}

public enum AIHandoffReturn {
  public static let learningsMarker = "YC-LEARNINGS:"

  public static func menuPrepPlan(
    from text: String,
    currentPlan: MenuPrepPlan
  ) -> (plan: MenuPrepPlan, learnings: [String]) {
    let split = splitting(text)
    return (
      currentPlan.applyingEditableReviewText(split.deliverable),
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
      "The returned handoff needs a prep plan or at least one learning bullet."
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
    let routedText = AIHandoffToken.stripping(from: result)
    guard let resolvedHandoffID = handoffID ?? routedText?.handoffID else {
      throw AIHandoffIntentImportError.missingHandoffID
    }
    guard let handoff = try AIHandoffRepository.handoff(id: resolvedHandoffID, in: db) else {
      throw AIHandoffIntentImportError.handoffNotFound(resolvedHandoffID)
    }
    guard handoff.sourceType == .menu,
      handoff.taskType == .prepPlan || handoff.taskType == .learning
    else {
      throw AIHandoffIntentImportError.wrongTask
    }
    guard handoff.status == .awaitingReturn, handoff.importedAt == nil else {
      throw AIHandoffIntentImportError.duplicate
    }
    guard let menu = try Menu.find(handoff.sourceID).fetchOne(db) else {
      throw AIHandoffIntentImportError.handoffNotFound(resolvedHandoffID)
    }

    let currentPlan = MenuPrepPlan(steps: MenuPrepPlanCoding.decode(menu.prepPlan))
    let returned = AIHandoffReturn.menuPrepPlan(
      from: routedText?.payload ?? result,
      currentPlan: currentPlan
    )
    guard !returned.plan.steps.isEmpty || !returned.learnings.isEmpty else {
      throw AIHandoffIntentImportError.emptyPlan
    }

    try AIHandoffRepository.markImported(id: handoff.id, at: now, in: db)
    return AIHandoffMenuPrepPlanReview(
      handoffID: handoff.id,
      menuID: menu.id,
      plan: returned.plan,
      learnings: returned.learnings
    )
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

  public var errorDescription: String? {
    switch self {
    case .emptyPlan:
      "The pasted handoff needs prep steps or at least one learning bullet."
    case .wrongMenu:
      "This handoff belongs to a different menu."
    case .wrongTask:
      "This handoff does not contain a supported result."
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
    _ returned: (plan: MenuPrepPlan, learnings: [String]),
    to menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard !returned.plan.steps.isEmpty || !returned.learnings.isEmpty else {
      throw AIHandoffMenuPrepPlanImportError.emptyPlan
    }
    if !returned.plan.steps.isEmpty {
      try MenuRepository.applyPrepPlan(returned.plan, to: menuID, in: db, now: now)
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
