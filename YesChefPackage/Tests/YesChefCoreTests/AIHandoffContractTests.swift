import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

extension AIHandoffTests {
  @Test
  func onboardRecipeReturnUsesTheSharedHandoffReviewParserWithoutAnExportedHandoff() throws {
    @Dependency(\.defaultDatabase) var database
    let recipeID = SampleUUIDSequence.uuid(38_020)
    let reviewID = SampleUUIDSequence.uuid(38_021)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Brown Butter Cookies", dateCreated: now, dateModified: now)
      }
      .execute(db)
    }

    let review = try database.read { db in
      try AIHandoffIntentImport.stageOnboardReview(
        handoff: AIHandoff(
          id: reviewID,
          sourceType: .recipe,
          sourceID: recipeID,
          taskType: .recipeMakeAhead,
          createdAt: now,
          exportedPrompt: ""
        ),
        result: """
        Mix and chill the dough the day before baking.
        YC-LEARNINGS:
        - Browned butter benefits from a short cool-down before it meets the sugar.
        """,
        in: db
      ).review
    }

    guard case let .recipeMakeAhead(onboardReview) = review else {
      Issue.record("Expected an onboard recipe make-ahead review.")
      return
    }
    expectNoDifference(onboardReview.handoffID, reviewID)
    expectNoDifference(onboardReview.recipeID, recipeID)
    expectNoDifference(onboardReview.makeAhead, "Mix and chill the dough the day before baking.")
    expectNoDifference(
      onboardReview.learnings,
      ["Browned butter benefits from a short cool-down before it meets the sugar."]
    )
  }

  @Test
  func recipeAdjustmentFinalizeClassifiesByShapeNotKeyword() throws {
    let revision = """
    \(AIHandoffReturnContract.marker)
    Take the butter to 120g and brown it — more nutty depth.
    Move the salt into the flour so it distributes evenly.
    """
    #expect(try RecipeAdjustmentFinalize.classify(payload: revision) == .revisionBrief)

    let prosaicRecipeMention = "Rework the recipe so the sauce reduces further before plating."
    #expect(try RecipeAdjustmentFinalize.classify(payload: prosaicRecipeMention) == .revisionBrief)

    let newRecipe = """
    {"@context":"https://schema.org","@type":"Recipe","name":"Charred Cabbage",\
    "recipeIngredient":["1 head cabbage","2 tbsp olive oil"],\
    "recipeInstructions":[{"@type":"HowToStep","text":"Char the cabbage over high heat."}]}
    """
    #expect(try RecipeAdjustmentFinalize.classify(payload: newRecipe) == .newRecipe)
  }
}
