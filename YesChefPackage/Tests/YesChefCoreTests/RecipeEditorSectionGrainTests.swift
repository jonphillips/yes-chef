import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  /// The editor now carries every section (recipe-section-grain effort S2). These pin that the save path
  /// round-trips a multi-section recipe unchanged and correctly renames, adds, and removes sections —
  /// deletion being the one behaviour the old merge-only path never had to express.
  @Suite
  struct RecipeEditorSectionGrainTests {
    // Ingredient sections: "Sauce" (2 lines) then "Meatballs" (2 lines).
    // Instruction sections: "Make the sauce" (2 steps) then "Cook" (2 steps).
    // Instruction steps carry a single running global sortOrder, as import assigns them.
    private static let recipeID = SampleUUIDSequence.uuid(50_000)
    private static let sauceSectionID = SampleUUIDSequence.uuid(50_001)
    private static let sauceLine1ID = SampleUUIDSequence.uuid(50_002)
    private static let sauceLine2ID = SampleUUIDSequence.uuid(50_003)
    private static let meatballSectionID = SampleUUIDSequence.uuid(50_004)
    private static let meatballLine1ID = SampleUUIDSequence.uuid(50_005)
    private static let meatballLine2ID = SampleUUIDSequence.uuid(50_006)
    private static let makeSauceSectionID = SampleUUIDSequence.uuid(50_010)
    private static let sauceStep1ID = SampleUUIDSequence.uuid(50_011)
    private static let sauceStep2ID = SampleUUIDSequence.uuid(50_012)
    private static let cookSectionID = SampleUUIDSequence.uuid(50_013)
    private static let cookStep1ID = SampleUUIDSequence.uuid(50_014)
    private static let cookStep2ID = SampleUUIDSequence.uuid(50_015)

    private func seedMultiSectionRecipe(now: Date) throws {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try Recipe.insert {
          Recipe(id: Self.recipeID, title: "Turkey Zucchini Meatballs", dateCreated: now, dateModified: now)
        }
        .execute(db)

        try IngredientSection.insert {
          IngredientSection(id: Self.sauceSectionID, recipeID: Self.recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: Self.sauceLine1ID, recipeID: Self.recipeID, sectionID: Self.sauceSectionID, originalText: "1 cup sour cream", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: Self.sauceLine2ID, recipeID: Self.recipeID, sectionID: Self.sauceSectionID, originalText: "1 tablespoon lemon juice", sortOrder: 1)
        }
        .execute(db)

        try IngredientSection.insert {
          IngredientSection(id: Self.meatballSectionID, recipeID: Self.recipeID, name: "Meatballs", sortOrder: 1)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: Self.meatballLine1ID, recipeID: Self.recipeID, sectionID: Self.meatballSectionID, originalText: "1 pound ground turkey", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: Self.meatballLine2ID, recipeID: Self.recipeID, sectionID: Self.meatballSectionID, originalText: "1 cup grated zucchini", sortOrder: 1)
        }
        .execute(db)

        try InstructionSection.insert {
          InstructionSection(id: Self.makeSauceSectionID, recipeID: Self.recipeID, name: "Make the sauce", sortOrder: 0)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(id: Self.sauceStep1ID, recipeID: Self.recipeID, sectionID: Self.makeSauceSectionID, text: "Stir the sour cream and lemon juice.", sortOrder: 0)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(id: Self.sauceStep2ID, recipeID: Self.recipeID, sectionID: Self.makeSauceSectionID, text: "Chill until serving.", sortOrder: 1)
        }
        .execute(db)

        try InstructionSection.insert {
          InstructionSection(id: Self.cookSectionID, recipeID: Self.recipeID, name: "Cook", sortOrder: 1)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(id: Self.cookStep1ID, recipeID: Self.recipeID, sectionID: Self.cookSectionID, text: "Shape the meatballs.", sortOrder: 2)
        }
        .execute(db)
        try InstructionStep.insert {
          InstructionStep(id: Self.cookStep2ID, recipeID: Self.recipeID, sectionID: Self.cookSectionID, text: "Sear until browned.", sortOrder: 3)
        }
        .execute(db)
      }
    }

    private func fetchedDetail() throws -> RecipeDetailData {
      @Dependency(\.defaultDatabase) var database
      return try database.write { db in
        try #require(try RecipeRepository.fetchDetail(recipeID: Self.recipeID, in: db))
      }
    }

    private func save(_ draft: RecipeEditorDraft, now: Date, uuidStart: Int) throws -> RecipeDetailData {
      @Dependency(\.defaultDatabase) var database
      var uuids = SampleUUIDSequence(start: uuidStart)
      return try database.write { db in
        try RecipeRepository.save(draft: draft, in: db, now: now, uuid: { uuids.next() })
        return try #require(try RecipeRepository.fetchDetail(recipeID: Self.recipeID, in: db))
      }
    }

    private func ingredientShape(_ detail: RecipeDetailData) -> [(name: String?, lines: [(id: UUID, text: String)])] {
      detail.ingredientSections
        .sorted { $0.sortOrder < $1.sortOrder }
        .map { section in
          (
            section.name,
            detail.ingredientLines
              .filter { $0.sectionID == section.id }
              .sorted { $0.sortOrder < $1.sortOrder }
              .map { ($0.id, $0.originalText) }
          )
        }
    }

    private func instructionShape(_ detail: RecipeDetailData) -> [(name: String?, steps: [String])] {
      detail.instructionGroups.map { ($0.name, $0.steps.map(\.text)) }
    }

    @Test
    func twoSectionRecipeRoundTripsUnchanged() throws {
      let now = Date(timeIntervalSinceReferenceDate: 830_000_000)
      try seedMultiSectionRecipe(now: now)
      let before = try fetchedDetail()

      let updated = try save(RecipeEditorDraft(detail: before), now: now.addingTimeInterval(60), uuidStart: 51_000)

      // Ingredient sections, their names, order, line ids, and line text all survive untouched.
      let beforeIngredients = ingredientShape(before)
      let afterIngredients = ingredientShape(updated)
      expectNoDifference(afterIngredients.map(\.name), beforeIngredients.map(\.name))
      expectNoDifference(
        afterIngredients.map { $0.lines.map(\.id) },
        beforeIngredients.map { $0.lines.map(\.id) }
      )
      expectNoDifference(
        afterIngredients.map { $0.lines.map(\.text) },
        beforeIngredients.map { $0.lines.map(\.text) }
      )
      // Instructions read back in section order with per-section numbering intact.
      expectNoDifference(
        instructionShape(updated).map { [$0.name ?? ""] + $0.steps },
        [
          ["Make the sauce", "Stir the sour cream and lemon juice.", "Chill until serving."],
          ["Cook", "Shape the meatballs.", "Sear until browned."],
        ]
      )
    }

    @Test
    func editingSecondSectionLeavesFirstUntouched() throws {
      let now = Date(timeIntervalSinceReferenceDate: 830_100_000)
      try seedMultiSectionRecipe(now: now)
      let before = try fetchedDetail()

      var draft = RecipeEditorDraft(detail: before)
      let meatballIndex = try #require(draft.ingredientSections.firstIndex { $0.id == Self.meatballSectionID })
      draft.ingredientSections[meatballIndex].text += "\n1 egg"

      let updated = try save(draft, now: now.addingTimeInterval(60), uuidStart: 52_000)

      // Section one's rows keep their identities and text.
      let sauceLines = updated.ingredientLines
        .filter { $0.sectionID == Self.sauceSectionID }
        .sorted { $0.sortOrder < $1.sortOrder }
      expectNoDifference(sauceLines.map(\.id), [Self.sauceLine1ID, Self.sauceLine2ID])
      expectNoDifference(sauceLines.map(\.originalText), ["1 cup sour cream", "1 tablespoon lemon juice"])

      // The edited section gains the new line while keeping its existing ones.
      let meatballLines = updated.ingredientLines
        .filter { $0.sectionID == Self.meatballSectionID }
        .sorted { $0.sortOrder < $1.sortOrder }
      expectNoDifference(
        meatballLines.map(\.originalText),
        ["1 pound ground turkey", "1 cup grated zucchini", "1 egg"]
      )
      expectNoDifference(Array(meatballLines.prefix(2)).map(\.id), [Self.meatballLine1ID, Self.meatballLine2ID])
    }

    @Test
    func renamingSectionPersists() throws {
      let now = Date(timeIntervalSinceReferenceDate: 830_200_000)
      try seedMultiSectionRecipe(now: now)
      var draft = RecipeEditorDraft(detail: try fetchedDetail())
      let sauceIndex = try #require(draft.ingredientSections.firstIndex { $0.id == Self.sauceSectionID })
      draft.ingredientSections[sauceIndex].name = "Yogurt Sauce"

      let updated = try save(draft, now: now.addingTimeInterval(60), uuidStart: 53_000)

      let renamed = try #require(updated.ingredientSections.first { $0.id == Self.sauceSectionID })
      expectNoDifference(renamed.name, "Yogurt Sauce")
      let untouched = try #require(updated.ingredientSections.first { $0.id == Self.meatballSectionID })
      expectNoDifference(untouched.name, "Meatballs")
    }

    @Test
    func addingSectionCreatesRows() throws {
      let now = Date(timeIntervalSinceReferenceDate: 830_300_000)
      try seedMultiSectionRecipe(now: now)
      var draft = RecipeEditorDraft(detail: try fetchedDetail())
      let newSectionID = SampleUUIDSequence.uuid(54_900)
      draft.ingredientSections.append(
        RecipeEditorIngredientSectionDraft(id: newSectionID, name: "Garnish", text: "2 tablespoons chopped dill")
      )

      let updated = try save(draft, now: now.addingTimeInterval(60), uuidStart: 54_000)

      let added = try #require(updated.ingredientSections.first { $0.id == newSectionID })
      expectNoDifference(added.name, "Garnish")
      expectNoDifference(added.sortOrder, 2)
      let addedLines = updated.ingredientLines.filter { $0.sectionID == newSectionID }
      expectNoDifference(addedLines.map(\.originalText), ["2 tablespoons chopped dill"])
    }

    @Test
    func deletingSectionRemovesItsRows() throws {
      let now = Date(timeIntervalSinceReferenceDate: 830_400_000)
      try seedMultiSectionRecipe(now: now)
      var draft = RecipeEditorDraft(detail: try fetchedDetail())
      draft.instructionSections.removeAll { $0.id == Self.cookSectionID }

      let updated = try save(draft, now: now.addingTimeInterval(60), uuidStart: 55_000)

      expectNoDifference(updated.instructionSections.contains { $0.id == Self.cookSectionID }, false)
      expectNoDifference(updated.instructionSteps.contains { $0.sectionID == Self.cookSectionID }, false)
      // The surviving section is intact.
      expectNoDifference(
        instructionShape(updated).map { [$0.name ?? ""] + $0.steps },
        [["Make the sauce", "Stir the sour cream and lemon juice.", "Chill until serving."]]
      )
    }

    @Test
    func perSectionStepRenumberingStaysOrderedAcrossSections() throws {
      let now = Date(timeIntervalSinceReferenceDate: 830_500_000)
      try seedMultiSectionRecipe(now: now)
      var draft = RecipeEditorDraft(detail: try fetchedDetail())
      let makeSauceIndex = try #require(draft.instructionSections.firstIndex { $0.id == Self.makeSauceSectionID })
      draft.instructionSections[makeSauceIndex].text += "\n\nTaste and adjust salt."

      let updated = try save(draft, now: now.addingTimeInterval(60), uuidStart: 56_000)

      // Section one renumbers 0…2 on save; section two would collide on a flat sort, but grouping by
      // (section.sortOrder, step.sortOrder) keeps sauce before cook regardless (S1 made this safe).
      expectNoDifference(
        instructionShape(updated).map { [$0.name ?? ""] + $0.steps },
        [
          ["Make the sauce", "Stir the sour cream and lemon juice.", "Chill until serving.", "Taste and adjust salt."],
          ["Cook", "Shape the meatballs.", "Sear until browned."],
        ]
      )
      let cookSortOrders = updated.instructionSteps
        .filter { $0.sectionID == Self.cookSectionID }
        .map(\.sortOrder)
        .sorted()
      let sauceSortOrders = updated.instructionSteps
        .filter { $0.sectionID == Self.makeSauceSectionID }
        .map(\.sortOrder)
        .sorted()
      // Both sections now start at 0 — global step-order uniqueness is no longer load-bearing.
      expectNoDifference(sauceSortOrders, [0, 1, 2])
      expectNoDifference(cookSortOrders, [0, 1])
    }
  }
}
