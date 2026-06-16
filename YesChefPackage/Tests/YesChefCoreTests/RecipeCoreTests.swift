import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct RecipeCoreTests {
  @Test
  func ingredientParserParsesSimpleQuantities() {
    let recipeID = SampleUUIDSequence.uuid(1)
    let sectionID = SampleUUIDSequence.uuid(2)
    var uuids = SampleUUIDSequence(start: 10)

    let lines = IngredientParser.lines(
      from: "2 tablespoons soy sauce\nKosher salt, to taste",
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { uuids.next() }
    )

    expectNoDifference(lines.map(\.quantity), [2, nil])
    expectNoDifference(lines.map(\.unit), ["tablespoons", nil])
    expectNoDifference(lines.map(\.item), ["soy sauce", "Kosher salt, to taste"])
  }

  @Test
  func scalingUsesParsedQuantitiesAndPreservesUnparsedText() {
    let recipeID = SampleUUIDSequence.uuid(1)
    let sectionID = SampleUUIDSequence.uuid(2)
    let parsed = IngredientLine(
      id: SampleUUIDSequence.uuid(3),
      recipeID: recipeID,
      sectionID: sectionID,
      originalText: "2 tablespoons soy sauce",
      quantity: 2,
      quantityText: "2",
      unit: "tablespoons",
      item: "soy sauce",
      sortOrder: 0,
      confidence: .medium
    )
    let unparsed = IngredientLine(
      id: SampleUUIDSequence.uuid(4),
      recipeID: recipeID,
      sectionID: sectionID,
      originalText: "Kosher salt, to taste",
      sortOrder: 1,
      confidence: .low
    )

    expectNoDifference(IngredientScaler.scaledText(for: parsed, factor: 2), "4 tablespoons soy sauce")
    expectNoDifference(IngredientScaler.scaledText(for: unparsed, factor: 2), "Kosher salt, to taste")
  }

  @Test
  func originalSnapshotRoundTripsReadableRecipeData() throws {
    let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
    let recipeID = SampleUUIDSequence.uuid(1)
    let sectionID = SampleUUIDSequence.uuid(2)
    let recipe = Recipe(
      id: recipeID,
      title: "Test Recipe",
      summary: "A useful fixture",
      servingsText: "Serves 4",
      dateCreated: now,
      dateModified: now
    )
    let data = try RecipeBundleCoding.snapshotData(
      recipe: recipe,
      source: RecipeSource(id: SampleUUIDSequence.uuid(3), recipeID: recipeID, name: "Personal"),
      ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
      ingredientLines: [
        IngredientLine(
          id: SampleUUIDSequence.uuid(4),
          recipeID: recipeID,
          sectionID: sectionID,
          originalText: "1 onion",
          quantity: 1,
          quantityText: "1",
          unit: nil,
          item: "onion",
          sortOrder: 0
        )
      ],
      instructionSections: [],
      instructionSteps: [],
      notes: [],
      tagNames: ["weeknight"],
      categoryNames: ["Mains"]
    )

    let snapshot = try RecipeBundleCoding.decodeSnapshot(data)

    expectNoDifference(snapshot.recipe.title, "Test Recipe")
    expectNoDifference(snapshot.ingredients, ["1 onion"])
    expectNoDifference(snapshot.ingredientLines.first?.quantity, 1)
    expectNoDifference(snapshot.tags, ["weeknight"])
  }

  @Test
  func savePreservesUnchangedChildIDsAndNonGeneralNotes() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
    let recipeID = SampleUUIDSequence.uuid(1)
    let sourceID = SampleUUIDSequence.uuid(2)
    let ingredientSectionID = SampleUUIDSequence.uuid(3)
    let extraIngredientSectionID = SampleUUIDSequence.uuid(4)
    let ingredientLineID = SampleUUIDSequence.uuid(5)
    let extraIngredientLineID = SampleUUIDSequence.uuid(6)
    let instructionSectionID = SampleUUIDSequence.uuid(7)
    let instructionStepID = SampleUUIDSequence.uuid(8)
    let generalNoteID = SampleUUIDSequence.uuid(9)
    let warningNoteID = SampleUUIDSequence.uuid(10)

    try database.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Stable Soup",
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
      try RecipeSource.insert {
        RecipeSource(id: sourceID, recipeID: recipeID, name: "Notebook")
      }
      .execute(db)
      try IngredientSection.insert {
        IngredientSection(id: ingredientSectionID, recipeID: recipeID, sortOrder: 0)
      }
      .execute(db)
      try IngredientSection.insert {
        IngredientSection(id: extraIngredientSectionID, recipeID: recipeID, name: "Garnish", sortOrder: 1)
      }
      .execute(db)
      try IngredientLine.insert {
        IngredientLine(
          id: ingredientLineID,
          recipeID: recipeID,
          sectionID: ingredientSectionID,
          originalText: "1 onion",
          quantity: 1,
          quantityText: "1",
          item: "onion",
          sortOrder: 0,
          confidence: .medium
        )
      }
      .execute(db)
      try IngredientLine.insert {
        IngredientLine(
          id: extraIngredientLineID,
          recipeID: recipeID,
          sectionID: extraIngredientSectionID,
          originalText: "Chives",
          sortOrder: 0,
          confidence: .low
        )
      }
      .execute(db)
      try InstructionSection.insert {
        InstructionSection(id: instructionSectionID, recipeID: recipeID, sortOrder: 0)
      }
      .execute(db)
      try InstructionStep.insert {
        InstructionStep(
          id: instructionStepID,
          recipeID: recipeID,
          sectionID: instructionSectionID,
          text: "Cook until soft.",
          sortOrder: 0
        )
      }
      .execute(db)
      try RecipeNote.insert {
        RecipeNote(
          id: generalNoteID,
          recipeID: recipeID,
          text: "Use a heavy pot.",
          noteType: .general,
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
      try RecipeNote.insert {
        RecipeNote(
          id: warningNoteID,
          recipeID: recipeID,
          text: "Do not boil after adding cream.",
          noteType: .warning,
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)

      let maybeDetail = try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)
      let detail = try #require(maybeDetail)
      var draft = RecipeEditorDraft(detail: detail)
      draft.summary = "Updated without rewriting children"

      var uuids = SampleUUIDSequence(start: 50)
      try RecipeRepository.save(
        draft: draft,
        in: db,
        now: now.addingTimeInterval(60),
        uuid: { uuids.next() }
      )

      let maybeUpdated = try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)
      let updated = try #require(maybeUpdated)
      expectNoDifference(
        updated.ingredientLines.sorted { $0.originalText < $1.originalText }.map(\.id),
        [ingredientLineID, extraIngredientLineID]
      )
      expectNoDifference(updated.instructionSteps.map(\.id), [instructionStepID])
      expectNoDifference(
        updated.notes.sorted { $0.text < $1.text }.map(\.noteType),
        [.warning, .general]
      )
      expectNoDifference(
        updated.ingredientSections.map(\.id),
        [ingredientSectionID, extraIngredientSectionID]
      )
    }
  }
}
