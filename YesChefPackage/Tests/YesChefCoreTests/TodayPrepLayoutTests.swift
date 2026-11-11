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
    let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let second = calendar.date(byAdding: .year, value: 1, to: first)!
    let today = calendar.date(byAdding: .day, value: 1, to: second)!
    let before = calendar.date(byAdding: .day, value: 2, to: first)!
    let after = calendar.date(byAdding: .day, value: 4, to: first)!
    let steps = [step(1, offset: 0, completedAt: before), step(2, offset: nil, completedAt: after)]

    let ids = PrepPlanProgress.doneStepIDs(
      steps: steps,
      dayCount: 3,
      placements: [placement(first, id: 1), placement(second, id: 2)],
      today: today,
      calendar: calendar
    )
    #expect(ids == [steps[1].id])
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

  private func step(_ order: Int, offset: Int?, completedAt: Date? = nil) -> PrepPlanStepRecord {
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + order))!
    return PrepPlanStepRecord(
      id: id,
      menuID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      sortOrder: order,
      session: order.isMultiple(of: 2) ? "Morning" : "Evening",
      task: "Task \(order)",
      workDayOffset: offset,
      completedAt: completedAt
    )
  }
}
