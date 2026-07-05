import Foundation
import SQLiteData

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
}

extension RecipeChatContext {
  public var persistenceSubject: RecipeChatSubject? {
    switch self {
    case let .mealPlan(context): context.persistenceSubject
    case let .menu(context): context.persistenceSubject
    case let .recipe(context): context.persistenceSubject
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

  public static func replaceMessages(
    _ messages: [RecipeChatMessage],
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

    for (index, message) in messages.enumerated() {
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
  }

  public static func pruneMessages(olderThan cutoff: Date, in db: Database) throws {
    let expiredRows = try ChatMessageRecord.fetchAll(db).filter { $0.createdAt < cutoff }
    for row in expiredRows {
      try ChatMessageRecord.find(row.id).delete().execute(db)
    }
  }

  private static func rows(for subject: RecipeChatSubject, in db: Database) throws -> [ChatMessageRecord] {
    try ChatMessageRecord
      .where { $0.subjectKind.eq(subject.kind) }
      .where { $0.subjectID.eq(subject.id) }
      .order { $0.sortOrder }
      .fetchAll(db)
  }
}
