import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct RecipeVariationAnchorRepairEditorTests {
  @Test
  func editorRepairsAnAnchorAndRefreshesItsResolvedDetail() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 910_500_000)
    let recipeID = SampleUUIDSequence.uuid(91_700)
    let sectionID = SampleUUIDSequence.uuid(91_701)
    let ingredientID = SampleUUIDSequence.uuid(91_702)
    let variationID = SampleUUIDSequence.uuid(91_703)
    let missingIngredientID = SampleUUIDSequence.uuid(91_704)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let deltas = try RecipeVariationPayload(
        ingredientOps: [
          .substitute(
            RecipeIngredientReference(id: missingIngredientID, originalText: "1 tablespoon old lemon juice"),
            line: "2 tablespoons lime juice"
          )
        ],
        methodStepReplacements: []
      )
      .encodedData()
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: ingredientID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: recipeID,
            name: "Lime",
            sortIndex: 0,
            deltas: deltas,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      let model = RecipeVariationEditorModel(recipeID: recipeID, variationID: variationID)
      try await model.$baseDetail.load()
      model.baseDetailChanged(model.baseDetail)
      let repairItem = try #require(model.repairItems.first)
      expectNoDifference(model.unresolvedAnchors, [.ingredient("1 tablespoon old lemon juice")])

      await model.repairAnchor(repairItem, reanchoringTo: ingredientID)

      expectNoDifference(model.repairItems, [])
      expectNoDifference(model.unresolvedAnchors, [])
      expectNoDifference(model.resolvedDetail?.ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
    }
  }
}
