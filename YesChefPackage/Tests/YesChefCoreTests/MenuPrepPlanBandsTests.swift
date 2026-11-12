import Foundation
import Testing
import YesChefCore

@Suite
struct MenuPrepPlanBandsTests {
  @Test
  func headingsOptionallyIncludeTimeAndChangeWhenTimeChanges() {
    let steps = [
      step(1, session: "A", workDayOffset: 1, timeOfDay: 1_020),
      step(2, session: "B", workDayOffset: 1, timeOfDay: 1_050),
      step(3, session: "B", workDayOffset: 1, timeOfDay: 1_050),
      step(4, session: "B", workDayOffset: 1, timeOfDay: 1_065),
      step(5, session: "B", workDayOffset: 1)
    ]

    let withTimes = MenuPrepPlanBanding.bands(steps: steps, dayCount: 2, showsTimes: true).flatMap(\.steps)
    #expect(withTimes.map(\.sessionLabel) == ["A", "B", nil, "B", "B"])
    #expect(withTimes.map(\.headingTime) == [1_020, 1_050, nil, 1_065, nil])

    let withoutTimes = MenuPrepPlanBanding.bands(steps: steps, dayCount: 2).flatMap(\.steps)
    #expect(withoutTimes.map(\.sessionLabel) == ["A", "B", nil, nil, nil])
    #expect(withoutTimes.allSatisfy { $0.headingTime == nil })
  }

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
    let twoDaysBefore = calendar.date(byAdding: .day, value: -2, to: start)!
    #expect(bands[1].title == "\(twoDaysBefore.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · 2 days before Day 1")
    #expect(bands[2].title == "Today")
    #expect(bands[2].isToday)
    #expect(bands[2].steps.map(\.step.sortOrder) == [1, 3, 4])
    #expect(bands[2].steps.map(\.sessionLabel) == ["Evening", "Morning", nil])
  }

  @Test
  func dayBeforeDayOneCanBeTodayWithAPlacement() {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(byAdding: .day, value: -1, to: start)!
    let bands = MenuPrepPlanBanding.bands(
      steps: [step(1, session: "Morning", workDayOffset: -1)],
      dayCount: 2,
      placementStartDate: start,
      today: today,
      calendar: calendar
    )
    #expect(bands.first?.title == "Today")
    #expect(bands.first?.isToday == true)
  }

  @Test
  func noPlacementShowsRelativeDayTitlesAndNeverMarksToday() {
    let bands = MenuPrepPlanBanding.bands(
      steps: [step(1, session: "Earlier", workDayOffset: -2), step(2, session: "Evening", workDayOffset: 1)],
      dayCount: 3,
      today: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
    #expect(bands.map(\.title) == ["2 days before Day 1", "Day 2"])
    #expect(bands.allSatisfy { !$0.isToday })
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

  private func step(_ order: Int, session: String, workDayOffset: Int?, timeOfDay: Int? = nil) -> PrepPlanStepRecord {
    PrepPlanStepRecord(
      id: SampleUUIDSequence.uuid(75_000 + order),
      menuID: SampleUUIDSequence.uuid(75_100),
      sortOrder: order,
      session: session,
      task: "Task \(order)",
      timeOfDay: timeOfDay,
      workDayOffset: workDayOffset
    )
  }
}
