import Foundation
import SQLiteData

public struct ChatAccessStagedPrepPlan: Codable, Equatable, Sendable {
  public struct Dish: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
      public var workDayOffset: Int?
      public var session: String
      public var task: String
      public init(workDayOffset: Int? = nil, session: String, task: String) {
        self.workDayOffset = workDayOffset
        self.session = session
        self.task = task
      }
    }
    public var dayOffset: Int
    public var recipeID: UUID?
    public var title: String
    public var steps: [Step]
    public init(dayOffset: Int, recipeID: UUID? = nil, title: String, steps: [Step]) {
      self.dayOffset = dayOffset; self.recipeID = recipeID; self.title = title; self.steps = steps
    }
  }
  public var format: String
  public var version: Int
  public var menuID: UUID
  public var menuTitle: String
  public var dishes: [Dish]
  public var planAtStage: [ChatAccessExport.PrepStepRecord]?
  public init(menuID: UUID, menuTitle: String, dishes: [Dish], planAtStage: [ChatAccessExport.PrepStepRecord]?) {
    format = "yc-prep-plan"; version = 1; self.menuID = menuID; self.menuTitle = menuTitle
    self.dishes = dishes; self.planAtStage = planAtStage
  }
  private enum CodingKeys: String, CodingKey { case format, version, menuID, menuTitle, dishes, planAtStage }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let format = try c.decode(String.self, forKey: .format), version = try c.decode(Int.self, forKey: .version)
    guard format == "yc-prep-plan" else { throw ChatAccessStagedEnvelopeError.unsupportedFormat(format) }
    guard version == 1 else { throw ChatAccessStagedEnvelopeError.unsupportedVersion(found: version, supported: 1) }
    self.format = format; self.version = version; menuID = try c.decode(UUID.self, forKey: .menuID)
    menuTitle = try c.decode(String.self, forKey: .menuTitle); dishes = try c.decode([Dish].self, forKey: .dishes)
    planAtStage = try c.decodeIfPresent([ChatAccessExport.PrepStepRecord].self, forKey: .planAtStage)
  }
}

public enum ChatPrepPlanImport {
  public enum Error: LocalizedError, Equatable, Sendable {
    case menuUnavailable
    case dishUnavailable(String)
    public var errorDescription: String? {
      switch self {
      case .menuUnavailable: "That menu isn't available on this device."
      case let .dishUnavailable(title): "\(title) is no longer on that menu."
      }
    }
  }
  public enum Entry: Equatable, Sendable {
    case new(dish: MenuItem, step: ChatAccessStagedPrepPlan.Dish.Step)
    case kept(dish: MenuItem, step: PrepPlanStepRecord, matchedByName: Bool)
    case removed(dish: MenuItem, step: PrepPlanStepRecord, matchedByName: Bool)
  }
  public struct Plan: Equatable, Sendable {
    public var menuID: Menu.ID
    public var menuTitle: String
    public var dayCount: Int
    public var startDate: Date?
    public var dishes: [(MenuItem, [Entry])]
    public var planChangedSinceStage: Bool?
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.menuID == rhs.menuID && lhs.menuTitle == rhs.menuTitle && lhs.dayCount == rhs.dayCount && lhs.startDate == rhs.startDate && lhs.planChangedSinceStage == rhs.planChangedSinceStage && lhs.dishes.map(\.1) == rhs.dishes.map(\.1)
    }
    public init(menuID: Menu.ID, menuTitle: String, dayCount: Int, startDate: Date?, dishes: [(MenuItem, [Entry])], planChangedSinceStage: Bool?) {
      self.menuID = menuID; self.menuTitle = menuTitle; self.dayCount = dayCount; self.startDate = startDate; self.dishes = dishes; self.planChangedSinceStage = planChangedSinceStage
    }
    public var newCount: Int { dishes.flatMap(\.1).filter { if case .new = $0 { true } else { false } }.count }
  }

  public static func plan(_ envelope: ChatAccessStagedPrepPlan, in db: Database) throws -> Plan {
    guard let menu = try Menu.find(envelope.menuID).fetchOne(db) else { throw Error.menuUnavailable }
    let rows = try MenuItem.where { $0.menuID.eq(menu.id) }.fetchAll(db)
    let candidates = rows.map { PrepPlanDishMatchCandidate(id: $0.id, title: $0.title) }
    let steps = try PrepPlanStepRepository.steps(for: menu.id, in: db)
    var owned: [UUID: [(PrepPlanStepRecord, Bool)]] = [:]
    for step in steps {
      if let dishID = step.sourceDish, rows.contains(where: { $0.id == dishID }) { owned[dishID, default: []].append((step, false)) }
      else if step.sourceDish == nil, let dishID = PrepPlanDishMatcher.suggestedSourceDish(serves: step.serves, among: candidates) { owned[dishID, default: []].append((step, true)) }
    }
    var planned: [(MenuItem, [Entry])] = []
    var namedDishIDs = Set<MenuItem.ID>()
    for dish in envelope.dishes {
      let matches = rows.filter { row in
        row.dayOffset == dish.dayOffset && (dish.recipeID.map { row.kind == .recipe && row.recipeID == $0 } ?? ((row.kind == .note || row.kind == .reservation) && row.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(dish.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame))
      }
      guard matches.count == 1, let row = matches.first, namedDishIDs.insert(row.id).inserted else { throw Error.dishUnavailable(dish.title) }
      var current = owned[row.id, default: []]
      var entries: [Entry] = []
      for staged in dish.steps {
        if let i = current.firstIndex(where: { same($0.0, staged) }) {
          let (step, matchedByName) = current.remove(at: i)
          entries.append(.kept(dish: row, step: step, matchedByName: matchedByName))
        } else { entries.append(.new(dish: row, step: staged)) }
      }
      entries += current.map { .removed(dish: row, step: $0.0, matchedByName: $0.1) }
      planned.append((row, entries))
    }
    let drift = envelope.planAtStage.map { baseline in
      multiset(baseline) != multiset(trySteps(steps))
    }
    let startDate = try MenuPlacement.where { $0.menuID.eq(menu.id) }.fetchAll(db).map(\.startDate).min()
    return Plan(menuID: menu.id, menuTitle: menu.title, dayCount: menu.dayCount, startDate: startDate, dishes: planned, planChangedSinceStage: drift)
  }

  public static func apply(_ plan: Plan, keeping: Set<Int>, in db: Database, now: Date, uuid: @Sendable () -> UUID) throws {
    guard let menu = try Menu.find(plan.menuID).fetchOne(db) else { throw Error.menuUnavailable }
    for (dish, _) in plan.dishes {
      guard let current = try MenuItem.find(dish.id).fetchOne(db), current.menuID == menu.id, current.dayOffset == dish.dayOffset else {
        throw Error.dishUnavailable(dish.title)
      }
    }
    let allRows = try PrepPlanStepRepository.steps(for: menu.id, in: db)
    var removedIDs = Set<UUID>()
    for entry in plan.dishes.flatMap(\.1) { if case let .removed(_, row, _) = entry { removedIDs.insert(row.id) } }
    for id in removedIDs { try PrepPlanStepRecord.find(id).delete().execute(db) }
    var remaining = allRows.filter { !removedIDs.contains($0.id) }
    var insertions: [(Int, PrepPlanStepRecord)] = []
    var entryIndex = 0
    for (dish, entries) in plan.dishes {
      for entry in entries {
        switch entry {
        case let .kept(dish, row, matchedByName):
          if matchedByName, let updated = try PrepPlanStepRecord.find(row.id).fetchOne(db) {
            var linked = updated; linked.sourceDish = dish.id
            try PrepPlanStepRecord.find(row.id).update { $0.sourceDish = #bind(dish.id) }.execute(db)
            if let index = remaining.firstIndex(where: { $0.id == linked.id }) { remaining[index] = linked }
          }
        case let .new(_, step):
          if keeping.contains(entryIndex) {
            insertions.append((entryIndex, PrepPlanStepRecord(id: uuid(), menuID: menu.id, sortOrder: 0, session: step.session.trimmingCharacters(in: .whitespacesAndNewlines), task: step.task.trimmingCharacters(in: .whitespacesAndNewlines), serves: dish.title, sourceDish: dish.id, workDayOffset: step.workDayOffset)))
          }
        case .removed: break
        }
        entryIndex += 1
      }
    }
    for (_, insertion) in insertions {
      let sameBand = remaining.last { $0.workDayOffset == insertion.workDayOffset && $0.session == insertion.session }
      let sameDay = remaining.last { $0.workDayOffset == insertion.workDayOffset }
      let anchor = sameBand ?? sameDay
      let position = anchor.flatMap { anchor in remaining.firstIndex(where: { $0.id == anchor.id }).map { $0 + 1 } } ?? remaining.endIndex
      remaining.insert(insertion, at: position)
    }
    let insertedIDs = Set(insertions.map { $0.1.id })
    for (order, row) in remaining.enumerated() {
      if insertedIDs.contains(row.id) {
        var inserted = row; inserted.sortOrder = order
        try PrepPlanStepRecord.insert { inserted }.execute(db)
      } else if row.sortOrder != order {
        try PrepPlanStepRecord.find(row.id).update { $0.sortOrder = #bind(order) }.execute(db)
      }
    }
    try Menu.find(menu.id).update { $0.dateModified = #bind(now) }.execute(db)
  }

  private static func same(_ row: PrepPlanStepRecord, _ step: ChatAccessStagedPrepPlan.Dish.Step) -> Bool {
    row.workDayOffset == step.workDayOffset && row.session.trimmingCharacters(in: .whitespacesAndNewlines) == step.session.trimmingCharacters(in: .whitespacesAndNewlines) && row.task.trimmingCharacters(in: .whitespacesAndNewlines) == step.task.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  private static func multiset(_ rows: [ChatAccessExport.PrepStepRecord]) -> [String: Int] {
    Dictionary(rows.map { ("\($0.workDayOffset ?? 0)|\($0.session)|\($0.task)|\($0.serves ?? "")", 1) }, uniquingKeysWith: +)
  }
  private static func trySteps(_ rows: [PrepPlanStepRecord]) -> [ChatAccessExport.PrepStepRecord] {
    rows.map { .init(workDayOffset: $0.workDayOffset, session: $0.session, task: $0.task, serves: $0.serves, dishIndex: nil) }
  }
}
