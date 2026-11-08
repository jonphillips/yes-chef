import Foundation

public struct MenuPrepPlanBandStep: Equatable, Sendable {
  public var step: PrepPlanStepRecord
  public var sessionLabel: String?

  public init(step: PrepPlanStepRecord, sessionLabel: String?) {
    self.step = step
    self.sessionLabel = sessionLabel
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
    calendar: Calendar = .autoupdatingCurrent
  ) -> [MenuPrepPlanBand] {
    guard dayCount > 1 else { return sessionBands(steps) }

    let flexible = steps.filter { $0.workDayOffset == nil }
    var result: [MenuPrepPlanBand] = []
    if !flexible.isEmpty {
      var priorSession: String?
      result.append(MenuPrepPlanBand(
        id: "flexible",
        title: "Flexible",
        steps: flexible.sorted { $0.sortOrder < $1.sortOrder }.map { step in
          let label = priorSession == step.session ? nil : step.session
          priorSession = step.session
          return MenuPrepPlanBandStep(step: step, sessionLabel: label)
        }
      ))
    }

    let dated = Dictionary(grouping: steps.compactMap { step -> (Int, PrepPlanStepRecord)? in
      guard let offset = step.workDayOffset else { return nil }
      return (offset, step)
    }, by: \.0)
    for offset in dated.keys.sorted() {
      let daySteps = (dated[offset] ?? []).map(\.1).sorted { $0.sortOrder < $1.sortOrder }
      var priorSession: String?
      let bandSteps = daySteps.map { step -> MenuPrepPlanBandStep in
        let label = priorSession == step.session ? nil : step.session
        priorSession = step.session
        return MenuPrepPlanBandStep(step: step, sessionLabel: label)
      }
      let workDate = placementStartDate.flatMap { calendar.date(byAdding: .day, value: offset, to: $0) }
      let dayNumber = offset + 1
      let title: String
      if dayNumber <= 0 {
        title = "\(-offset) \(-offset == 1 ? "day" : "days") before Day 1"
      } else if placementStartDate != nil, let workDate {
        title = calendar.isDate(workDate, inSameDayAs: today)
          ? "Today"
          : "\(workDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · Day \(dayNumber)"
      } else {
        title = "Day \(dayNumber)"
      }
      result.append(MenuPrepPlanBand(
        id: "day:\(offset)",
        title: title,
        steps: bandSteps,
        isToday: placementStartDate != nil && workDate.map { calendar.isDate($0, inSameDayAs: today) } == true
      ))
    }
    return result
  }

  private static func sessionBands(_ steps: [PrepPlanStepRecord]) -> [MenuPrepPlanBand] {
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
        steps: group.steps.map { MenuPrepPlanBandStep(step: $0, sessionLabel: nil) }
      )
    }
  }
}
