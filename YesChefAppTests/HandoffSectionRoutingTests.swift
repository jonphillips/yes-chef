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
}
