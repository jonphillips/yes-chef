import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeVariationAnchorRepairTests {
    @Test
    func keepsModelSuppliedTextAnchorsAsBaseIDs() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_000_000)
      let ids = AnchorRepairFixtureIDs(start: 91_000)
      var uuid = SampleUUIDSequence(start: 91_100)

      try database.write { db in
        try insertAnchorRepairBase(ids: ids, now: now, in: db)
      }
      let variation = try database.write { db in
        try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [
              .substitute(
                RecipeIngredientReference(originalText: "1 tablespoon lemon juice"),
                line: "2 tablespoons lime juice"
              )
            ],
            methodStepReplacements: [
              RecipeMethodStepReplacement(
                originalText: "Finish with lemon.",
                replacementText: "Finish with lime."
              )
            ]
          ),
          recipeID: ids.recipeID,
          name: "Lime",
          deliberationBody: nil,
          in: db,
          now: now,
          uuid: { uuid.next() }
        )
      }

      try database.write { db in
        var ingredient = try #require(try IngredientLine.find(ids.ingredientID).fetchOne(db))
        ingredient.originalText = "1 tablespoon preserved lemon juice"
        try IngredientLine.upsert { ingredient }.execute(db)
        var step = try #require(try InstructionStep.find(ids.stepID).fetchOne(db))
        step.text = "Finish with preserved lemon."
        try InstructionStep.upsert { step }.execute(db)
      }

      try database.read { db in
        let stored = try #require(try RecipeVariation.find(variation.id).fetchOne(db))
        let payload = try RecipeVariationPayload.decode(stored.deltas, variationID: stored.id)
        expectNoDifference(payload.ingredientOps, [
          .substitute(
            RecipeIngredientReference(id: ids.ingredientID, originalText: "1 tablespoon lemon juice"),
            line: "2 tablespoons lime juice"
          )
        ])
        expectNoDifference(payload.methodStepReplacements, [
          RecipeMethodStepReplacement(
            id: ids.stepID,
            originalText: "Finish with lemon.",
            replacementText: "Finish with lime."
          )
        ])

        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: ids.recipeID, in: db))
        let resolved = try detail.resolved(applying: stored).detail
        expectNoDifference(resolved.ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
        expectNoDifference(resolved.instructionSteps.map(\.text), ["Finish with lime."])
      }
    }

    @Test
    func backfillIsIdempotentAndNormalizesLegacyPayloads() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_100_000)
      let ids = AnchorRepairFixtureIDs(start: 91_200)
      let variationID = SampleUUIDSequence.uuid(91_210)
      let legacyPayload = try RecipeVariationPayload(
        ingredientOps: [
          .substitute(
            RecipeIngredientReference(originalText: "1 tablespoon lemon juice"),
            line: "2 tablespoons lime juice"
          )
        ],
        methodStepReplacements: [
          RecipeMethodStepReplacement(
            originalText: "Finish with lemon.",
            replacementText: "Finish with lime."
          )
        ]
      )
      .encodedData()

      try database.write { db in
        try insertAnchorRepairBase(ids: ids, now: now, in: db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: ids.recipeID,
            name: "Lime",
            sortIndex: 0,
            deltas: legacyPayload,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let first = try RecipeRepository.backfillVariationAnchors(in: db)
        expectNoDifference(first.updatedVariationIDs, [variationID])
        expectNoDifference(first.unresolvedAnchors, [])
        let second = try RecipeRepository.backfillVariationAnchors(in: db)
        expectNoDifference(second, RecipeVariationAnchorBackfillReport())
      }

      try database.read { db in
        let variation = try #require(try RecipeVariation.find(variationID).fetchOne(db))
        let payload = try RecipeVariationPayload.decode(variation.deltas, variationID: variationID)
        expectNoDifference(payload.ingredientOps, [
          .substitute(
            RecipeIngredientReference(id: ids.ingredientID, originalText: "1 tablespoon lemon juice"),
            line: "2 tablespoons lime juice"
          )
        ])
        expectNoDifference(payload.methodStepReplacements.first?.id, ids.stepID)
      }
    }

    @Test
    func backfillReportsButDoesNotRewriteUnmatchedAnchors() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_200_000)
      let ids = AnchorRepairFixtureIDs(start: 91_300)
      let variationID = SampleUUIDSequence.uuid(91_310)
      let payload = RecipeVariationPayload(
        ingredientOps: [
          .remove(RecipeIngredientReference(originalText: "1 tablespoon vanished juice"))
        ],
        methodStepReplacements: [
          RecipeMethodStepReplacement(
            originalText: "Vanished instruction.",
            replacementText: "Replacement."
          )
        ]
      )
      let originalData = try payload.encodedData()

      try database.write { db in
        try insertAnchorRepairBase(ids: ids, now: now, in: db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: ids.recipeID,
            name: "Missing anchors",
            sortIndex: 0,
            deltas: originalData,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let report = try RecipeRepository.backfillVariationAnchors(in: db)
        expectNoDifference(report.updatedVariationIDs, [])
        expectNoDifference(report.unresolvedAnchors, [
          .ingredient(
            variationID: variationID,
            variationName: "Missing anchors",
            text: "1 tablespoon vanished juice"
          ),
          .instructionStep(
            variationID: variationID,
            variationName: "Missing anchors",
            text: "Vanished instruction."
          ),
        ])
        expectNoDifference(try RecipeVariation.find(variationID).fetchOne(db)?.deltas, originalData)
      }
    }

    @Test
    func repairReanchorsOnlyTheChosenUnresolvedOperation() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_250_000)
      let ids = AnchorRepairFixtureIDs(start: 91_350)
      let variationID = SampleUUIDSequence.uuid(91_351)
      let payload = try RecipeVariationPayload(
        ingredientOps: [
          .substitute(
            RecipeIngredientReference(
              id: SampleUUIDSequence.uuid(91_600),
              originalText: "1 tablespoon vanished juice"
            ),
            line: "2 tablespoons lime juice"
          )
        ],
        methodStepReplacements: [
          RecipeMethodStepReplacement(
            id: SampleUUIDSequence.uuid(91_601),
            originalText: "Vanished instruction.",
            replacementText: "Replacement."
          )
        ]
      )
      .encodedData()

      try database.write { db in
        try insertAnchorRepairBase(ids: ids, now: now, in: db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: ids.recipeID,
            name: "Needs repair",
            sortIndex: 0,
            deltas: payload,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        _ = try RecipeRepository.repairVariationAnchor(
          .ingredientOperation(0),
          in: variationID,
          reanchoringTo: ids.ingredientID,
          in: db,
          now: now.addingTimeInterval(1)
        )
      }

      try database.read { db in
        let variation = try #require(try RecipeVariation.find(variationID).fetchOne(db))
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: ids.recipeID, in: db))
        expectNoDifference(
          try RecipeRepository.variationAnchorRepairItems(for: variation, in: detail),
          [
            RecipeVariationAnchorRepairItem(
              address: .methodStepReplacement(0),
              kind: .instructionStep,
              originalText: "Vanished instruction."
            )
          ]
        )
        let repairedPayload = try RecipeVariationPayload.decode(variation.deltas, variationID: variationID)
        expectNoDifference(repairedPayload.ingredientOps, [
          .substitute(
            RecipeIngredientReference(
              id: ids.ingredientID,
              originalText: "1 tablespoon vanished juice"
            ),
            line: "2 tablespoons lime juice"
          )
        ])
        let resolution = try detail.resolved(applying: variation)
        expectNoDifference(resolution.detail.ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
        expectNoDifference(resolution.unresolvedAnchors, [.instructionStep("Vanished instruction.")])
      }
    }

    @Test
    func repairCanDiscardAnUnresolvedOperationWithoutDroppingOtherChanges() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_275_000)
      let ids = AnchorRepairFixtureIDs(start: 91_375)
      let variationID = SampleUUIDSequence.uuid(91_376)
      let payload = try RecipeVariationPayload(
        ingredientOps: [
          .remove(RecipeIngredientReference(originalText: "1 tablespoon vanished juice"))
        ],
        methodStepReplacements: [
          RecipeMethodStepReplacement(
            id: ids.stepID,
            originalText: "Finish with lemon.",
            replacementText: "Finish with lime."
          )
        ]
      )
      .encodedData()

      try database.write { db in
        try insertAnchorRepairBase(ids: ids, now: now, in: db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: ids.recipeID,
            name: "Needs repair",
            sortIndex: 0,
            deltas: payload,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        _ = try RecipeRepository.repairVariationAnchor(
          .ingredientOperation(0),
          in: variationID,
          reanchoringTo: nil,
          in: db,
          now: now.addingTimeInterval(1)
        )
      }

      try database.read { db in
        let variation = try #require(try RecipeVariation.find(variationID).fetchOne(db))
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: ids.recipeID, in: db))
        let repairedPayload = try RecipeVariationPayload.decode(variation.deltas, variationID: variationID)
        expectNoDifference(repairedPayload.ingredientOps, [])
        expectNoDifference(try RecipeRepository.variationAnchorRepairItems(for: variation, in: detail), [])
        let resolution = try detail.resolved(applying: variation)
        expectNoDifference(resolution.unresolvedAnchors, [])
        expectNoDifference(resolution.detail.instructionSteps.map(\.text), ["Finish with lime."])
      }
    }

    @Test
    func legacyOriginalTextAnchorStillResolves() throws {
      let now = Date(timeIntervalSinceReferenceDate: 910_300_000)
      let ids = AnchorRepairFixtureIDs(start: 91_400)
      let detail = anchorRepairDetail(ids: ids, now: now)
      let variation = RecipeVariation(
        id: SampleUUIDSequence.uuid(91_410),
        recipeID: ids.recipeID,
        name: "Lime",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [
            .substitute(
              RecipeIngredientReference(originalText: "1 tablespoon lemon juice"),
              line: "2 tablespoons lime juice"
            )
          ],
          methodStepReplacements: []
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      let resolved = try detail.resolved(applying: variation).detail
      expectNoDifference(resolved.ingredientLines.map(\.originalText), ["2 tablespoons lime juice"])
    }

    @Test
    func legacyStepNumberCannotRewriteTheWrongStepAfterReordering() throws {
      let now = Date(timeIntervalSinceReferenceDate: 910_400_000)
      let ids = AnchorRepairFixtureIDs(start: 91_500)
      let firstStepID = SampleUUIDSequence.uuid(91_510)
      let secondStepID = SampleUUIDSequence.uuid(91_511)
      var detail = anchorRepairDetail(ids: ids, now: now)
      detail.instructionSteps = [
        InstructionStep(id: firstStepID, recipeID: ids.recipeID, sectionID: ids.instructionSectionID, text: "First step.", sortOrder: 0),
        InstructionStep(id: secondStepID, recipeID: ids.recipeID, sectionID: ids.instructionSectionID, text: "Second step.", sortOrder: 1),
      ]
      let variation = RecipeVariation(
        id: SampleUUIDSequence.uuid(91_512),
        recipeID: ids.recipeID,
        name: "Changed second step",
        sortIndex: 0,
        deltas: try RecipeVariationPayload(
          ingredientOps: [],
          methodStepReplacements: [
            RecipeMethodStepReplacement(
              stepNumber: 1,
              originalText: "Second step.",
              replacementText: "Changed second step."
            )
          ]
        )
        .encodedData(),
        dateCreated: now,
        dateModified: now
      )

      let resolved = try detail.resolved(applying: variation).detail
      expectNoDifference(resolved.instructionSteps.map(\.text), ["First step.", "Changed second step."])
    }
  }
}

private struct AnchorRepairFixtureIDs {
  let recipeID: Recipe.ID
  let ingredientSectionID: IngredientSection.ID
  let ingredientID: IngredientLine.ID
  let instructionSectionID: InstructionSection.ID
  let stepID: InstructionStep.ID

  init(start: Int) {
    recipeID = SampleUUIDSequence.uuid(start)
    ingredientSectionID = SampleUUIDSequence.uuid(start + 1)
    ingredientID = SampleUUIDSequence.uuid(start + 2)
    instructionSectionID = SampleUUIDSequence.uuid(start + 3)
    stepID = SampleUUIDSequence.uuid(start + 4)
  }
}

private func anchorRepairDetail(ids: AnchorRepairFixtureIDs, now: Date) -> RecipeDetailData {
  RecipeDetailData(
    recipe: Recipe(id: ids.recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now),
    ingredientSections: [
      IngredientSection(id: ids.ingredientSectionID, recipeID: ids.recipeID, sortOrder: 0)
    ],
    ingredientLines: [
      IngredientLine(
        id: ids.ingredientID,
        recipeID: ids.recipeID,
        sectionID: ids.ingredientSectionID,
        originalText: "1 tablespoon lemon juice",
        sortOrder: 0
      )
    ],
    instructionSections: [
      InstructionSection(id: ids.instructionSectionID, recipeID: ids.recipeID, sortOrder: 0)
    ],
    instructionSteps: [
      InstructionStep(
        id: ids.stepID,
        recipeID: ids.recipeID,
        sectionID: ids.instructionSectionID,
        text: "Finish with lemon.",
        sortOrder: 0
      )
    ]
  )
}

private func insertAnchorRepairBase(
  ids: AnchorRepairFixtureIDs,
  now: Date,
  in db: Database
) throws {
  let detail = anchorRepairDetail(ids: ids, now: now)
  try Recipe.insert { detail.recipe }.execute(db)
  for section in detail.ingredientSections {
    try IngredientSection.insert { section }.execute(db)
  }
  for line in detail.ingredientLines {
    try IngredientLine.insert { line }.execute(db)
  }
  for section in detail.instructionSections {
    try InstructionSection.insert { section }.execute(db)
  }
  for step in detail.instructionSteps {
    try InstructionStep.insert { step }.execute(db)
  }
}
