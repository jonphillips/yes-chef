import Foundation
import Testing
import YesChefCore

@Suite
struct MenuPrepPlanBandsTests {
  @Test
  func multidayBandsPutFlexibleFirstAndKeepSessionsInsideWorkDays() {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(byAdding: .day, value: 1, to: start)!
    let steps = [
      step(1, session: "Evening", workDayOffset: 1),
      step(2, session: "Flexible", workDayOffset: nil),
      step(3, session: "Morning", workDayOffset: 1),
      step(4, session: "Morning", workDayOffset: 1),
      step(5, session: "Prep", workDayOffset: -2),
    ]

    let bands = MenuPrepPlanBanding.bands(
      steps: steps,
      dayCount: 3,
      placementStartDate: start,
      today: today,
      calendar: calendar
    )
    #expect(bands.map(\.id) == ["flexible", "day:-2", "day:1"])
    #expect(bands.first?.title == "Flexible")
    #expect(bands[1].title == "2 days before Day 1")
    #expect(bands[2].title == "Today")
    #expect(bands[2].isToday)
    #expect(bands[2].steps.map(\.step.sortOrder) == [1, 3, 4])
    #expect(bands[2].steps.map(\.sessionLabel) == ["Evening", "Morning", nil])
  }

  @Test
  func oneDayBandingKeepsFlexibleSessionGroupsFirst() {
    let bands = MenuPrepPlanBanding.bands(
      steps: [step(1, session: "The day of", workDayOffset: nil), step(2, session: "Flexible", workDayOffset: nil)],
      dayCount: 1
    )
    #expect(bands.map(\.title) == ["Flexible", "The day of"])
    #expect(bands.allSatisfy { !$0.isToday })
  }

  private func step(_ order: Int, session: String, workDayOffset: Int?) -> PrepPlanStepRecord {
    PrepPlanStepRecord(
      id: SampleUUIDSequence.uuid(75_000 + order),
      menuID: SampleUUIDSequence.uuid(75_100),
      sortOrder: order,
      session: session,
      task: "Task \(order)",
      workDayOffset: workDayOffset
    )
  }
}
