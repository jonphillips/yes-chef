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
    expectNoDifference(lines.map(\.item), ["soy sauce", "Kosher salt"])
    expectNoDifference(lines.map(\.preparation), [nil, "to taste"])
  }

  @Test
  func ingredientParserDoesNotTreatFoodWordsAsUnits() {
    let recipeID = SampleUUIDSequence.uuid(11)
    let sectionID = SampleUUIDSequence.uuid(12)
    var uuids = SampleUUIDSequence(start: 13)

    let lines = IngredientParser.lines(
      from: """
      4 anchovy fillets, minced
      1/2 red onion, thinly sliced
      2 celery ribs, sliced
      """,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { uuids.next() }
    )

    expectNoDifference(lines.map(\.quantity), [4, 0.5, 2])
    expectNoDifference(lines.map(\.quantityText), ["4", "1/2", "2"])
    expectNoDifference(lines.map(\.unit), [nil, nil, nil])
    expectNoDifference(lines.map(\.item), ["anchovy fillets", "red onion", "celery ribs"])
    expectNoDifference(lines.map(\.preparation), ["minced", "thinly sliced", "sliced"])
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

    let unitless = IngredientLine(
      id: SampleUUIDSequence.uuid(5),
      recipeID: recipeID,
      sectionID: sectionID,
      originalText: "1/2 red onion, thinly sliced",
      quantity: 0.5,
      quantityText: "1/2",
      item: "red onion",
      preparation: "thinly sliced",
      sortOrder: 2,
      confidence: .medium
    )
    expectNoDifference(IngredientScaler.scaledText(for: unitless, factor: 2), "1 red onion")
  }

  @Test
  func archiveRecipeMarksRecipeArchivedAndPreservesChildren() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
    let archivedAt = now.addingTimeInterval(60)
    let recipeID = SampleUUIDSequence.uuid(201)
    let sectionID = SampleUUIDSequence.uuid(202)
    let lineID = SampleUUIDSequence.uuid(203)

    try database.write { db in
      try Recipe.insert {
        Recipe(
          id: recipeID,
          title: "Archive Me",
          dateCreated: now,
          dateModified: now
        )
      }
      .execute(db)
      try IngredientSection.insert {
        IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
      }
      .execute(db)
      try IngredientLine.insert {
        IngredientLine(
          id: lineID,
          recipeID: recipeID,
          sectionID: sectionID,
          originalText: "1 onion",
          quantity: 1,
          quantityText: "1",
          item: "onion",
          sortOrder: 0,
          confidence: .medium
        )
      }
      .execute(db)

      try RecipeRepository.archive(recipeID: recipeID, in: db, now: archivedAt)

      let archivedRecipe = try #require(try Recipe.find(recipeID).fetchOne(db))
      expectNoDifference(archivedRecipe.archived, true)
      expectNoDifference(archivedRecipe.dateModified, archivedAt)

      let visibleRecipeIDs = try Recipe.fetchAll(db)
        .filter { !$0.archived }
        .map(\.id)
      expectNoDifference(visibleRecipeIDs.contains(recipeID), false)

      let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
      expectNoDifference(detail.ingredientSections.map(\.id), [sectionID])
      expectNoDifference(detail.ingredientLines.map(\.id), [lineID])
    }
  }

  @Test
  func supplementCreatedDatesMatchesBackupByTitleAndSourceURL() throws {
    @Dependency(\.defaultDatabase) var database
    let importedAt = Date(timeIntervalSinceReferenceDate: 802_100_000)
    let paprikaCreatedAt = Date(timeIntervalSinceReferenceDate: 700_100_000)
    let bakedBrieCreatedAt = Date(timeIntervalSinceReferenceDate: 700_200_000)
    let targetID = SampleUUIDSequence.uuid(301)
    let duplicateID = SampleUUIDSequence.uuid(302)
    let bakedBrieID = SampleUUIDSequence.uuid(303)

    try database.write { db in
      try Recipe.insert {
        Recipe(
          id: targetID,
          title: "Kung Pao Chicken - JP",
          dateCreated: importedAt,
          dateModified: importedAt
        )
      }
      .execute(db)
      try RecipeSource.insert {
        RecipeSource(
          id: SampleUUIDSequence.uuid(304),
          recipeID: targetID,
          name: "Cooks Illustrated",
          url: "https://www.cooksillustrated.com/recipes/11227-kung-pao-chicken"
        )
      }
      .execute(db)
      try Recipe.insert {
        Recipe(
          id: duplicateID,
          title: "Kung Pao Chicken - JP",
          dateCreated: importedAt,
          dateModified: importedAt
        )
      }
      .execute(db)
      try RecipeSource.insert {
        RecipeSource(
          id: SampleUUIDSequence.uuid(305),
          recipeID: duplicateID,
          name: "Notebook",
          url: "https://example.com/kung-pao"
        )
      }
      .execute(db)
      try Recipe.insert {
        Recipe(
          id: bakedBrieID,
          title: "Baked Brie",
          dateCreated: importedAt,
          dateModified: importedAt
        )
      }
      .execute(db)

      let summary = try RecipeRepository.supplementCreatedDates(
        from: [
          PaprikaRecipeBackupRecord(
            name: "Kung Pao Chicken — JP",
            sourceName: "cooksillustrated.com",
            sourceURL: "https://www.cooksillustrated.com/recipes/11227-kung-pao-chicken",
            created: paprikaCreatedAt
          ),
          PaprikaRecipeBackupRecord(name: "Baked Brie", created: bakedBrieCreatedAt),
          PaprikaRecipeBackupRecord(name: "Missing Recipe", created: paprikaCreatedAt),
        ],
        in: db
      )

      expectNoDifference(summary.backupRecipeCount, 3)
      expectNoDifference(summary.matchedRecipeCount, 2)
      expectNoDifference(summary.updatedRecipeCount, 2)
      expectNoDifference(summary.unchangedRecipeCount, 0)
      expectNoDifference(summary.ambiguousRecipeCount, 0)
      expectNoDifference(summary.unmatchedRecipeCount, 1)
      expectNoDifference(summary.skippedRecordCount, 0)

      let target = try #require(try Recipe.find(targetID).fetchOne(db))
      let duplicate = try #require(try Recipe.find(duplicateID).fetchOne(db))
      let bakedBrie = try #require(try Recipe.find(bakedBrieID).fetchOne(db))
      expectNoDifference(target.dateCreated, paprikaCreatedAt)
      expectNoDifference(duplicate.dateCreated, importedAt)
      expectNoDifference(bakedBrie.dateCreated, bakedBrieCreatedAt)
    }
  }

  @Test
  func supplementCreatedDatesLeavesAmbiguousTitleMatchesUntouched() throws {
    @Dependency(\.defaultDatabase) var database
    let importedAt = Date(timeIntervalSinceReferenceDate: 802_200_000)
    let paprikaCreatedAt = Date(timeIntervalSinceReferenceDate: 700_300_000)
    let firstID = SampleUUIDSequence.uuid(311)
    let secondID = SampleUUIDSequence.uuid(312)

    try database.write { db in
      try Recipe.insert {
        Recipe(
          id: firstID,
          title: "Duplicate Dish",
          dateCreated: importedAt,
          dateModified: importedAt
        )
      }
      .execute(db)
      try Recipe.insert {
        Recipe(
          id: secondID,
          title: "Duplicate Dish",
          dateCreated: importedAt,
          dateModified: importedAt
        )
      }
      .execute(db)

      let summary = try RecipeRepository.supplementCreatedDates(
        from: [
          PaprikaRecipeBackupRecord(name: "Duplicate Dish", created: paprikaCreatedAt)
        ],
        in: db
      )

      expectNoDifference(summary.backupRecipeCount, 1)
      expectNoDifference(summary.matchedRecipeCount, 0)
      expectNoDifference(summary.updatedRecipeCount, 0)
      expectNoDifference(summary.ambiguousRecipeCount, 1)

      let first = try #require(try Recipe.find(firstID).fetchOne(db))
      let second = try #require(try Recipe.find(secondID).fetchOne(db))
      expectNoDifference(first.dateCreated, importedAt)
      expectNoDifference(second.dateCreated, importedAt)
    }
  }

  @Test
  func savePersistsLibraryPlacement() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 802_300_000)
    var uuids = SampleUUIDSequence(start: 600)

    try database.write { db in
      let recipeID = try RecipeRepository.save(
        draft: RecipeEditorDraft(
          title: "Variant Chocolate Chip Cookies",
          libraryPlacement: .reference,
          ingredientText: "1 cup flour",
          instructionText: "Bake until done."
        ),
        in: db,
        now: now,
        uuid: { uuids.next() }
      )

      let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
      expectNoDifference(detail.recipe.libraryPlacement, .reference)

      let row = try #require(try RecipeListRequest().fetch(db).first { $0.recipe.id == recipeID })
      expectNoDifference(row.recipe.libraryPlacement, .reference)
    }
  }

  @Test
  func saveCreatesHierarchicalCategoryPathsForDisplayAndFiltering() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 802_400_000)
    var uuids = SampleUUIDSequence(start: 700)

    try database.write { db in
      let recipeID = try RecipeRepository.save(
        draft: RecipeEditorDraft(
          title: "Dinner Party Chicken",
          ingredientText: "1 chicken",
          instructionText: "Roast.",
          categoryNames: "Meal Type > Dinner Party, Protein > Chicken"
        ),
        in: db,
        now: now,
        uuid: { uuids.next() }
      )

      let categories = try Category.fetchAll(db)
      let mealType = try #require(categories.first { $0.name == "Meal Type" })
      let dinnerParty = try #require(categories.first { $0.name == "Dinner Party" })
      let protein = try #require(categories.first { $0.name == "Protein" })
      let chicken = try #require(categories.first { $0.name == "Chicken" })

      expectNoDifference(dinnerParty.parentCategoryID, mealType.id)
      expectNoDifference(chicken.parentCategoryID, protein.id)

      let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
      expectNoDifference(
        detail.categoryDisplayNames,
        [
          "Meal Type > Dinner Party",
          "Protein > Chicken",
        ]
      )

      let row = try #require(try RecipeListRequest().fetch(db).first { $0.recipe.id == recipeID })
      expectNoDifference(
        row.categoryNames,
        [
          "Meal Type > Dinner Party",
          "Protein > Chicken",
        ]
      )
      expectNoDifference(
        row.categoryFilterNames,
        [
          "Meal Type",
          "Meal Type > Dinner Party",
          "Protein",
          "Protein > Chicken",
        ]
      )
    }
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
        RecipeSource(
          id: sourceID,
          recipeID: recipeID,
          name: "Notebook",
          importedFrom: "Paprika HTML",
          dateImported: now
        )
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
      draft.sourceAuthor = "Source Author"
      draft.sourcePublicationName = "Source Publication"
      draft.sourceBookTitle = "Source Book"
      draft.sourcePageNumber = "42"
      draft.sourceNotes = "Source metadata stays typed."

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
      expectNoDifference(updated.source?.id, sourceID)
      expectNoDifference(updated.source?.author, "Source Author")
      expectNoDifference(updated.source?.publicationName, "Source Publication")
      expectNoDifference(updated.source?.bookTitle, "Source Book")
      expectNoDifference(updated.source?.pageNumber, "42")
      expectNoDifference(updated.source?.importedFrom, "Paprika HTML")
      expectNoDifference(updated.source?.dateImported, now)
      expectNoDifference(updated.source?.sourceNotes, "Source metadata stays typed.")
    }
  }
}
