import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeEditorIngredientStructureTests {
    @Test
    func editorSavePreservesIngredientStructureMetadata() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 824_000_000)
      let savedAt = now.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(36_001)
      let sectionID = SampleUUIDSequence.uuid(36_002)
      let lineID = SampleUUIDSequence.uuid(36_003)
      let extraSectionID = SampleUUIDSequence.uuid(36_004)
      let extraLineID = SampleUUIDSequence.uuid(36_005)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Layer Cake", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: nil, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lineID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "For the batter:",
            isHeader: false,
            sortOrder: 0
          )
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: extraSectionID, recipeID: recipeID, name: "Frosting", sortOrder: 1)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: extraLineID,
            recipeID: recipeID,
            sectionID: extraSectionID,
            originalText: "2 cups powdered sugar",
            sortOrder: 0
          )
        }
        .execute(db)

        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        var draft = RecipeEditorDraft(detail: detail)
        draft.ingredientSectionName = "Cake"
        draft.ingredientLineDrafts[0].isHeader = true

        try RecipeRepository.save(
          draft: draft,
          in: db,
          now: savedAt,
          uuid: { SampleUUIDSequence.uuid(36_100) }
        )

        let updated = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let editableSection = try #require(updated.ingredientSections.first { $0.id == sectionID })
        let editableLine = try #require(updated.ingredientLines.first { $0.id == lineID })
        let extraLine = try #require(updated.ingredientLines.first { $0.id == extraLineID })

        expectNoDifference(editableSection.name, "Cake")
        expectNoDifference(editableLine.isHeader, true)
        expectNoDifference(extraLine.originalText, "2 cups powdered sugar")
      }
    }
  }
}
