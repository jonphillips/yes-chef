import Foundation

public struct AIHandoffMenuPrepPlanReturn: Equatable, Sendable {
  public var plan: MenuPrepPlan
  public var learnings: [String]
  public var unparsedLines: [String]
  public var outOfRangeDayCount: Int
}

extension AIHandoffReturn {
  public static func menuPrepPlan(
    from text: String,
    currentPlan: MenuPrepPlan,
    dayCount: Int = 1
  ) -> AIHandoffMenuPrepPlanReturn {
    let split = splitting(text)
    let parsed = currentPlan.parsingEditableReviewText(split.deliverable, dayCount: dayCount)
    let parsedLearnings = learnings(from: split.learnings)
    return AIHandoffMenuPrepPlanReturn(
      plan: parsed.plan,
      learnings: parsedLearnings.learnings,
      unparsedLines: parsed.unparsedLines,
      outOfRangeDayCount: parsed.outOfRangeDayCount
    )
  }
}
