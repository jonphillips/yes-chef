import Foundation
import LLMClientKit
import SQLiteData

@Table("chatThreads")
public struct ChatThreadRecord: Codable, Equatable, Sendable {
  public var subjectKind: ChatSubjectKind
  public var subjectID: String
  public var continuationProvider: String
  public var responseID: String
  public var dateModified: Date

  public init(
    subjectKind: ChatSubjectKind,
    subjectID: String,
    continuationProvider: String,
    responseID: String,
    dateModified: Date
  ) {
    self.subjectKind = subjectKind
    self.subjectID = subjectID
    self.continuationProvider = continuationProvider
    self.responseID = responseID
    self.dateModified = dateModified
  }
}

public struct RecipeChatSubject: Equatable, Hashable, Sendable {
  public var kind: ChatSubjectKind
  public var id: String

  public init(kind: ChatSubjectKind, id: String) {
    self.kind = kind
    self.id = id
  }

  public static func recipe(_ id: Recipe.ID) -> Self {
    Self(kind: .recipe, id: id.uuidString)
  }

  public static func menu(_ id: Menu.ID) -> Self {
    Self(kind: .menu, id: id.uuidString)
  }

  public static func mealPlanDay(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Self {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0
    return Self(kind: .mealPlanDay, id: String(format: "%04d-%02d-%02d", year, month, day))
  }

  public static func workbench(_ id: Workbench.ID) -> Self {
    Self(kind: .workbench, id: id.uuidString)
  }
}

extension RecipeChatContext {
  public var persistenceSubject: RecipeChatSubject? {
    switch self {
    case let .mealPlan(context): context.persistenceSubject
    case let .menu(context): context.persistenceSubject
    case let .recipe(context): context.persistenceSubject
    case let .workbench(context): context.persistenceSubject
    }
  }
}

extension MealPlanChatContext {
  public var persistenceSubject: RecipeChatSubject? {
    subjectDate.map { RecipeChatSubject.mealPlanDay($0) }
  }
}

extension MenuChatContext {
  public var persistenceSubject: RecipeChatSubject? {
    menuID.map(RecipeChatSubject.menu)
  }
}

extension RecipeChatRecipeContext {
  public var persistenceSubject: RecipeChatSubject? {
    recipeID.map(RecipeChatSubject.recipe)
  }
}

extension WorkbenchChatContext {
  public var persistenceSubject: RecipeChatSubject? {
    workbenchID.map(RecipeChatSubject.workbench)
  }
}

public enum RecipeChatStore {
  public static let retention: TimeInterval = 30 * 24 * 60 * 60

  public static func cutoff(now: Date) -> Date {
    now.addingTimeInterval(-retention)
  }

  public static func fetchMessages(
    for subject: RecipeChatSubject,
    in db: Database
  ) throws -> [RecipeChatMessage] {
    try rows(for: subject, in: db).map {
      RecipeChatMessage(id: $0.id, role: $0.role, text: $0.text)
    }
  }

  public static func fetchThread(
    for subject: RecipeChatSubject,
    in db: Database
  ) throws -> RecipeChatThread {
    let record = try threadRecord(for: subject, in: db)
    return RecipeChatThread(
      messages: try fetchMessages(for: subject, in: db),
      continuationToken: record.flatMap { record in
        FrontierProvider(rawValue: record.continuationProvider).map {
          ModelContinuationToken(provider: $0, value: record.responseID)
        }
      }
    )
  }

  public static func replaceMessages(
    _ messages: [RecipeChatMessage],
    for subject: RecipeChatSubject,
    in db: Database,
    now: Date
  ) throws {
    try replaceThread(
      RecipeChatThread(messages: messages),
      for: subject,
      in: db,
      now: now
    )
  }

  public static func replaceThread(
    _ thread: RecipeChatThread,
    for subject: RecipeChatSubject,
    in db: Database,
    now: Date
  ) throws {
    try pruneMessages(olderThan: cutoff(now: now), in: db)

    let existingRows = try rows(for: subject, in: db)
    let existingCreatedAtByID = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.id, $0.createdAt) })
    for row in existingRows {
      try ChatMessageRecord.find(row.id).delete().execute(db)
    }

    for (index, message) in thread.messages.enumerated() {
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      try ChatMessageRecord.insert {
        ChatMessageRecord(
          id: message.id,
          subjectKind: subject.kind,
          subjectID: subject.id,
          role: message.role,
          text: message.text,
          createdAt: existingCreatedAtByID[message.id] ?? now,
          sortOrder: index
        )
      }
      .execute(db)
    }

    try deleteThreadRecord(for: subject, in: db)
    if let continuationToken = thread.continuationToken {
      try ChatThreadRecord.insert {
        ChatThreadRecord(
          subjectKind: subject.kind,
          subjectID: subject.id,
          continuationProvider: continuationToken.provider.rawValue,
          responseID: continuationToken.value,
          dateModified: now
        )
      }
      .execute(db)
    }
  }

  public static func pruneMessages(olderThan cutoff: Date, in db: Database) throws {
    let expiredRows = try ChatMessageRecord.fetchAll(db).filter { $0.createdAt < cutoff }
    for row in expiredRows {
      try ChatMessageRecord.find(row.id).delete().execute(db)
    }
    for thread in try ChatThreadRecord.fetchAll(db).filter({ $0.dateModified < cutoff }) {
      try deleteThreadRecord(
        for: RecipeChatSubject(kind: thread.subjectKind, id: thread.subjectID),
        in: db
      )
    }
  }

  private static func rows(for subject: RecipeChatSubject, in db: Database) throws -> [ChatMessageRecord] {
    try ChatMessageRecord
      .where { $0.subjectKind.eq(subject.kind) }
      .where { $0.subjectID.eq(subject.id) }
      .order { $0.sortOrder }
      .fetchAll(db)
  }

  private static func threadRecord(
    for subject: RecipeChatSubject,
    in db: Database
  ) throws -> ChatThreadRecord? {
    try ChatThreadRecord
      .where { $0.subjectKind.eq(subject.kind) }
      .where { $0.subjectID.eq(subject.id) }
      .fetchOne(db)
  }

  private static func deleteThreadRecord(
    for subject: RecipeChatSubject,
    in db: Database
  ) throws {
    try #sql(
      """
      DELETE FROM "chatThreads"
      WHERE "subjectKind" = \(bind: subject.kind)
        AND "subjectID" = \(bind: subject.id)
      """
    )
    .execute(db)
  }
}

public struct RecipeChatThread: Equatable, Sendable {
  public var messages: [RecipeChatMessage]
  public var continuationToken: ModelContinuationToken?

  public init(
    messages: [RecipeChatMessage] = [],
    continuationToken: ModelContinuationToken? = nil
  ) {
    self.messages = messages
    self.continuationToken = continuationToken
  }
}
