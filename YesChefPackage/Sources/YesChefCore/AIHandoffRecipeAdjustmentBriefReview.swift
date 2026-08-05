import Foundation

public struct AIHandoffRecipeAdjustmentBriefReview: Equatable, Sendable {
  public let handoffID: AIHandoff.ID
  public let recipeID: Recipe.ID
  public let variationID: RecipeVariation.ID?
  public let brief: String
  public let learnings: [String]

  public init(
    handoffID: AIHandoff.ID,
    recipeID: Recipe.ID,
    variationID: RecipeVariation.ID? = nil,
    brief: String,
    learnings: [String]
  ) {
    self.handoffID = handoffID
    self.recipeID = recipeID
    self.variationID = variationID
    self.brief = brief
    self.learnings = learnings
  }
}
