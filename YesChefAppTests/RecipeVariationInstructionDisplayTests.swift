import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

/// ADR-0021 Amd4-D4 at the *assembly*, not the parts: Core resolution folds an inserted step in and
/// drops a removed one, and the reader has to turn that back into an overlay the cook can read —
/// the inserted step marked as an addition, the removed step still legible underneath (D3), and the
/// numbering following only the steps that are actually performed.
@Suite
@MainActor
struct RecipeVariationInstructionDisplayTests {
  @Test
  func activeVariationMarksInsertedStepsAndKeepsRemovedOnesLegibleWithoutNumberingThem() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 841_100_000)
    let recipeID = SampleUUIDSequence.uuid(62_001)
    let prepID = SampleUUIDSequence.uuid(62_002)
    let finishID = SampleUUIDSequence.uuid(62_003)
    let chopID = SampleUUIDSequence.uuid(62_004)
    let rinseID = SampleUUIDSequence.uuid(62_005)
    let serveID = SampleUUIDSequence.uuid(62_006)
    let variationID = SampleUUIDSequence.uuid(62_007)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database

      // Two sections; the variation drops "Rinse." from the first and adds "Reheat." at the head of
      // the second — the placement that anchors to the previous section's last step.
      let payload = RecipeVariationPayload(
        ingredientOps: [],
        methodStepReplacements: [],
        methodStepStructuralOps: [
          .remove(RecipeStepReference(id: rinseID, originalText: "Rinse.")),
          .insert(
            after: RecipeStepReference(id: chopID, originalText: "Chop."),
            sectionID: finishID,
            text: "Reheat."
          ),
        ]
      )

      let deltas = try payload.encodedData()
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
        try InstructionSection.insert {
          InstructionSection(id: prepID, recipeID: recipeID, name: "Prep", sortOrder: 0)
          InstructionSection(id: finishID, recipeID: recipeID, name: "Finish", sortOrder: 1)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(id: chopID, recipeID: recipeID, sectionID: prepID, text: "Chop.", sortOrder: 0)
          InstructionStep(id: rinseID, recipeID: recipeID, sectionID: prepID, text: "Rinse.", sortOrder: 1)
          InstructionStep(id: serveID, recipeID: recipeID, sectionID: finishID, text: "Serve.", sortOrder: 2)
        }
        .execute(db)
        try RecipeVariation.insert {
          RecipeVariation(
            id: variationID,
            recipeID: recipeID,
            name: "Make-ahead",
            sortIndex: 0,
            deltas: deltas,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try RecipeRepository.setActiveVariation(
          variationID, recipeID: recipeID, in: db, now: now, uuid: { UUID() }
        )
      }

      let model = RecipeDetailModel(recipeID: recipeID)
      try await model.$detail.load()

      let groups = model.instructionStepDisplayGroups
      expectNoDifference(groups.map(\.name), ["Prep", "Finish"])

      // "Rinse." is gone from the resolved procedure but stays visible, unnumbered, in its base
      // position — the cook can see what this variation drops.
      expectNoDifference(
        groups[0].steps.map { "\($0.number.map(String.init) ?? "—") \($0.step.text)" },
        ["1 Chop.", "— Rinse."]
      )
      expectNoDifference(groups[0].steps.map(\.highlight), [nil, .removed])

      // The inserted step landed in the section it was added to, not the anchor's section, and is
      // marked as an addition.
      expectNoDifference(
        groups[1].steps.map { "\($0.number.map(String.init) ?? "—") \($0.step.text)" },
        ["1 Reheat.", "2 Serve."]
      )
      expectNoDifference(groups[1].steps.map(\.highlight), [.inserted, nil])
    }
  }

  @Test
  func baseRecipeWithNoActiveVariationNumbersEveryStepAndHighlightsNothing() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 841_200_000)
    let recipeID = SampleUUIDSequence.uuid(62_101)
    let sectionID = SampleUUIDSequence.uuid(62_102)
    let chopID = SampleUUIDSequence.uuid(62_103)
    let serveID = SampleUUIDSequence.uuid(62_104)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
        try InstructionSection.insert {
          InstructionSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(id: chopID, recipeID: recipeID, sectionID: sectionID, text: "Chop.", sortOrder: 0)
          InstructionStep(id: serveID, recipeID: recipeID, sectionID: sectionID, text: "Serve.", sortOrder: 1)
        }
        .execute(db)
      }

      let model = RecipeDetailModel(recipeID: recipeID)
      try await model.$detail.load()

      let steps = model.instructionStepDisplayGroups.flatMap(\.steps)
      expectNoDifference(steps.map(\.number), [1, 2])
      expectNoDifference(steps.map(\.highlight), [nil, nil])
    }
  }
}
