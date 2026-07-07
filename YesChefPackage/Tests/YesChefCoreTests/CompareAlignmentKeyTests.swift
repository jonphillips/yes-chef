import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CompareAlignmentKeyTests {
    @Test
    func contentSignatureTracksTextWhileIdentityStaysStable() {
      let working = detail(recipeID: uuid("11111111-1111-1111-1111-111111111111"), lineText: "1 cup onions")
      let candidate = detail(recipeID: uuid("22222222-2222-2222-2222-222222222222"), lineText: "2 cups onions")

      let baseline = CompareAlignmentKey(working: working, candidates: [candidate])
      let edited = CompareAlignmentKey(
        working: detail(recipeID: working.recipe.id, lineText: "9 cups onions"),
        candidates: [candidate]
      )

      // Same recipe set → same cache slot; edited text → a changed content fingerprint.
      #expect(baseline.identity == edited.identity)
      #expect(baseline.contentSignature != edited.contentSignature)
    }

    @Test
    func identityChangesWhenCandidateSetChanges() {
      let working = detail(recipeID: uuid("11111111-1111-1111-1111-111111111111"), lineText: "1 cup onions")
      let candidate = detail(recipeID: uuid("22222222-2222-2222-2222-222222222222"), lineText: "2 cups onions")
      let added = detail(recipeID: uuid("33333333-3333-3333-3333-333333333333"), lineText: "3 cups onions")

      let baseline = CompareAlignmentKey(working: working, candidates: [candidate])
      let withAdded = CompareAlignmentKey(working: working, candidates: [candidate, added])

      #expect(baseline.identity != withAdded.identity)
    }
  }
}

private func detail(recipeID: UUID, lineText: String) -> RecipeDetailData {
  let prefix = String(recipeID.uuidString.prefix(8))
  let sectionID = uuid("\(prefix)-0000-0000-0000-000000000000")
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
        id: uuid("\(prefix)-1111-1111-1111-111111111111"),
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
