import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeVariationTests {
    @Test
    func keepAsVariationPersistsPayloadSelectsItAndResolvesWithoutChangingBase() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_250_000)
      let recipeID = SampleUUIDSequence.uuid(32_001)
      let sectionID = SampleUUIDSequence.uuid(32_002)
      let lemonID = SampleUUIDSequence.uuid(32_003)
      var uuids = SampleUUIDSequence(start: 32_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lemonID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
      }

      let variation = try database.write { db in
        try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            summary: "Lime version",
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
              .add(line: "1 teaspoon lime zest", sectionName: "Sauce"),
            ],
            methodNote: "Taste before serving."
          ),
          recipeID: recipeID,
          name: "Lime",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let baseDetail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(baseDetail.ingredientLines.map(\.originalText), ["1 tablespoon lemon juice"])
        expectNoDifference(baseDetail.variations.map(\.name), ["Lime"])
        expectNoDifference(baseDetail.activeVariationID, variation.id)
        expectNoDifference(baseDetail.activeVariation?.note, "Taste before serving.")

        let resolved = try baseDetail.resolved(applying: variation)
        expectNoDifference(resolved.ingredientLines.map(\.originalText), [
          "2 tablespoons lime juice",
          "1 teaspoon lime zest",
        ])
        let highlights = try baseDetail.variationIngredientHighlights(for: variation)
        expectNoDifference(highlights[lemonID], .changed)
        #expect(highlights.values.contains(.added))
      }
    }

    @Test
    func renameVariationUpdatesNameAndModificationDateWithBlankFallback() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_260_000)
      let renamedAt = now.addingTimeInterval(120)
      let recipeID = SampleUUIDSequence.uuid(32_701)
      let sectionID = SampleUUIDSequence.uuid(32_702)
      let lemonID = SampleUUIDSequence.uuid(32_703)
      var uuids = SampleUUIDSequence(start: 32_800)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lemonID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
      }

      let variation = try database.write { db in
        try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            summary: "Lime version",
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice")
            ],
            methodNote: nil
          ),
          recipeID: recipeID,
          name: "Lime",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      // A real rename updates the name and bumps dateModified.
      try database.write { db in
        try RecipeRepository.renameVariation(variation.id, to: "  Zesty Lime  ", in: db, now: renamedAt)
      }
      try database.read { db in
        let stored = try #require(try RecipeVariation.find(variation.id).fetchOne(db))
        expectNoDifference(stored.name, "Zesty Lime")
        expectNoDifference(stored.dateModified, renamedAt)
      }

      // A blank rename keeps the existing name.
      try database.write { db in
        try RecipeRepository.renameVariation(
          variation.id,
          to: "   ",
          in: db,
          now: renamedAt.addingTimeInterval(60)
        )
      }
      try database.read { db in
        let stored = try #require(try RecipeVariation.find(variation.id).fetchOne(db))
        expectNoDifference(stored.name, "Zesty Lime")
      }
    }

    @Test
    func variationNeedsReviewErrorUsesUserFacingDescription() {
      let error = RecipeAdjustmentError.variationNeedsReview(
        "Smoky",
        "The adjustment references an ingredient that could not be matched: 1 teaspoon paprika"
      )

      expectNoDifference(
        error.localizedDescription,
        "\"Smoky\" needs review before this recipe can be overwritten: The adjustment references an ingredient that could not be matched: 1 teaspoon paprika"
      )
      #expect(String(describing: error) != error.localizedDescription)
    }

    @Test
    func addedIngredientHighlightUsesResolvedLineIDWhenRecipeHasNoIngredientSections() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_255_000)
      let recipeID = SampleUUIDSequence.uuid(32_601)
      let variationID = SampleUUIDSequence.uuid(32_602)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Lime Rice", dateCreated: now, dateModified: now)
      )
      let variation = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Zesty",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [
            .add(line: "1 teaspoon lime zest", sectionName: nil)
          ],
          methodStepReplacements: []
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      let resolved = try detail.resolved(applying: variation)
      let addedLine = try #require(resolved.ingredientLines.first)
      let highlights = try detail.variationIngredientHighlights(for: variation)

      expectNoDifference(resolved.ingredientSections.count, 1)
      expectNoDifference(addedLine.originalText, "1 teaspoon lime zest")
      expectNoDifference(highlights[addedLine.id], RecipeVariationIngredientHighlight?.some(.added))
    }

    @Test
    func addedIngredientHighlightUsesResolvedLineIDWhenAddTextContainsNewline() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_256_000)
      let recipeID = SampleUUIDSequence.uuid(32_611)
      let variationID = SampleUUIDSequence.uuid(32_612)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Lime Rice", dateCreated: now, dateModified: now)
      )
      let variation = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Extra Lime",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [
            .add(line: "1 teaspoon lime zest\n1 tablespoon lime juice", sectionName: nil)
          ],
          methodStepReplacements: []
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      let resolved = try detail.resolved(applying: variation)
      let addedLine = try #require(resolved.ingredientLines.first)
      let highlights = try detail.variationIngredientHighlights(for: variation)

      expectNoDifference(resolved.ingredientSections.count, 1)
      expectNoDifference(addedLine.originalText, "1 teaspoon lime zest")
      expectNoDifference(highlights[addedLine.id], RecipeVariationIngredientHighlight?.some(.added))
    }

    @Test
    func overwriteBlocksWhenExistingVariationNoLongerResolvesAgainstProposedBase() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_260_000)
      let recipeID = SampleUUIDSequence.uuid(32_201)
      let sectionID = SampleUUIDSequence.uuid(32_202)
      let paprikaID = SampleUUIDSequence.uuid(32_203)
      var uuids = SampleUUIDSequence(start: 32_300)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Stew", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: paprikaID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 teaspoon paprika",
            sortOrder: 0
          )
        }
        .execute(db)
        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: paprikaID), line: "1 teaspoon smoked paprika")
            ]
          ),
          recipeID: recipeID,
          name: "Smoky",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      try database.write { db in
        #expect(throws: RecipeAdjustmentError.self) {
          try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
            RecipeAdjustmentProposal(
              ingredientOps: [
                .remove(RecipeIngredientReference(id: paprikaID))
              ]
            ),
            recipeID: recipeID,
            in: db,
            now: now.addingTimeInterval(60),
            uuid: { uuids.next() }
          )
        }
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.ingredientLines.map(\.originalText), ["1 teaspoon paprika"])
      }
    }

    @Test
    func groceryGenerationUsesActiveVariationFold() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_270_000)
      let recipeID = SampleUUIDSequence.uuid(32_401)
      let sectionID = SampleUUIDSequence.uuid(32_402)
      let lemonID = SampleUUIDSequence.uuid(32_403)
      var uuids = SampleUUIDSequence(start: 32_500)

      let listID = try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: lemonID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            quantity: 1,
            quantityText: "1",
            unit: "tablespoon",
            item: "lemon juice",
            sortOrder: 0
          )
        }
        .execute(db)
        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
              .add(line: "1 teaspoon lime zest", sectionName: "Sauce"),
            ]
          ),
          recipeID: recipeID,
          name: "Lime",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let listID = try GroceryRepository.ensureDefaultList(in: db, now: now, uuid: { uuids.next() })
        try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        return listID
      }

      try database.read { db in
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { $0.item.groceryListID == listID }
        expectNoDifference(rows.map(\.item.title), ["lime juice", "lime zest"])
        expectNoDifference(
          rows.flatMap(\.sources).compactMap(\.sourceSubtitle).sorted(),
          ["Variation: Lime", "Variation: Lime"]
        )
      }
    }

    @Test
    func derivingEditedResolvedVariationKeepsStableAnchorsAndRoundTripsExactly() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_280_000)
      let recipeID = SampleUUIDSequence.uuid(33_001)
      let sauceID = SampleUUIDSequence.uuid(33_002)
      let garnishID = SampleUUIDSequence.uuid(33_003)
      let lemonID = SampleUUIDSequence.uuid(33_004)
      let stepID = SampleUUIDSequence.uuid(33_005)
      let variationID = SampleUUIDSequence.uuid(33_006)
      let base = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now),
        ingredientSections: [
          IngredientSection(id: sauceID, recipeID: recipeID, name: "Sauce", sortOrder: 0),
          IngredientSection(id: garnishID, recipeID: recipeID, name: "Garnish", sortOrder: 1),
        ],
        ingredientLines: [
          IngredientLine(id: lemonID, recipeID: recipeID, sectionID: sauceID, originalText: "1 tablespoon lemon juice", sortOrder: 0),
        ],
        instructionSections: [InstructionSection(id: sauceID, recipeID: recipeID, name: "Cook", sortOrder: 0)],
        instructionSteps: [InstructionStep(id: stepID, recipeID: recipeID, sectionID: sauceID, text: "Toss the pasta.", sortOrder: 0)]
      )
      let variation = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Lime",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [
            .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
            .add(line: "1 teaspoon lime zest", sectionName: "Garnish"),
          ],
          methodStepReplacements: [
            RecipeMethodStepReplacement(id: stepID, replacementText: "Toss the pasta with the lime juice.")
          ]
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      var edited = try base.resolved(applying: variation)
      edited.ingredientLines[edited.ingredientLines.firstIndex { $0.id == lemonID }!].originalText = "3 tablespoons lime juice"
      let addedLineID = try #require(edited.ingredientLines.first { $0.id != lemonID }?.id)
      edited.ingredientLines[edited.ingredientLines.firstIndex { $0.id == addedLineID }!].originalText = "2 teaspoons lime zest"
      edited.instructionSteps[0].text = "Toss the pasta with lime juice and zest."

      let derivation = base.derivingVariation(from: edited)
      expectNoDifference(derivation.unrepresentableEdits, [])
      expectNoDifference(derivation.payload.ingredientOps.count, 2)
      expectNoDifference(derivation.payload.methodStepReplacements.count, 1)

      let rederived = RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Lime",
        sortIndex: 0,
        deltas: try derivation.payload.encodedData(),
        dateCreated: now,
        dateModified: now
      )
      let roundTrip = try base.resolved(applying: rederived)
      expectNoDifference(roundTrip.ingredientLines.map(\.originalText), edited.ingredientLines.map(\.originalText))
      expectNoDifference(roundTrip.instructionSteps.map(\.text), edited.instructionSteps.map(\.text))
    }

    @Test
    func derivingOneWordIngredientEditProducesOneSubstitute() {
      let now = Date(timeIntervalSinceReferenceDate: 819_290_000)
      let recipeID = SampleUUIDSequence.uuid(33_101)
      let sectionID = SampleUUIDSequence.uuid(33_102)
      let lineID = SampleUUIDSequence.uuid(33_103)
      let base = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Rice", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        ingredientLines: [IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "1 cup rice", sortOrder: 0)]
      )
      var edited = base
      edited.ingredientLines[0].originalText = "1 cup jasmine rice"

      let derivation = base.derivingVariation(from: edited)
      expectNoDifference(
        derivation.payload.ingredientOps,
        [.substitute(RecipeIngredientReference(id: lineID, originalText: "1 cup rice"), line: "1 cup jasmine rice")]
      )
      expectNoDifference(derivation.unrepresentableEdits, [])
    }

    @Test
    func derivingNewIngredientSectionReportsItWithoutProducingAPartialPayload() {
      let now = Date(timeIntervalSinceReferenceDate: 819_300_000)
      let recipeID = SampleUUIDSequence.uuid(33_201)
      let sectionID = SampleUUIDSequence.uuid(33_202)
      let newSectionID = SampleUUIDSequence.uuid(33_203)
      let base = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, name: "Soup", sortOrder: 0)]
      )
      var edited = base
      edited.ingredientSections.append(
        IngredientSection(id: newSectionID, recipeID: recipeID, name: "For serving", sortOrder: 1)
      )

      let derivation = base.derivingVariation(from: edited)
      expectNoDifference(derivation.payload.ingredientOps, [])
      expectNoDifference(derivation.unrepresentableEdits, [.ingredientSectionAdded("For serving")])
    }

    @Test
    func splitOffMaterializesTheEditedResolvedRecipeAndRemovesOnlyTheVariation() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_310_000)
      let recipeID = SampleUUIDSequence.uuid(33_301)
      let sectionID = SampleUUIDSequence.uuid(33_302)
      let lineID = SampleUUIDSequence.uuid(33_303)
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
          variation.id, resolvedDetail: resolved, name: variation.name,
          in: db, now: now.addingTimeInterval(60), uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let original = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let standalone = try #require(try RecipeRepository.fetchDetail(recipeID: standaloneID, in: db))
        expectNoDifference(original.ingredientLines.map(\.originalText), ["1 tablespoon lemon juice"])
        expectNoDifference(original.variations, [])
        expectNoDifference(standalone.recipe.title, "Lime Pasta")
        expectNoDifference(standalone.ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
        #expect(standalone.ingredientLines.allSatisfy { $0.recipeID == standaloneID })
      }
    }

    @Test
    func promoteToBaseReDerivesSiblingVariationsAndKeepsThePreviousBaseAvailable() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_320_000)
      let recipeID = SampleUUIDSequence.uuid(33_501)
      let sectionID = SampleUUIDSequence.uuid(33_502)
      let lineID = SampleUUIDSequence.uuid(33_503)
      var uuids = SampleUUIDSequence(start: 33_600)

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
        let smoky = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "1 tablespoon smoked lemon juice")]
          ),
          recipeID: recipeID, name: "Smoky", in: db, now: now, uuid: { uuids.next() }
        )
        let lime = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "2 tablespoons lime juice")]
          ),
          recipeID: recipeID, name: "Lime", in: db, now: now, uuid: { uuids.next() }
        )
        return (smoky, lime)
      }

      let result = try database.write { db in
        try RecipeRepository.promoteVariationToBase(
          variations.0.id, in: db, now: now.addingTimeInterval(60), uuid: { uuids.next() }
        )
      }
      expectNoDifference(result, .promoted)

      try database.read { db in
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.ingredientLines.map(\.originalText), ["1 tablespoon smoked lemon juice"])
        expectNoDifference(detail.activeVariationID, nil)
        let previousBase = try #require(detail.variations.first { $0.name == "Pasta" })
        let lime = try #require(detail.variations.first { $0.name == "Lime" })
        expectNoDifference(try detail.resolved(applying: previousBase).ingredientLines.map(\.originalText), ["1 tablespoon lemon juice"])
        expectNoDifference(try detail.resolved(applying: lime).ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
      }
    }

  }
}
