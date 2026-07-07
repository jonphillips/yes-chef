import Dependencies
import DependenciesTestSupport
import LLMClientKit
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
struct WorkbenchCompareAlignmentModelTests {
  @Test
  func compareAlignmentKeyUsesRecipeIdentityAndOrderOnly() {
    let working = detail(recipeID: uuid("11111111-1111-1111-1111-111111111111"), lineText: "1 cup onions")
    let candidateA = detail(recipeID: uuid("22222222-2222-2222-2222-222222222222"), lineText: "2 cups onions")
    let candidateB = detail(recipeID: uuid("33333333-3333-3333-3333-333333333333"), lineText: "3 cups onions")
    let candidateC = detail(recipeID: uuid("44444444-4444-4444-4444-444444444444"), lineText: "4 cups onions")

    let baseline = CompareAlignmentKey(working: working, candidates: [candidateA, candidateB])
    let editedText = CompareAlignmentKey(
      working: detail(recipeID: working.recipe.id, lineText: "9 cups onions"),
      candidates: [
        detail(recipeID: candidateA.recipe.id, lineText: "7 cups onions"),
        detail(recipeID: candidateB.recipe.id, lineText: "8 cups onions"),
      ]
    )
    let addedCandidate = CompareAlignmentKey(working: working, candidates: [candidateA, candidateB, candidateC])
    let removedCandidate = CompareAlignmentKey(working: working, candidates: [candidateA])

    #expect(baseline.orderedRecipeIDs == [working.recipe.id, candidateA.recipe.id, candidateB.recipe.id])
    #expect(baseline == editedText)
    #expect(baseline != addedCandidate)
    #expect(baseline != removedCandidate)
  }

  @Test
  func alignmentModelFallsBackToDeterministicWhenAlignerThrows() async {
    let working = detail(recipeID: uuid("55555555-5555-5555-5555-555555555555"), lineText: "1 cup tomatoes")
    let candidate = detail(recipeID: uuid("66666666-6666-6666-6666-666666666666"), lineText: "2 cups tomatoes")
    let key = CompareAlignmentKey(working: working, candidates: [candidate])
    let model = await MainActor.run { WorkbenchCompareAlignmentModel() }

    await withDependencies {
      $0.workbenchCompareAligner = WorkbenchCompareAlignerClient { _, _, _ in
        throw TestError.failure
      }
    } operation: {
      await model.ingredientsSegmentAppeared(working: working, candidates: [candidate], tier: .onDevice)
    }

    let state = await MainActor.run {
      (
        model.cachedComparison(for: key),
        model.currentComparison,
        model.isAligning,
        model.showsBasicViewAffordance
      )
    }

    #expect(state.0 == nil)
    #expect(state.1 == nil)
    #expect(state.2 == false)
    #expect(state.3 == true)
  }
}

private enum TestError: Error {
  case failure
}

private func detail(recipeID: UUID, lineText: String) -> RecipeDetailData {
  let sectionID = uuid("\(recipeID.uuidString.prefix(8))0000-0000-0000-000000000000")
  return RecipeDetailData(
    recipe: Recipe(
      id: recipeID,
      title: recipeID.uuidString,
      dateCreated: Date(timeIntervalSinceReferenceDate: 0),
      dateModified: Date(timeIntervalSinceReferenceDate: 0)
    ),
    ingredientSections: [
      IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
    ],
    ingredientLines: [
      IngredientLine(
        id: uuid("\(recipeID.uuidString.prefix(8))1111-1111-1111-111111111111"),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: lineText,
        sortOrder: 0
      )
    ]
  )
}

private func uuid(_ string: String) -> UUID {
  guard let uuid = UUID(uuidString: string) else {
    fatalError("Invalid UUID string: \(string)")
  }
  return uuid
}
