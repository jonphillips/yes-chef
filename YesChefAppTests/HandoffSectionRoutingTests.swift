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
  func recipeAdjustmentRoundTripKeepsTheTokenContractMarkerProseAndLearnings() throws {
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003903")!
    let result = """
    YC-HANDOFF: \(handoffID.uuidString)
    YC-CONTRACT: v2
    Brown the butter before creaming it so the cookies have more nutty depth.
    YC-LEARNINGS:
    - Bacon was rejected because it would overpower the cookie.
    """

    let contractChecked = try #require(AIHandoffReturnContract.strippingMarker(from: result))
    let routed = try #require(AIHandoffToken.stripping(from: contractChecked))
    let returned = AIHandoffReturn.plainText(from: routed.payload)

    #expect(routed.handoffID == handoffID)
    #expect(returned.deliverable == "Brown the butter before creaming it so the cookies have more nutty depth.")
    #expect(returned.learnings == ["Bacon was rejected because it would overpower the cookie."])
  }
}
