import Foundation
import Testing
import YesChefCore

@Suite
struct TodayPrepLayoutTests {
  @Test
  func datedLayoutKeepsEarlierOpenWorkAndBuildsTodayAheadAndTomorrow() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let today = calendar.date(byAdding: .day, value: 1, to: start)!
    let placement = placement(start, id: 1)
    let steps = [
      step(1, offset: 0),
      step(2, offset: 0, completedAt: today),
      step(3, offset: 1),
      step(4, offset: 2),
      step(5, offset: nil),
    ]

    let layout = TodayPrepLayout.make(steps: steps, dayCount: 3, placements: [placement], today: today, calendar: calendar)
    #expect(layout.mode == .dated(dayTitle: layout.sections[1].title, dayOffset: 1))
    #expect(layout.sections.map(\.kind) == [.stillOpen, .today, .getAhead, .tomorrow])
    #expect(layout.sections[0].steps.map { $0.step.id } == [steps[0].id])
    #expect(layout.sections[1].steps.map { $0.step.id } == [steps[2].id])
    #expect(layout.sections[2].steps.map { $0.step.id } == [steps[4].id])
    #expect(layout.sections[3].steps.map { $0.step.id } == [steps[3].id])
  }

  @Test
  func secondPlacementUsesOnlyChecksAfterPreviousRunEnds() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = calendar.date(from: DateComponents(year: 2025, month: 11, day: 24))!
    let second = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
    let today = calendar.date(byAdding: .day, value: 1, to: second)!
    let before = calendar.date(byAdding: .day, value: 2, to: first)!
    let after = calendar.date(byAdding: .day, value: 4, to: first)!
    let earlyFlexible = calendar.date(byAdding: .day, value: -10, to: second)!
    let steps = [
      step(1, offset: 0, completedAt: before),
      step(2, offset: nil, completedAt: after),
      step(3, offset: nil, completedAt: earlyFlexible),
    ]

    let placements = [placement(first, id: 1), placement(second, id: 2)]
    let layout = TodayPrepLayout.make(
      steps: steps,
      dayCount: 3,
      placements: placements,
      today: today,
      calendar: calendar
    )
    if case let .dated(_, dayOffset) = layout.mode {
      #expect(dayOffset == 1)
    } else {
      Issue.record("The second placement should be the current dated run")
    }
    #expect(layout.doneStepIDs == [steps[1].id, steps[2].id])
  }

  @Test
  func unplacedAndSinglePlacementMenusCountAnyCompletionDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let oldCheck = Date(timeIntervalSinceReferenceDate: 100)
    let row = step(1, offset: nil, completedAt: oldCheck)
    let unplaced = PrepPlanProgress.doneStepIDs(
      steps: [row], dayCount: 3, placements: [], today: today, calendar: calendar
    )
    let placed = PrepPlanProgress.doneStepIDs(
      steps: [row],
      dayCount: 3,
      placements: [placement(calendar.date(byAdding: .day, value: 30, to: today)!, id: 1)],
      today: today,
      calendar: calendar
    )
    #expect(unplaced == [row.id])
    #expect(placed == [row.id])
  }

  @Test
  func stillOpenSessionLabelsRestartForEachEarlierDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let steps = [
      step(1, offset: -2, session: "Evening"),
      step(3, offset: -1, session: "Evening"),
    ]
    let layout = TodayPrepLayout.make(
      steps: steps,
      dayCount: 3,
      placements: [placement(start, id: 1)],
      today: start,
      calendar: calendar
    )
    let stillOpen = layout.sections.filter { $0.kind == .stillOpen }
    #expect(stillOpen.count == 2)
    #expect(stillOpen.allSatisfy { $0.title.hasPrefix("Still open ·") })
    #expect(stillOpen.allSatisfy { $0.steps.first?.sessionLabel == "Evening" })
  }

  @Test
  func lastDayOmitsTomorrowAndDayBeforeDayOneIsDated() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let placement = placement(start, id: 1)
    let lastDay = calendar.date(byAdding: .day, value: 2, to: start)!
    let lastDayLayout = TodayPrepLayout.make(
      steps: [step(1, offset: 2)], dayCount: 3, placements: [placement], today: lastDay, calendar: calendar
    )
    #expect(lastDayLayout.sections.contains { $0.kind == .tomorrow } == false)

    let dayBefore = calendar.date(byAdding: .day, value: -1, to: start)!
    let dayBeforeLayout = TodayPrepLayout.make(
      steps: [step(2, offset: -1)], dayCount: 3, placements: [placement], today: dayBefore, calendar: calendar
    )
    #expect(dayBeforeLayout.mode == .dated(dayTitle: dayBeforeLayout.sections[0].title, dayOffset: -1))
    #expect(dayBeforeLayout.sections.first?.steps.first?.step.workDayOffset == -1)
  }

  @Test
  func overlappingPlacementsUseManualMode() {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let layout = TodayPrepLayout.make(
      steps: [step(1, offset: 0)],
      dayCount: 3,
      placements: [placement(start, id: 1), placement(start, id: 2)],
      today: start
    )
    #expect(layout.mode == .manual)
  }

  @Test
  func manualModeStartsAtFirstBandWithUncheckedWork() {
    let steps = [step(1, offset: nil, completedAt: .now), step(2, offset: 0)]
    let layout = TodayPrepLayout.make(steps: steps, dayCount: 1, placements: [], today: .now)
    #expect(layout.mode == .manual)
    #expect(layout.firstOpenBandID == layout.bands.last?.id)
  }

  private func placement(_ date: Date, id: Int) -> MenuPlacement {
    let uuid = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!
    return MenuPlacement(id: uuid, menuID: uuid, startDate: date, dateCreated: date, dateModified: date)
  }

  private func step(_ order: Int, offset: Int?, session: String? = nil, completedAt: Date? = nil) -> PrepPlanStepRecord {
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + order))!
    return PrepPlanStepRecord(
      id: id,
      menuID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      sortOrder: order,
      session: session ?? (order.isMultiple(of: 2) ? "Morning" : "Evening"),
      task: "Task \(order)",
      workDayOffset: offset,
      completedAt: completedAt
    )
  }
}
