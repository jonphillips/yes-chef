import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeVariationReviewRegressionTests {
    @Test
    func derivingAnEditBackToTheBaseTextRemovesTheSubstitute() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_295_000)
      let recipeID = SampleUUIDSequence.uuid(33_151)
      let sectionID = SampleUUIDSequence.uuid(33_152)
      let lineID = SampleUUIDSequence.uuid(33_153)
      let variationID = SampleUUIDSequence.uuid(33_154)
      let base = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Rice", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        ingredientLines: [IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "1 cup rice", sortOrder: 0)]
      )
      let variation = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Jasmine",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "1 cup jasmine rice")],
          methodStepReplacements: []
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )
      var edited = try base.resolved(applying: variation)
      edited.ingredientLines[0].originalText = "1 cup rice"

      let derivation = base.derivingVariation(from: edited)

      expectNoDifference(derivation.payload.ingredientOps, [])
      expectNoDifference(derivation.unrepresentableEdits, [])
    }

    @Test
    func derivingAnInsertedInstructionStepReportsItWithoutProducingAPartialPayload() {
      let now = Date(timeIntervalSinceReferenceDate: 819_305_000)
      let recipeID = SampleUUIDSequence.uuid(33_251)
      let sectionID = SampleUUIDSequence.uuid(33_252)
      let originalStepID = SampleUUIDSequence.uuid(33_253)
      let insertedStepID = SampleUUIDSequence.uuid(33_254)
      let base = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now),
        instructionSections: [InstructionSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        instructionSteps: [InstructionStep(id: originalStepID, recipeID: recipeID, sectionID: sectionID, text: "Simmer.", sortOrder: 0)]
      )
      var edited = base
      edited.instructionSteps.append(
        InstructionStep(id: insertedStepID, recipeID: recipeID, sectionID: sectionID, text: "Taste and serve.", sortOrder: 1)
      )

      let derivation = base.derivingVariation(from: edited)

      expectNoDifference(derivation.payload.methodStepReplacements, [])
      expectNoDifference(derivation.unrepresentableEdits, [.instructionStepAdded("Taste and serve.")])
    }

    @Test
    func splitOffWithWhitespaceTitleFallsBackToTheVariationName() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_315_000)
      let recipeID = SampleUUIDSequence.uuid(33_351)
      let sectionID = SampleUUIDSequence.uuid(33_352)
      let lineID = SampleUUIDSequence.uuid(33_353)
      var uuids = SampleUUIDSequence(start: 33_400)

      let variation = try database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now) }.execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "1 tablespoon lemon juice", sortOrder: 0)
        }
        .execute(db)
        return try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "2 tablespoons lime juice")]
          ),
          recipeID: recipeID, name: "Lime Pasta", in: db, now: now, uuid: { uuids.next() }
        )
      }

      let standaloneID = try database.write { db in
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let resolved = try detail.resolved(applying: variation)
        return try RecipeRepository.splitVariationOff(
          variation.id, resolvedDetail: resolved, name: "   ",
          in: db, now: now.addingTimeInterval(60), uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let standalone = try #require(try RecipeRepository.fetchDetail(recipeID: standaloneID, in: db))
        expectNoDifference(standalone.recipe.title, "Lime Pasta")
      }
    }

    @Test
    func promoteToBaseRequiresConfirmationBeforeRemovingAnUnanchorableSibling() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_330_000)
      let recipeID = SampleUUIDSequence.uuid(33_701)
      let sectionID = SampleUUIDSequence.uuid(33_702)
      let lineID = SampleUUIDSequence.uuid(33_703)
      var uuids = SampleUUIDSequence(start: 33_800)

      let variations = try database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now) }.execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "1 tablespoon lemon juice", sortOrder: 0)
        }
        .execute(db)
        let removeLemon = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(ingredientOps: [.remove(RecipeIngredientReference(id: lineID))]),
          recipeID: recipeID, name: "No Lemon", in: db, now: now, uuid: { uuids.next() }
        )
        let smoky = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "1 tablespoon smoked lemon juice")]
          ),
          recipeID: recipeID, name: "Smoky", in: db, now: now, uuid: { uuids.next() }
        )
        return (removeLemon, smoky)
      }

      let needsConfirmation = try database.write { db in
        try RecipeRepository.promoteVariationToBase(
          variations.0.id, in: db, now: now.addingTimeInterval(60), uuid: { uuids.next() }
        )
      }
      expectNoDifference(needsConfirmation, .needsConfirmation(removingVariations: ["Smoky"]))

      try database.read { db in
        let beforeConfirmation = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(beforeConfirmation.ingredientLines.map(\.originalText), ["1 tablespoon lemon juice"])
        expectNoDifference(beforeConfirmation.variations.map(\.name).sorted(), ["No Lemon", "Smoky"])
      }

      let confirmed = try database.write { db in
        try RecipeRepository.promoteVariationToBase(
          variations.0.id,
          confirmingRemovalOfUnrepresentableVariations: true,
          in: db,
          now: now.addingTimeInterval(120),
          uuid: { uuids.next() }
        )
      }
      expectNoDifference(confirmed, .promoted)

      try database.read { db in
        let promoted = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(promoted.ingredientLines, [])
        expectNoDifference(promoted.variations.map(\.name), ["Pasta"])
        let restoredBase = try #require(promoted.variations.first)
        expectNoDifference(
          try promoted.resolved(applying: restoredBase).ingredientLines.map(\.originalText),
          ["1 tablespoon lemon juice"]
        )
      }
    }
  }
}
