import CustomDump
import Dependencies
import SQLiteData
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct IngredientRangeBackfillTests {
    @Test
    func repairsRangeAndHyphenatedSizeParseFieldsAndIsIdempotent() throws {
      @Dependency(\.defaultDatabase) var database
      let recipeID = SampleUUIDSequence.uuid(84_001)
      let sectionID = SampleUUIDSequence.uuid(84_002)
      let oldRange = IngredientLine(
        id: SampleUUIDSequence.uuid(84_003),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: "8-10 ounces kale",
        comment: "keep this comment",
        isOptional: true,
        shoppingCategory: "Produce",
        doNotShop: true,
        sortOrder: 4,
        confidence: .low
      )
      let spacedRange = IngredientLine(
        id: SampleUUIDSequence.uuid(84_004),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: "8 to 10 ounces spinach",
        quantity: 8,
        quantityText: "8",
        unit: "ounces",
        item: "spinach",
        canonicalName: "spinach",
        sortOrder: 5,
        confidence: .medium
      )
      let staleNonRange = IngredientLine(
        id: SampleUUIDSequence.uuid(84_005),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: "2 cups flour",
        quantity: 1,
        quantityText: "2",
        unit: "cups",
        item: "flour",
        canonicalName: "flour",
        sortOrder: 6,
        confidence: .medium
      )
      let staleSize = IngredientLine(
        id: SampleUUIDSequence.uuid(84_006),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: "1 1/2-inch piece fresh ginger, peeled",
        quantity: 1,
        quantityText: "1",
        item: "1/2-inch piece fresh ginger",
        canonicalName: "1/2-inch piece fresh ginger",
        preparation: "peeled",
        isOptional: true,
        shoppingCategory: "Produce",
        doNotShop: true,
        sortOrder: 7,
        confidence: .medium
      )

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Range repair", dateCreated: .distantPast, dateModified: .distantPast)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        for line in [oldRange, spacedRange, staleNonRange, staleSize] {
          try IngredientLine.insert { line }.execute(db)
        }

        let first = try RecipeRepository.reparseIngredientRanges(in: db)
        expectNoDifference(
          first.updatedIngredientLineIDs,
          [oldRange.id, spacedRange.id, staleSize.id].sorted { $0.uuidString < $1.uuidString }
        )

        let repaired = try #require(try IngredientLine.find(oldRange.id).fetchOne(db))
        expectNoDifference(repaired.quantity, 10)
        expectNoDifference(repaired.quantityText, "8-10")
        expectNoDifference(repaired.unit, "ounces")
        expectNoDifference(repaired.item, "kale")
        expectNoDifference(repaired.canonicalName, "kale")
        expectNoDifference(repaired.comment, "keep this comment")
        expectNoDifference(repaired.shoppingCategory, "Produce")
        expectNoDifference(repaired.isOptional, true)
        expectNoDifference(repaired.doNotShop, true)
        expectNoDifference(repaired.sortOrder, 4)
        expectNoDifference(repaired.originalText, "8-10 ounces kale")
        expectNoDifference(try IngredientLine.find(staleNonRange.id).fetchOne(db), staleNonRange)

        let repairedSize = try #require(try IngredientLine.find(staleSize.id).fetchOne(db))
        expectNoDifference(repairedSize.quantity, nil)
        expectNoDifference(repairedSize.quantityText, nil)
        expectNoDifference(repairedSize.unit, nil)
        expectNoDifference(repairedSize.item, "1 1/2-inch piece fresh ginger")
        expectNoDifference(repairedSize.canonicalName, CanonicalIngredient.canonicalName("1 1/2-inch piece fresh ginger"))
        expectNoDifference(repairedSize.preparation, "peeled")
        expectNoDifference(repairedSize.confidence, .low)
        expectNoDifference(repairedSize.shoppingCategory, "Produce")
        expectNoDifference(repairedSize.isOptional, true)
        expectNoDifference(repairedSize.doNotShop, true)
        expectNoDifference(repairedSize.sortOrder, 7)
        expectNoDifference(repairedSize.originalText, staleSize.originalText)
        expectNoDifference(try RecipeRepository.reparseIngredientRanges(in: db), IngredientRangeBackfillReport())
      }
    }
  }
}
