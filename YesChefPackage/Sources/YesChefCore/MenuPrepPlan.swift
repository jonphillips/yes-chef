import Dependencies
import Foundation
import LLMClientKit
import SQLiteData

/// The rows a person can address and edit in a menu's prep plan. `sourceDish` is a
/// loose ID: this synced child already has its one CloudKit-compatible parent FK,
/// `menuID`.
@Table("prepPlanSteps")
public struct PrepPlanStepRecord: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var menuID: Menu.ID
  public var sortOrder: Int
  public var session: String
  public var task: String
  public var serves: String?
  public var sourceDish: MenuItem.ID?
  public var workDayOffset: Int?

  public init(
    id: UUID,
    menuID: Menu.ID,
    sortOrder: Int,
    session: String,
    task: String,
    serves: String? = nil,
    sourceDish: MenuItem.ID? = nil,
    workDayOffset: Int? = nil
  ) {
    self.id = id
    self.menuID = menuID
    self.sortOrder = sortOrder
    self.session = session
    self.task = task
    self.serves = serves
    self.sourceDish = sourceDish
    self.workDayOffset = workDayOffset
  }

}

/// The picker vocabulary for new human-authored prep-plan rows. Existing and
/// custom labels remain valid through the explicit `.other` escape hatch.
public enum PrepPlanSessionBand: String, CaseIterable, Identifiable, Sendable {
  case flexible
  case earlierInWeek
  case dayBefore
  case dayOf
  case atService
  case other

  public var id: Self { self }

  public var title: String {
    switch self {
    case .flexible: "Flexible / get ahead"
    case .earlierInWeek: "Earlier in the week"
    case .dayBefore: "The day before"
    case .dayOf: "The day of"
    case .atService: "At service"
    case .other: "Other session"
    }
  }

  /// Maps legacy and model-authored session prose onto a display band without
  /// changing the persisted session label.
  public init?(matching session: String) {
    let normalized = session.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.contains("anytime")
      || normalized.contains("flexible")
      || normalized.contains("get ahead") {
      self = .flexible
      return
    }
    guard let band = Self.allCases.first(where: { $0.title.lowercased() == normalized }) else {
      return nil
    }
    self = band
  }
}

public struct PrepPlanStep: Codable, Equatable, Sendable {
  public var session: String
  public var task: String
  public var serves: String?
  public var sourceDish: MenuItem.ID?
  public var workDayOffset: Int?

  public init(
    session: String,
    task: String,
    serves: String? = nil,
    sourceDish: MenuItem.ID? = nil,
    workDayOffset: Int? = nil
  ) {
    self.session = session
    self.task = task
    self.serves = serves
    self.sourceDish = sourceDish
    self.workDayOffset = workDayOffset
  }

  public init(_ record: PrepPlanStepRecord) {
    self.init(
      session: record.session,
      task: record.task,
      serves: record.serves,
      sourceDish: record.sourceDish,
      workDayOffset: record.workDayOffset
    )
  }

  private enum CodingKeys: String, CodingKey {
    case session
    case when
    case task
    case serves
    case sourceDish
    case workDay
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    session = try container.decodeIfPresent(String.self, forKey: .session)
      ?? container.decode(String.self, forKey: .when)
    task = try container.decode(String.self, forKey: .task)
    serves = try container.decodeIfPresent(String.self, forKey: .serves)
    sourceDish = try container.decodeIfPresent(MenuItem.ID.self, forKey: .sourceDish)
    workDayOffset = try container.decodeIfPresent(Int.self, forKey: .workDay).map { $0 - 1 }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(session, forKey: .session)
    try container.encode(task, forKey: .task)
    try container.encodeIfPresent(serves, forKey: .serves)
    try container.encodeIfPresent(sourceDish, forKey: .sourceDish)
    try container.encodeIfPresent(workDayOffset.map { $0 + 1 }, forKey: .workDay)
  }
}

public struct MenuPrepPlan: Equatable, Sendable {
  public struct EditableReviewParseResult: Equatable, Sendable {
    public var plan: MenuPrepPlan
    public var unparsedLines: [String]
    public var outOfRangeDayCount: Int

    public init(plan: MenuPrepPlan, unparsedLines: [String], outOfRangeDayCount: Int = 0) {
      self.plan = plan
      self.unparsedLines = unparsedLines
      self.outOfRangeDayCount = outOfRangeDayCount
    }
  }

  public var steps: [PrepPlanStep]
  public var outOfRangeDayCount: Int

  public init(steps: [PrepPlanStep] = [], outOfRangeDayCount: Int = 0) {
    self.steps = steps
    self.outOfRangeDayCount = outOfRangeDayCount
  }

  public func rendered() -> String {
    editableReviewText()
  }

  public func editableReviewText(dayCount: Int = 1) -> String {
    var lines: [String] = []
    var previousGroup: (day: Int?, session: String)?
    for step in steps {
      let day = dayCount > 1 ? step.workDayOffset.map { $0 + 1 } : nil
      let group = (day: day, session: step.session)
      if previousGroup?.day != group.day || previousGroup?.session != group.session {
        let header = day.map { "Day \($0) · \(step.session)" } ?? step.session
        lines.append("\(header):")
        previousGroup = group
      }
      lines.append("- \(step.renderedEditableReviewLine)")
    }
    return lines.joined(separator: "\n")
  }

  public func applyingEditableReviewText(_ text: String, dayCount: Int = 1) -> MenuPrepPlan {
    parsingEditableReviewText(text, dayCount: dayCount).plan
  }

  public func parsingEditableReviewText(_ text: String, dayCount: Int = 1) -> EditableReviewParseResult {
    var session: String?
    var workDayOffset: Int?
    var revisedSteps: [PrepPlanStep] = []
    var unparsedLines: [String] = []
    var outOfRangeDayCount = 0

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.cleanedEditablePrepPlanLine
      guard !line.isEmpty else { continue }

      if rawLine.isEditablePrepPlanSessionHeader, let parsedHeader = line.editablePrepPlanHeader(dayCount: dayCount) {
        session = parsedHeader.session
        workDayOffset = parsedHeader.workDayOffset
        if dayCount > 1, workDayOffset == nil, line.hasOutOfRangeWorkDayHeader(dayCount: dayCount) {
          outOfRangeDayCount += 1
        }
        continue
      }

      guard let session else {
        unparsedLines.append(rawLine)
        continue
      }
      guard rawLine.isEditablePrepPlanBullet else {
        unparsedLines.append(rawLine)
        continue
      }
      guard let parsedLine = PrepPlanStep.editableReviewLine(line) else {
        unparsedLines.append(rawLine)
        continue
      }
      revisedSteps.append(
        PrepPlanStep(
          session: session,
          task: parsedLine.task,
          serves: parsedLine.serves,
          workDayOffset: workDayOffset
        )
      )
    }

    return EditableReviewParseResult(
      plan: MenuPrepPlan(steps: revisedSteps),
      unparsedLines: unparsedLines,
      outOfRangeDayCount: outOfRangeDayCount
    )
  }

}

private extension String {
  func editablePrepPlanHeader(dayCount: Int) -> (session: String, workDayOffset: Int?)? {
    guard dayCount > 1 else {
      guard let session = editablePrepPlanSession else { return nil }
      return (session, nil)
    }
    let header = trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    guard let range = header.range(of: #"^Day\s+(-?\d+)(?:(?:\s*[·—–\-:]\s*|\s+)(.*))?$"#, options: [.regularExpression, .caseInsensitive]) else {
      guard let session = editablePrepPlanSession else { return nil }
      return (session, nil)
    }
    let match = String(header[range])
    guard let dayRange = match.range(of: #"-?\d+"#, options: .regularExpression),
      let day = Int(match[dayRange]) else { return nil }
    let suffix = String(match[dayRange.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ·—–-:"))
    let session = suffix.isEmpty ? "Any time" : suffix
    guard day >= -6, day <= dayCount else { return (session, nil) }
    return (session, day - 1)
  }

  func hasOutOfRangeWorkDayHeader(dayCount: Int) -> Bool {
    let header = trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    guard let range = header.range(of: #"^Day\s+(-?\d+)(?:(?:\s*[·—–\-:]\s*|\s+).*)?$"#, options: [.regularExpression, .caseInsensitive]),
      let dayRange = header[range].range(of: #"-?\d+"#, options: .regularExpression),
      let day = Int(header[range][dayRange]) else { return false }
    return day < -6 || day > dayCount
  }
}

private extension PrepPlanStep {
  var renderedEditableReviewLine: String {
    guard let serves else { return task }
    return "\(task) → \(serves)"
  }

  static func editableReviewLine(_ line: String) -> (task: String, serves: String?)? {
    let pieces: [Substring]
    if line.contains("→") {
      pieces = line.split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false)
    } else {
      pieces = line.split(separator: "->", maxSplits: 1, omittingEmptySubsequences: false)
    }
    guard let task = String(pieces[0]).cleanedPrepPlanText else { return nil }
    guard pieces.count == 2 else { return (task, nil) }
    guard let serves = String(pieces[1]).cleanedPrepPlanText else { return nil }
    return (task, serves)
  }
}

public enum MenuPrepPlanCoding {
  public static func decode(_ data: Data?) -> [PrepPlanStep] {
    guard let data else { return [] }
    return (try? JSONDecoder().decode([PrepPlanStep].self, from: data)) ?? []
  }
}

public struct MenuPrepPlanClient: Sendable {
  public var extract: @Sendable (
    _ selection: String,
    _ messages: [RecipeChatMessage],
    _ context: String,
    _ dayCount: Int,
    _ tier: ModelTier
  ) async throws -> MenuPrepPlan

  public init(
    extract: @escaping @Sendable (
      _ selection: String,
      _ messages: [RecipeChatMessage],
      _ context: String,
      _ dayCount: Int,
      _ tier: ModelTier
    ) async throws -> MenuPrepPlan
  ) {
    self.extract = extract
  }

  public func callAsFunction(
    selection: String,
    messages: [RecipeChatMessage],
    context: String,
    dayCount: Int,
    tier: ModelTier
  ) async throws -> MenuPrepPlan {
    try await extract(selection, messages, context, dayCount, tier)
  }
}

extension MenuPrepPlanClient: DependencyKey {
  public static let liveValue = MenuPrepPlanClient { selection, messages, context, dayCount, tier in
    @Dependency(\.modelClient) var modelClient
    let call = ModelCall(
      surface: .menu,
      task: .prepPlan,
      tierResolution: .callerProvided,
      contextLayers: [.menu, .selection, .conversation],
      tier: tier,
      system: instructions,
      prompt: prompt(selection: selection, messages: messages, context: context),
      maxTokens: 4096,
      reasoningEffort: .high,
      promptPreferenceKey: AIPromptPreferenceKind.makeAheadPrepPlan.rawValue
    )
    let response = try await call.complete(using: modelClient)
    guard !response.wasBlockedByProvider else { throw StructuredModelResponseError.responseBlocked }
    guard !response.wasTruncated else { throw StructuredModelResponseError.responseTruncated }
    return parse(response.text, dayCount: dayCount)
  }

  public static let testValue = MenuPrepPlanClient { _, _, _, _, _ in
    MenuPrepPlan()
  }

  static let instructions = """
    You weave a staged prep plan for one multi-day menu from the current menu context and conversation.
    Return ONLY strict JSON:
    {"steps":[{"workDay":1,"session":"time within that day","task":"concrete kitchen task","serves":"human-readable meal or day this feeds, or null","sourceDish":"menu item UUID or null"}]}.
    Include workDay as a 1-based day number for scheduled work, or null for Flexible work. Day 0 and negative numbers mean
    days before Day 1; no more than 7 days before Day 1. Keep session as the time within that day. For one-day menus,
    omit workDay and keep using session bands.
    Emit separable, atomic, context-free tasks that stand on their own, such as "Salt the chicken Wednesday" or
    "Pull the beef to temp at 4." Do not generate choreography: never interleave recipe instructions, coordinate
    concurrent cooking, or turn the prep plan into a merged mega-recipe. The recipes hold the cooking.
    The menu context may include a Current prep plan. Treat it as the artifact being edited: preserve useful existing
    steps, apply the user's requested refinements, and return the full proposed replacement plan. Compose from stored
    per-recipe Make-Ahead notes when present, and invent grounded prep tasks and work sessions from the menu's dishes
    and conversation. Prefer the authored Make-Ahead notes when they are available.
    Group related work under free-form session labels such as "Anytime, get ahead" or "Wednesday evening". Set serves
    to the meal or day each step feeds when useful.
    Use sourceDish only when the step clearly comes from one menu item ID in the context; use null when a step spans
    dishes or the source is unclear. Return {"steps":[]} only when there is genuinely no prep plan to save.
    """

  static func prompt(selection: String, messages: [RecipeChatMessage], context: String) -> String {
    let conversation = messages.isEmpty
      ? "(No conversation yet.)"
      : messages.map { "\($0.role.promptLabel): \($0.text)" }.joined(separator: "\n")
    return """
      Menu context:
      \(context)

      User-selected subject:
      \(selection)

      Conversation so far:
      \(conversation)

      Refine the menu prep plan into a full replacement JSON object. Use any Current prep plan in the menu context as
      the starting artifact, and use the conversation only when it clarifies the requested edits or concrete tasks.
      """
  }

  public static func parse(_ text: String, dayCount: Int = 1) -> MenuPrepPlan {
    guard
      let json = jsonObjectSlice(text) ?? jsonArraySlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else { return MenuPrepPlan() }

    let elements: [[String: Any]]
    if let object = raw as? [String: Any] {
      elements = object["steps"] as? [[String: Any]] ?? []
    } else {
      elements = raw as? [[String: Any]] ?? []
    }

    var outOfRangeDayCount = 0
    let steps = elements.compactMap { element -> PrepPlanStep? in
        guard
          let session = (element["session"] as? String)?.cleanedPrepPlanText
            ?? (element["when"] as? String)?.cleanedPrepPlanText,
          let task = (element["task"] as? String)?.cleanedPrepPlanText
        else { return nil }
        let workDay = element["workDay"] as? Int
        let isOutOfRange = dayCount > 1 && workDay.map { $0 < -6 || $0 > dayCount } == true
        if isOutOfRange { outOfRangeDayCount += 1 }
        return PrepPlanStep(
          session: session,
          task: task,
          serves: (element["serves"] as? String)?.cleanedPrepPlanText,
          sourceDish: (element["sourceDish"] as? String)
            .flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) },
          workDayOffset: dayCount > 1 && !isOutOfRange ? workDay.map { $0 - 1 } : nil
        )
      }
    return MenuPrepPlan(steps: steps, outOfRangeDayCount: outOfRangeDayCount)
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }

  private static func jsonArraySlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close
    else { return nil }
    return String(text[open...close])
  }
}

extension DependencyValues {
  public var menuPrepPlanClient: MenuPrepPlanClient {
    get { self[MenuPrepPlanClient.self] }
    set { self[MenuPrepPlanClient.self] = newValue }
  }
}

extension MenuRepository {
  public static func applyPrepPlan(
    _ plan: MenuPrepPlan,
    to menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    try PrepPlanStepRepository.replace(plan.steps, for: menuID, in: db, now: now, uuid: uuid)
  }

  public static func clearPrepPlan(menuID: Menu.ID, in db: Database, now: Date) throws {
    try Menu.find(menuID).update {
      $0.dateModified = now
    }
    .execute(db)
    try PrepPlanStepRecord
      .where { $0.menuID.eq(menuID) }
      .delete()
      .execute(db)
  }
}

public enum PrepPlanStepRepository {
  public static func create(
    _ draft: PrepPlanStep,
    for menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let sortOrder = try nextSortOrder(for: menuID, in: db)
    try PrepPlanStepRecord.insert {
      PrepPlanStepRecord(
        id: uuid(),
        menuID: menuID,
        sortOrder: sortOrder,
        session: draft.session,
        task: draft.task,
        serves: draft.serves,
        sourceDish: draft.sourceDish,
        workDayOffset: draft.workDayOffset
      )
    }
    .execute(db)
    try Menu.find(menuID).update { $0.dateModified = #bind(now) }.execute(db)
  }

  public static func update(
    id: PrepPlanStepRecord.ID,
    session: String,
    task: String,
    serves: String?,
    sourceDish: MenuItem.ID?,
    workDayOffset: Int?,
    in db: Database,
    now: Date
  ) throws {
    guard let existing = try PrepPlanStepRecord.find(id).fetchOne(db) else { return }
    try PrepPlanStepRecord.find(id).update {
      $0.session = #bind(session)
      $0.task = #bind(task)
      $0.serves = #bind(serves?.cleanedPrepPlanText)
      $0.sourceDish = #bind(sourceDish)
      $0.workDayOffset = #bind(workDayOffset)
    }
    .execute(db)
    try Menu.find(existing.menuID).update { $0.dateModified = #bind(now) }.execute(db)
  }

  public static func delete(id: PrepPlanStepRecord.ID, in db: Database, now: Date) throws {
    guard let existing = try PrepPlanStepRecord.find(id).fetchOne(db) else { return }
    try PrepPlanStepRecord.find(id).delete().execute(db)
    try normalizeSortOrder(for: existing.menuID, in: db)
    try Menu.find(existing.menuID).update { $0.dateModified = #bind(now) }.execute(db)
  }

  @discardableResult
  public static func reorder(
    id: PrepPlanStepRecord.ID,
    direction: MenuItemMoveDirection,
    in db: Database,
    now: Date
  ) throws -> Bool {
    guard let step = try PrepPlanStepRecord.find(id).fetchOne(db) else { return false }
    var steps = try steps(for: step.menuID, in: db)
    guard let menu = try Menu.find(step.menuID).fetchOne(db) else { return false }
    let bandSteps = menu.dayCount > 1 ? steps.filter { $0.workDayOffset == step.workDayOffset } : steps
    guard let band = bandSteps.firstIndex(where: { $0.id == id }) else { return false }
    let neighbor = direction == .earlier ? band - 1 : band + 1
    guard bandSteps.indices.contains(neighbor) else { return false }
    if menu.dayCount > 1 {
      var reorderedBand = bandSteps
      reorderedBand.swapAt(band, neighbor)
      var bandIndex = 0
      for index in steps.indices where steps[index].workDayOffset == step.workDayOffset {
        steps[index] = reorderedBand[bandIndex]
        bandIndex += 1
      }
    } else {
      steps.swapAt(band, neighbor)
    }
    try writeSortOrder(steps, in: db)
    try Menu.find(step.menuID).update { $0.dateModified = #bind(now) }.execute(db)
    return true
  }

  public static func replace(
    _ drafts: [PrepPlanStep],
    for menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    var existingByContents = Dictionary(grouping: try steps(for: menuID, in: db)) { step in
      Contents(step)
    }
    var survivors: [PrepPlanStepRecord] = []
    for (sortOrder, draft) in drafts.enumerated() {
      let contents = Contents(draft)
      var candidates = existingByContents[contents] ?? []
      let existing = candidates.isEmpty ? nil : candidates.removeFirst()
      existingByContents[contents] = candidates
      survivors.append(
        PrepPlanStepRecord(
          id: existing?.id ?? uuid(),
          menuID: menuID,
          sortOrder: sortOrder,
          session: draft.session,
          task: draft.task,
          serves: draft.serves,
          sourceDish: draft.sourceDish,
          workDayOffset: draft.workDayOffset
        )
      )
    }
    for step in survivors {
      try PrepPlanStepRecord.upsert { step }.execute(db)
    }
    let survivorIDs = Set(survivors.map(\.id))
    for remaining in existingByContents.values.flatMap({ $0 }) where !survivorIDs.contains(remaining.id) {
      try PrepPlanStepRecord.find(remaining.id).delete().execute(db)
    }
    try Menu.find(menuID).update { $0.dateModified = #bind(now) }.execute(db)
  }

  public static func steps(for menuID: Menu.ID, in db: Database) throws -> [PrepPlanStepRecord] {
    let statement = PrepPlanStepRecord.where { prepPlanSteps in
      prepPlanSteps.menuID.eq(menuID)
    }
    let fetched = try statement.fetchAll(db)
    return fetched.sorted { lhs, rhs in
      lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
    }
  }

  private static func nextSortOrder(for menuID: Menu.ID, in db: Database) throws -> Int {
    (try steps(for: menuID, in: db).map(\.sortOrder).max() ?? -1) + 1
  }

  private static func normalizeSortOrder(for menuID: Menu.ID, in db: Database) throws {
    try writeSortOrder(steps(for: menuID, in: db), in: db)
  }

  private static func writeSortOrder(_ steps: [PrepPlanStepRecord], in db: Database) throws {
    for (sortOrder, step) in steps.enumerated() where step.sortOrder != sortOrder {
      try PrepPlanStepRecord.find(step.id).update { $0.sortOrder = #bind(sortOrder) }.execute(db)
    }
  }

  private struct Contents: Hashable {
    let session: String
    let task: String
    let serves: String?
    let sourceDish: MenuItem.ID?
    let workDayOffset: Int?

    init(_ step: PrepPlanStep) {
      self.init(
        session: step.session,
        task: step.task,
        serves: step.serves,
        sourceDish: step.sourceDish,
        workDayOffset: step.workDayOffset
      )
    }

    init(_ step: PrepPlanStepRecord) {
      self.init(
        session: step.session,
        task: step.task,
        serves: step.serves,
        sourceDish: step.sourceDish,
        workDayOffset: step.workDayOffset
      )
    }

    private init(session: String, task: String, serves: String?, sourceDish: MenuItem.ID?, workDayOffset: Int?) {
      self.session = session
      self.task = task
      self.serves = serves
      self.sourceDish = sourceDish
      self.workDayOffset = workDayOffset
    }
  }
}

public struct PrepPlanDishMatchCandidate: Equatable, Sendable {
  public var id: MenuItem.ID
  public var title: String

  public init(id: MenuItem.ID, title: String) {
    self.id = id
    self.title = title
  }
}

/// Suggests one dish for a human to confirm; it never writes a prep-plan row.
public enum PrepPlanDishMatcher {
  public static func suggestedSourceDish(
    serves: String?,
    among candidates: [PrepPlanDishMatchCandidate]
  ) -> MenuItem.ID? {
    guard let serves = serves?.cleanedPrepPlanText else { return nil }

    let comparableServes = [serves, strippingDayAnchor(from: serves)]
      .filter { !$0.isEmpty }
    for candidateServes in comparableServes {
      let matches = matchingIDs(
        for: collapsedComparison(candidateServes),
        among: candidates,
        transform: collapsedComparison
      )
      if matches.count == 1 { return matches[0] }
      if !matches.isEmpty { return nil }
    }

    for candidateServes in comparableServes {
      let matches = matchingIDs(
        for: parentheticalComparison(candidateServes),
        among: candidates,
        transform: parentheticalComparison
      )
      if matches.count == 1 { return matches[0] }
      if !matches.isEmpty { return nil }
    }

    // A menu-item title may legitimately contain commas. Only treat a comma as compound after
    // trying the entire serves string against every title above.
    guard !serves.contains(",") else { return nil }
    return nil
  }

  private static func matchingIDs(
    for value: String,
    among candidates: [PrepPlanDishMatchCandidate],
    transform: (String) -> String
  ) -> [MenuItem.ID] {
    candidates.compactMap { candidate in
      transform(candidate.title) == value ? candidate.id : nil
    }
  }

  private static func collapsedComparison(_ value: String) -> String {
    value
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased()
  }

  private static func parentheticalComparison(_ value: String) -> String {
    let collapsed = collapsedComparison(value)
    guard let range = collapsed.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) else {
      return collapsed
    }
    return String(collapsed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
  }

  private static func strippingDayAnchor(from serves: String) -> String {
    let pattern = #"^(?i:monday|tuesday|wednesday|thursday|friday|saturday|sunday)[’']s\s+"#
    guard let range = serves.range(of: pattern, options: .regularExpression) else { return serves }
    return String(serves[range.upperBound...])
  }
}

// ADR-0040 D3: row identity asks "is this the same row?" and includes `sourceDish`. This advisory
// comparison asks "did a human-visible step disappear?" and deliberately ignores it, so parsed text
// never re-derives hidden identity from matching prose.
struct PrepPlanStepVisibleContent: Hashable {
  let session: String
  let task: String
  let serves: String?
  let workDayOffset: Int?

  init(_ step: PrepPlanStep) {
    self.init(session: step.session, task: step.task, serves: step.serves, workDayOffset: step.workDayOffset)
  }

  init(_ step: PrepPlanStepRecord) {
    self.init(session: step.session, task: step.task, serves: step.serves, workDayOffset: step.workDayOffset)
  }

  private init(session: String, task: String, serves: String?, workDayOffset: Int?) {
    self.session = session
    self.task = task
    self.serves = serves
    self.workDayOffset = workDayOffset
  }
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
  var isEditablePrepPlanBullet: Bool {
    let line = trimmingCharacters(in: .whitespacesAndNewlines)
    return line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
  }

  var cleanedEditablePrepPlanLine: String {
    var line = trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
      line.removeFirst(2)
    } else if line.hasPrefix("• ") {
      line.removeFirst(2)
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var cleanedPrepPlanText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var editablePrepPlanSession: String? {
    if lowercased().hasPrefix("session:") {
      return String(dropFirst("session:".count)).cleanedPrepPlanText
    }
    guard hasSuffix(":") else { return nil }
    return String(dropLast()).cleanedPrepPlanText
  }

  var isEditablePrepPlanSessionHeader: Bool {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.hasPrefix("- ")
      && !trimmed.hasPrefix("* ")
      && !trimmed.hasPrefix("• ")
      && editablePrepPlanSession != nil
  }
}
