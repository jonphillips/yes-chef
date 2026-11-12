import Foundation

public struct MenuPrepPlanBandStep: Equatable, Sendable {
  public var step: PrepPlanStepRecord
  public var sessionLabel: String?
  public var headingTime: Int?

  public init(step: PrepPlanStepRecord, sessionLabel: String?, headingTime: Int? = nil) {
    self.step = step
    self.sessionLabel = sessionLabel
    self.headingTime = headingTime
  }
}

public struct MenuPrepPlanBand: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var steps: [MenuPrepPlanBandStep]
  public var isToday: Bool
  public var stepCountTitle: String { steps.count == 1 ? "1 step" : "\(steps.count) steps" }

  public init(id: String, title: String, steps: [MenuPrepPlanBandStep], isToday: Bool = false) {
    self.id = id
    self.title = title
    self.steps = steps
    self.isToday = isToday
  }
}

public enum MenuPrepPlanBanding {
  public static func bands(
    steps: [PrepPlanStepRecord],
    dayCount: Int,
    placementStartDate: Date? = nil,
    today: Date = .now,
    calendar: Calendar = .autoupdatingCurrent,
    showsTimes: Bool = false
  ) -> [MenuPrepPlanBand] {
    guard dayCount > 1 else { return sessionBands(steps, showsTimes: showsTimes) }

    let flexible = steps.filter { $0.workDayOffset == nil }
    var result: [MenuPrepPlanBand] = []
    if !flexible.isEmpty {
      result.append(MenuPrepPlanBand(
        id: "flexible",
        title: "Flexible",
        steps: headingSteps(
          flexible.sorted { $0.sortOrder < $1.sortOrder },
          showsTimes: showsTimes,
          showsSession: true
        )
      ))
    }

    let dated = Dictionary(grouping: steps.compactMap { step -> (Int, PrepPlanStepRecord)? in
      guard let offset = step.workDayOffset else { return nil }
      return (offset, step)
    }, by: \.0)
    for offset in dated.keys.sorted() {
      let daySteps = (dated[offset] ?? []).map(\.1).sorted { $0.sortOrder < $1.sortOrder }
      let bandSteps = headingSteps(daySteps, showsTimes: showsTimes, showsSession: true)
      let workDate = placementStartDate.flatMap { calendar.date(byAdding: .day, value: offset, to: $0) }
      let isToday = placementStartDate != nil && workDate.map { calendar.isDate($0, inSameDayAs: today) } == true
      let title = isToday ? "Today" : dayTitle(offset: offset, start: placementStartDate, calendar: calendar)
      result.append(MenuPrepPlanBand(
        id: "day:\(offset)",
        title: title,
        steps: bandSteps,
        isToday: isToday
      ))
    }
    return result
  }

  private static func sessionBands(_ steps: [PrepPlanStepRecord], showsTimes: Bool) -> [MenuPrepPlanBand] {
    var groups: [(session: String, steps: [PrepPlanStepRecord])] = []
    for step in steps.sorted(by: { $0.sortOrder < $1.sortOrder }) {
      if groups.last?.session == step.session {
        groups[groups.count - 1].steps.append(step)
      } else {
        groups.append((step.session, [step]))
      }
    }
    let flexible = groups.filter { PrepPlanSessionBand(matching: $0.session) == .flexible }
    let other = groups.filter { PrepPlanSessionBand(matching: $0.session) != .flexible }
    return (flexible + other).enumerated().map { index, group in
      MenuPrepPlanBand(
        id: "session:\(index):\(group.session)",
        title: group.session,
        steps: headingSteps(group.steps, showsTimes: showsTimes, showsSession: showsTimes)
      )
    }
  }

  static func headingSteps(
    _ steps: [PrepPlanStepRecord],
    showsTimes: Bool,
    showsSession: Bool
  ) -> [MenuPrepPlanBandStep] {
    var priorHeading: (time: Int?, session: String)?
    return steps.map { step in
      let heading = (time: showsTimes ? step.timeOfDay : nil, session: step.session)
      let hasHeading = priorHeading?.time != heading.time || priorHeading?.session != heading.session
      priorHeading = heading
      return MenuPrepPlanBandStep(
        step: step,
        sessionLabel: hasHeading && showsSession ? step.session : nil,
        headingTime: hasHeading ? heading.time : nil
      )
    }
  }

  static func dayTitle(offset: Int, start: Date?, calendar: Calendar) -> String {
    let dayNumber = offset + 1
    let dayLabel = dayNumber <= 0
      ? "\(-offset) \(-offset == 1 ? "day" : "days") before Day 1"
      : "Day \(dayNumber)"
    guard let start else { return dayLabel }
    let dayDate = calendar.date(byAdding: .day, value: offset, to: start) ?? start
    return "\(dayDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(dayLabel)"
  }
}

public enum PrepPlanProgress {
  public static func doneStepIDs(
    steps: [PrepPlanStepRecord],
    dayCount: Int,
    placements: [MenuPlacement],
    today: Date,
    calendar: Calendar = .autoupdatingCurrent,
    showsTimes: Bool = false
  ) -> Set<PrepPlanStepRecord.ID> {
    guard !placements.isEmpty else {
      return Set(steps.filter { $0.completedAt != nil }.map(\.id))
    }
    func workRange(_ placement: MenuPlacement) -> ClosedRange<Date> {
      let start = calendar.startOfDay(for: placement.startDate)
      return calendar.date(byAdding: .day, value: -7, to: start)!...calendar.date(byAdding: .day, value: dayCount - 1, to: start)!
    }
    let day = calendar.startOfDay(for: today)
    let ordered = placements.sorted { $0.startDate < $1.startDate }
    let current = ordered.first { workRange($0).contains(day) }
      ?? ordered.first { calendar.startOfDay(for: $0.startDate) > day }
      ?? ordered.last!
    guard let previous = ordered.last(where: { $0.startDate < current.startDate }) else {
      return Set(steps.filter { $0.completedAt != nil }.map(\.id))
    }
    let previousEnd = calendar.date(
      byAdding: .day,
      value: dayCount,
      to: calendar.startOfDay(for: previous.startDate)
    )!
    return Set(steps.compactMap { step in
      guard let completedAt = step.completedAt, completedAt >= previousEnd else { return nil }
      return step.id
    })
  }
}

public struct TodayPrepSection: Identifiable, Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case stillOpen, today, getAhead, tomorrow, manual }
  public var id: String
  public var title: String
  public var kind: Kind
  public var steps: [MenuPrepPlanBandStep]

  public init(id: String, title: String, kind: Kind, steps: [MenuPrepPlanBandStep]) {
    self.id = id
    self.title = title
    self.kind = kind
    self.steps = steps
  }
}

public struct TodayPrepLayout: Equatable, Sendable {
  public enum Mode: Equatable, Sendable { case dated(dayTitle: String, dayOffset: Int), manual }
  public var mode: Mode
  public var sections: [TodayPrepSection]
  public var bands: [MenuPrepPlanBand]
  public var firstOpenBandID: String?
  public var doneStepIDs: Set<PrepPlanStepRecord.ID>

  public static func make(
    steps: [PrepPlanStepRecord],
    dayCount: Int,
    placements: [MenuPlacement],
    today: Date,
    calendar: Calendar = .autoupdatingCurrent,
    showsTimes: Bool = false
  ) -> TodayPrepLayout {
    let done = PrepPlanProgress.doneStepIDs(
      steps: steps, dayCount: dayCount, placements: placements, today: today, calendar: calendar
    )
    let covering = placements.filter { placement in
      let start = calendar.startOfDay(for: placement.startDate)
      let lower = calendar.date(byAdding: .day, value: -7, to: start)!
      let upper = calendar.date(byAdding: .day, value: dayCount - 1, to: start)!
      return (lower...upper).contains(calendar.startOfDay(for: today))
    }
    guard dayCount > 1, covering.count == 1 else {
      let bands = MenuPrepPlanBanding.bands(
        steps: steps,
        dayCount: dayCount,
        placementStartDate: placements.count == 1 ? placements[0].startDate : nil,
        today: today,
        calendar: calendar,
        showsTimes: showsTimes
      )
      return TodayPrepLayout(
        mode: .manual,
        sections: bands.map { TodayPrepSection(id: $0.id, title: $0.title, kind: .manual, steps: $0.steps) },
        bands: bands,
        firstOpenBandID: bands.first(where: { $0.steps.contains { !done.contains($0.step.id) } })?.id ?? bands.first?.id,
        doneStepIDs: done
      )
    }
    let placement = covering[0]
    let start = calendar.startOfDay(for: placement.startDate)
    let offset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: today)).day ?? 0
    func labeledSteps(_ steps: [PrepPlanStepRecord]) -> [MenuPrepPlanBandStep] {
      MenuPrepPlanBanding.headingSteps(
        steps.sorted { $0.sortOrder < $1.sortOrder },
        showsTimes: showsTimes,
        showsSession: true
      )
    }
    func daySteps(_ filter: (PrepPlanStepRecord) -> Bool) -> [MenuPrepPlanBandStep] {
      labeledSteps(steps.filter(filter))
    }
    let earlierByDay = Dictionary(grouping: steps.filter {
      ($0.workDayOffset ?? Int.max) < offset && !done.contains($0.id)
    }, by: { $0.workDayOffset ?? 0 })
    let todaySteps = daySteps { $0.workDayOffset == offset }
    let ahead = daySteps { $0.workDayOffset == nil }
    let tomorrow = daySteps { $0.workDayOffset == offset + 1 }
    let dayTitle = "Today · \(MenuPrepPlanBanding.dayTitle(offset: offset, start: placement.startDate, calendar: calendar))"
    var sections: [TodayPrepSection] = []
    if !earlierByDay.isEmpty {
      for day in earlierByDay.keys.sorted() {
        let title = "Still open · \(MenuPrepPlanBanding.dayTitle(offset: day, start: placement.startDate, calendar: calendar))"
        sections.append(
          TodayPrepSection(
            id: "open:\(day)",
            title: title,
            kind: .stillOpen,
            steps: labeledSteps(earlierByDay[day] ?? [])
          )
        )
      }
    }
    sections.append(TodayPrepSection(id: "today", title: dayTitle, kind: .today, steps: todaySteps))
    if !ahead.isEmpty { sections.append(TodayPrepSection(id: "ahead", title: "Get ahead", kind: .getAhead, steps: ahead)) }
    if offset + 1 < dayCount, !tomorrow.isEmpty {
      sections.append(TodayPrepSection(id: "tomorrow", title: "Tomorrow", kind: .tomorrow, steps: tomorrow))
    }
    return TodayPrepLayout(mode: .dated(dayTitle: dayTitle, dayOffset: offset), sections: sections, bands: [], firstOpenBandID: nil, doneStepIDs: done)
  }
}
