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
  case adjustRecipe
  case mealPlanMakeAheadStrategy
}

public enum AIHandoffStatus: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case awaitingReturn
  case imported
  case discarded
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

      You may discuss this freely. When the user asks you to finalize, return only the token line above as the first line followed by paste-ready review text. Preserve that token exactly and do not use a Markdown code fence.
      """
    case .immediate:
      return """
      \(token)

      \(context)

      Return the completed prep plan in your first response. Preserve the token above as the first line. Return only the token and formatted prep plan: no preamble and no Markdown code fence. Use this exact format:
      session:
      - task → serves
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

  public init(handoffID: AIHandoff.ID, menuID: Menu.ID, plan: MenuPrepPlan) {
    self.handoffID = handoffID
    self.menuID = menuID
    self.plan = plan
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
      "The returned plan needs a session heading followed by one or more prep steps."
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
    guard handoff.sourceType == .menu, handoff.taskType == .prepPlan else {
      throw AIHandoffIntentImportError.wrongTask
    }
    guard handoff.status == .awaitingReturn, handoff.importedAt == nil else {
      throw AIHandoffIntentImportError.duplicate
    }
    guard let menu = try Menu.find(handoff.sourceID).fetchOne(db) else {
      throw AIHandoffIntentImportError.handoffNotFound(resolvedHandoffID)
    }

    let currentPlan = MenuPrepPlan(steps: MenuPrepPlanCoding.decode(menu.prepPlan))
    let plan = currentPlan.applyingEditableReviewText(routedText?.payload ?? result)
    guard !plan.steps.isEmpty else { throw AIHandoffIntentImportError.emptyPlan }

    try AIHandoffRepository.markImported(id: handoff.id, at: now, in: db)
    return AIHandoffMenuPrepPlanReview(handoffID: handoff.id, menuID: menu.id, plan: plan)
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
      "The pasted plan needs a session heading followed by one or more prep steps."
    case .wrongMenu:
      "This handoff belongs to a different menu."
    case .wrongTask:
      "This handoff does not contain a prep plan."
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
    now: Date
  ) throws -> AIHandoffMenuPrepPlanImportResult {
    let routedText = AIHandoffToken.stripping(from: text)

    if let routedText, let handoff = try AIHandoffRepository.handoff(id: routedText.handoffID, in: db) {
      guard handoff.sourceType == .menu, handoff.sourceID == menuID else {
        throw AIHandoffMenuPrepPlanImportError.wrongMenu
      }
      guard handoff.taskType == .prepPlan else {
        throw AIHandoffMenuPrepPlanImportError.wrongTask
      }
      guard handoff.status == .awaitingReturn, handoff.importedAt == nil else {
        return .duplicate
      }

      let plan = currentPlan.applyingEditableReviewText(routedText.payload)
      guard !plan.steps.isEmpty else { throw AIHandoffMenuPrepPlanImportError.emptyPlan }
      try MenuRepository.applyPrepPlan(plan, to: menuID, in: db, now: now)
      try AIHandoffRepository.markImported(id: handoff.id, at: now, in: db)
      return .imported
    }

    let plan = currentPlan.applyingEditableReviewText(routedText?.payload ?? text)
    guard !plan.steps.isEmpty else { throw AIHandoffMenuPrepPlanImportError.emptyPlan }
    try MenuRepository.applyPrepPlan(plan, to: menuID, in: db, now: now)
    return .applied
  }
}
