import Foundation

public struct AIHandoffMenuPrepPlanReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let menuID: Menu.ID
  public let plan: MenuPrepPlan
  public let learnings: [String]
  public let unparsedPlanLines: [String]
  public let advisoryNotes: [String]
  public let prepPlanIntent: AIHandoffPrepPlanIntent
  public let replacementStepCount: Int

  public init(
    handoffID: AIHandoff.ID,
    menuID: Menu.ID,
    plan: MenuPrepPlan,
    learnings: [String],
    unparsedPlanLines: [String] = [],
    advisoryNotes: [String] = [],
    prepPlanIntent: AIHandoffPrepPlanIntent = .refine,
    replacementStepCount: Int = 0
  ) {
    self.handoffID = handoffID
    self.menuID = menuID
    self.plan = plan
    self.learnings = learnings
    self.unparsedPlanLines = unparsedPlanLines
    self.advisoryNotes = advisoryNotes
    self.prepPlanIntent = prepPlanIntent
    self.replacementStepCount = replacementStepCount
  }
}
