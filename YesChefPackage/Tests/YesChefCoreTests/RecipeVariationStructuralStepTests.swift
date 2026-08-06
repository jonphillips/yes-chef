import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  /// ADR-0021 Amendment 4 D4: the two structural instruction-step ops (`stepInsert` / `stepRemove`)
  /// and the edits that must stay unrepresentable and route to split-off.
  @Suite
  struct RecipeVariationStructuralStepTests {
    /// Base with two ordered steps in one section, shared by the tests below.
    private func soupBase(
      now: Date,
      recipeID: Recipe.ID,
      sectionID: InstructionSection.ID,
      chopID: InstructionStep.ID,
      serveID: InstructionStep.ID
    ) -> RecipeDetailData {
      RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now),
        instructionSections: [InstructionSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        instructionSteps: [
          InstructionStep(id: chopID, recipeID: recipeID, sectionID: sectionID, text: "Chop.", sortOrder: 0),
          InstructionStep(id: serveID, recipeID: recipeID, sectionID: sectionID, text: "Serve.", sortOrder: 1),
        ]
      )
    }

    private func variation(
      _ derivation: RecipeVariationDerivation,
      recipeID: Recipe.ID,
      variationID: RecipeVariation.ID,
      now: Date
    ) throws -> RecipeVariation {
      RecipeVariation(
        id: variationID,
        recipeID: recipeID,
        name: "Variation",
        sortIndex: 0,
        deltas: try derivation.payload.encodedData(),
        dateCreated: now,
        dateModified: now
      )
    }

    @Test
    func stepInsertDerivesResolvesAndRoundTripsForAMiddleInsert() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_350_000)
      let recipeID = SampleUUIDSequence.uuid(35_001)
      let sectionID = SampleUUIDSequence.uuid(35_002)
      let chopID = SampleUUIDSequence.uuid(35_003)
      let serveID = SampleUUIDSequence.uuid(35_004)
      let mixID = SampleUUIDSequence.uuid(35_005)
      let variationID = SampleUUIDSequence.uuid(35_006)
      let base = soupBase(now: now, recipeID: recipeID, sectionID: sectionID, chopID: chopID, serveID: serveID)

      // Insert "Mix." between the two base steps (renumbering Serve, which is not a move).
      var edited = base
      edited.instructionSteps = [
        InstructionStep(id: chopID, recipeID: recipeID, sectionID: sectionID, text: "Chop.", sortOrder: 0),
        InstructionStep(id: mixID, recipeID: recipeID, sectionID: sectionID, text: "Mix.", sortOrder: 1),
        InstructionStep(id: serveID, recipeID: recipeID, sectionID: sectionID, text: "Serve.", sortOrder: 2),
      ]

      let derivation = base.derivingVariation(from: edited)
      #expect(derivation.isRepresentable)
      expectNoDifference(
        derivation.payload.methodStepStructuralOps,
        [.insert(after: RecipeStepReference(id: chopID, originalText: "Chop."), sectionID: sectionID, text: "Mix.")]
      )

      // Payload round-trips exactly through the deltas BLOB.
      let reDecoded = try RecipeVariationPayload.decode(derivation.payload.encodedData(), variationID: variationID)
      expectNoDifference(reDecoded, derivation.payload)

      // Derive → resolve reproduces the edited step order.
      let variation = try variation(derivation, recipeID: recipeID, variationID: variationID, now: now)
      let resolved = try base.resolved(applying: variation).detail
      expectNoDifference(resolved.instructionGroups.flatMap(\.steps).map(\.text), ["Chop.", "Mix.", "Serve."])
    }

    @Test
    func stepRemoveDerivesAndResolvesToTheDroppedStep() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_360_000)
      let recipeID = SampleUUIDSequence.uuid(35_101)
      let sectionID = SampleUUIDSequence.uuid(35_102)
      let chopID = SampleUUIDSequence.uuid(35_103)
      let serveID = SampleUUIDSequence.uuid(35_104)
      let variationID = SampleUUIDSequence.uuid(35_105)
      let base = soupBase(now: now, recipeID: recipeID, sectionID: sectionID, chopID: chopID, serveID: serveID)

      // Remove the first base step.
      var edited = base
      edited.instructionSteps = [
        InstructionStep(id: serveID, recipeID: recipeID, sectionID: sectionID, text: "Serve.", sortOrder: 1)
      ]

      let derivation = base.derivingVariation(from: edited)
      #expect(derivation.isRepresentable)
      expectNoDifference(
        derivation.payload.methodStepStructuralOps,
        [.remove(RecipeStepReference(id: chopID, originalText: "Chop."))]
      )

      let variation = try variation(derivation, recipeID: recipeID, variationID: variationID, now: now)
      let resolved = try base.resolved(applying: variation).detail
      expectNoDifference(resolved.instructionGroups.flatMap(\.steps).map(\.text), ["Serve."])
    }

    @Test
    func stepInsertAnchorFoldsAfterTheBaseStepTextIsEdited() throws {
      // The anchor is pinned to the base step's ID, so a later base-step-text edit still folds
      // (the anchor is normalized, not orphaned) — the gate the anchor-repair effort cleared.
      let now = Date(timeIntervalSinceReferenceDate: 819_370_000)
      let recipeID = SampleUUIDSequence.uuid(35_201)
      let sectionID = SampleUUIDSequence.uuid(35_202)
      let chopID = SampleUUIDSequence.uuid(35_203)
      let serveID = SampleUUIDSequence.uuid(35_204)
      let mixID = SampleUUIDSequence.uuid(35_205)
      let variationID = SampleUUIDSequence.uuid(35_206)
      let base = soupBase(now: now, recipeID: recipeID, sectionID: sectionID, chopID: chopID, serveID: serveID)

      var edited = base
      edited.instructionSteps = [
        InstructionStep(id: chopID, recipeID: recipeID, sectionID: sectionID, text: "Chop.", sortOrder: 0),
        InstructionStep(id: mixID, recipeID: recipeID, sectionID: sectionID, text: "Mix.", sortOrder: 1),
        InstructionStep(id: serveID, recipeID: recipeID, sectionID: sectionID, text: "Serve.", sortOrder: 2),
      ]
      let derivation = base.derivingVariation(from: edited)
      let variation = try variation(derivation, recipeID: recipeID, variationID: variationID, now: now)

      // The cook later edits the base "Chop." step. The stored anchor (id = chopID) still resolves.
      var editedBase = base
      editedBase.instructionSteps[0].text = "Chop finely."
      let resolved = try editedBase.resolved(applying: variation)
      expectNoDifference(resolved.unresolvedAnchors, [])
      expectNoDifference(
        resolved.detail.instructionGroups.flatMap(\.steps).map(\.text),
        ["Chop finely.", "Mix.", "Serve."]
      )
    }

    @Test
    func stepInsertAtTheHeadOfASectionStaysInThatSection() throws {
      // Derive → resolve identity across sections. A step added at the top of the *second* section
      // anchors to the last step of the first one (there is nothing nearer ahead of it), so an
      // insert that inherited its anchor's section would silently move the step into the section
      // above. The op carries its own section for exactly this case.
      let now = Date(timeIntervalSinceReferenceDate: 819_390_000)
      let recipeID = SampleUUIDSequence.uuid(35_401)
      let prepID = SampleUUIDSequence.uuid(35_402)
      let finishID = SampleUUIDSequence.uuid(35_403)
      let chopID = SampleUUIDSequence.uuid(35_404)
      let serveID = SampleUUIDSequence.uuid(35_405)
      let reheatID = SampleUUIDSequence.uuid(35_406)
      let variationID = SampleUUIDSequence.uuid(35_407)

      let base = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now),
        instructionSections: [
          InstructionSection(id: prepID, recipeID: recipeID, name: "Prep", sortOrder: 0),
          InstructionSection(id: finishID, recipeID: recipeID, name: "Finish", sortOrder: 1),
        ],
        instructionSteps: [
          InstructionStep(id: chopID, recipeID: recipeID, sectionID: prepID, text: "Chop.", sortOrder: 0),
          InstructionStep(id: serveID, recipeID: recipeID, sectionID: finishID, text: "Serve.", sortOrder: 1),
        ]
      )

      var edited = base
      edited.instructionSteps = [
        InstructionStep(id: chopID, recipeID: recipeID, sectionID: prepID, text: "Chop.", sortOrder: 0),
        InstructionStep(id: reheatID, recipeID: recipeID, sectionID: finishID, text: "Reheat.", sortOrder: 1),
        InstructionStep(id: serveID, recipeID: recipeID, sectionID: finishID, text: "Serve.", sortOrder: 2),
      ]

      let derivation = base.derivingVariation(from: edited)
      #expect(derivation.isRepresentable)
      expectNoDifference(
        derivation.payload.methodStepStructuralOps,
        [.insert(after: RecipeStepReference(id: chopID, originalText: "Chop."), sectionID: finishID, text: "Reheat.")]
      )

      let variation = try variation(derivation, recipeID: recipeID, variationID: variationID, now: now)
      let resolved = try base.resolved(applying: variation).detail
      expectNoDifference(
        resolved.instructionGroups.map { "\($0.name ?? "-"): \($0.steps.map(\.text).joined(separator: "|"))" },
        ["Prep: Chop.", "Finish: Reheat.|Serve."]
      )
    }

    @Test
    func stepInsertFallsBackToTheAnchorSectionWhenItsOwnSectionIsGone() throws {
      // The section is a placement hint, not a second anchor: if the base later drops the section
      // the insert named, the step still folds (behind its anchor) rather than reporting an
      // unresolved anchor and blocking the recipe.
      let now = Date(timeIntervalSinceReferenceDate: 819_400_000)
      let recipeID = SampleUUIDSequence.uuid(35_501)
      let sectionID = SampleUUIDSequence.uuid(35_502)
      let goneSectionID = SampleUUIDSequence.uuid(35_503)
      let chopID = SampleUUIDSequence.uuid(35_504)
      let serveID = SampleUUIDSequence.uuid(35_505)
      let variationID = SampleUUIDSequence.uuid(35_506)
      let base = soupBase(now: now, recipeID: recipeID, sectionID: sectionID, chopID: chopID, serveID: serveID)

      let payload = RecipeVariationPayload(
        ingredientOps: [],
        methodStepReplacements: [],
        methodStepStructuralOps: [
          .insert(
            after: RecipeStepReference(id: chopID, originalText: "Chop."),
            sectionID: goneSectionID,
            text: "Mix."
          )
        ]
      )
      let variation = RecipeVariation(
        id: variationID, recipeID: recipeID, name: "Variation", sortIndex: 0,
        deltas: try payload.encodedData(), dateCreated: now, dateModified: now
      )

      let resolved = try base.resolved(applying: variation)
      expectNoDifference(resolved.unresolvedAnchors, [])
      expectNoDifference(resolved.detail.instructionGroups.flatMap(\.steps).map(\.text), ["Chop.", "Mix.", "Serve."])
    }

    @Test
    func instructionStepMoveAndSectionAddRemainUnrepresentableAndOfferSplitOff() {
      let now = Date(timeIntervalSinceReferenceDate: 819_380_000)
      let recipeID = SampleUUIDSequence.uuid(35_301)
      let sectionID = SampleUUIDSequence.uuid(35_302)
      let newSectionID = SampleUUIDSequence.uuid(35_303)
      let chopID = SampleUUIDSequence.uuid(35_304)
      let serveID = SampleUUIDSequence.uuid(35_305)
      let base = soupBase(now: now, recipeID: recipeID, sectionID: sectionID, chopID: chopID, serveID: serveID)

      // Reorder the two base steps (a move) — stays unrepresentable.
      var reordered = base
      reordered.instructionSteps = [
        InstructionStep(id: serveID, recipeID: recipeID, sectionID: sectionID, text: "Serve.", sortOrder: 0),
        InstructionStep(id: chopID, recipeID: recipeID, sectionID: sectionID, text: "Chop.", sortOrder: 1),
      ]
      let moveDerivation = base.derivingVariation(from: reordered)
      #expect(!moveDerivation.isRepresentable)
      #expect(moveDerivation.unrepresentableEdits.contains(.instructionStepMoved("Serve.")))
      expectNoDifference(moveDerivation.payload.methodStepStructuralOps, [])

      // Add a brand-new instruction section with a step — stays unrepresentable (section add).
      var newSection = base
      newSection.instructionSections.append(
        InstructionSection(id: newSectionID, recipeID: recipeID, name: "Garnish", sortOrder: 1)
      )
      newSection.instructionSteps.append(
        InstructionStep(id: SampleUUIDSequence.uuid(35_306), recipeID: recipeID, sectionID: newSectionID, text: "Top with herbs.", sortOrder: 0)
      )
      let sectionDerivation = base.derivingVariation(from: newSection)
      #expect(!sectionDerivation.isRepresentable)
      #expect(sectionDerivation.unrepresentableEdits.contains(.instructionSectionAdded("Garnish")))
      // The step in the new section did not leak into a structural op.
      expectNoDifference(sectionDerivation.payload.methodStepStructuralOps, [])
    }
  }
}
