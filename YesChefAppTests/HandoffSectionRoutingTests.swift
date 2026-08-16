import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
struct HandoffSectionRoutingTests {
  @Test
  func chefItUpReturnDoesNotMatchMakeAheadForTheSameRecipe() {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003901")!
    let chefItUpHandoff = AIHandoff(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000003902")!,
      sourceType: .recipe,
      sourceID: recipeID,
      taskType: .chefItUp,
      createdAt: .distantPast,
      exportedPrompt: ""
    )

    #expect(!HandoffExportSource.recipeSection(recipeID, .makeAhead).matches(chefItUpHandoff))
    #expect(HandoffExportSource.recipeSection(recipeID, .chefItUp).matches(chefItUpHandoff))
  }

  @Test
  func menuDayReturnOnlyMatchesItsOriginalDay() {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000003904")!
    let dayTwoHandoff = AIHandoff(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000003905")!,
      sourceType: .menu,
      sourceID: menuID,
      taskType: .prepPlan,
      dayOffset: 1,
      createdAt: .distantPast,
      exportedPrompt: ""
    )

    #expect(HandoffExportSource.menuDay(menuID, dayOffset: 1).matches(dayTwoHandoff))
    #expect(!HandoffExportSource.menuDay(menuID, dayOffset: 0).matches(dayTwoHandoff))
  }

  @Test
  func variationAdjustmentReturnOnlyMatchesItsOriginalVariation() {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003906")!
    let variationID = UUID(uuidString: "00000000-0000-0000-0000-000000003907")!
    let otherVariationID = UUID(uuidString: "00000000-0000-0000-0000-000000003908")!
    let variationHandoff = AIHandoff(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000003909")!,
      sourceType: .recipe,
      sourceID: recipeID,
      taskType: .adjustRecipe,
      variationID: variationID,
      createdAt: .distantPast,
      exportedPrompt: ""
    )

    #expect(HandoffExportSource.recipeAdjustment(recipeID, variationID: variationID).matches(variationHandoff))
    #expect(!HandoffExportSource.recipeAdjustment(recipeID).matches(variationHandoff))
    #expect(!HandoffExportSource.recipeAdjustment(recipeID, variationID: otherVariationID).matches(variationHandoff))
  }

  @Test
  @MainActor
  func unmatchedVariationPasteRestagesTheOriginalVariationScope() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003910")!
    let variationID = UUID(uuidString: "00000000-0000-0000-0000-000000003911")!
    let unrecognizedHandoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003912")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)
    let coordinator = HandoffReviewCoordinator()

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Variation Handoff", dateCreated: now, dateModified: now)
        }
        .execute(db)
      }

      let transport = HandoffInAppTransport()
      await transport.pastedResultsReceived(
        ["""
        YC-HANDOFF: \(unrecognizedHandoffID.uuidString)
        \(AIHandoffReturnContract.marker)
        Use a lighter sauce for this variation.
        """],
        source: .recipeAdjustment(recipeID, variationID: variationID)
      )

      #expect(transport.isShowingUnmatchedConfirmation)
      await transport.reviewUnmatchedResult()

      guard case let .recipeAdjustmentBrief(review) = coordinator.review else {
        Issue.record("Expected a recipe-adjustment brief review.")
        return
      }
      #expect(review.variationID == variationID)
    }
  }

  @Test
  @MainActor
  func workbenchDraftReviewStagesTheRecipeEvenWhenTheRationaleIsMissing() {
    // ADR-0042 S3b: a draft that omitted the rationale block (it argued it in-thread) must still
    // stage the recipe item — the review sheet fills the empty rationale — alongside its learnings.
    let coordinator = HandoffReviewCoordinator()
    let review = AIHandoffWorkbenchDraftReview(
      handoffID: UUID(uuidString: "00000000-0000-0000-0000-000000003940")!,
      workbenchID: UUID(uuidString: "00000000-0000-0000-0000-000000003941")!,
      draftRecipe: WorkbenchDraftRecipe(
        title: "No-Rationale Dish",
        ingredientLines: ["1 egg"],
        instructionLines: ["Cook it."],
        rationale: ""
      ),
      learnings: ["Eggs are a constraint."]
    )

    let items = coordinator.workbenchDraftReviewItems(for: review)

    #expect(items.count == 2)
    #expect(items.first?.commitTitle == "Create Working Recipe")
    #expect(items.last?.commitTitle == "Save to Workbench Log")
  }

  @Test
  func recipeAdjustmentRoundTripKeepsTheTokenContractMarkerProseAndLearnings() throws {
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003903")!
    let result = """
    YC-HANDOFF: \(handoffID.uuidString)
    YC-CONTRACT: v3
    Brown the butter before creaming it so the cookies have more nutty depth.
    YC-LEARNINGS:
    - Bacon was rejected because it would overpower the cookie.
    """

    let contractChecked = try AIHandoffReturnContract.strippingMarker(from: result)
    let routed = try #require(AIHandoffToken.stripping(from: contractChecked.text))
    let returned = AIHandoffReturn.plainText(from: routed.payload)

    #expect(routed.handoffID == handoffID)
    #expect(returned.deliverable == "Brown the butter before creaming it so the cookies have more nutty depth.")
    #expect(returned.learnings == ["Bacon was rejected because it would overpower the cookie."])
  }
}
