import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeEditorIngredientSectionSyntaxTests {
    @Test
    func colonHeaderSplitsCardAndPreservesMovedLineIDs() {
      let eggsID = SampleUUIDSequence.uuid(71_001)
      let creamID = SampleUUIDSequence.uuid(71_002)
      var uuids = SampleUUIDSequence(start: 71_003)
      var draft = RecipeEditorDraft(ingredientText: "2 eggs\nFor the sauce:\n1 cup cream")
      let originalSectionID = draft.ingredientSections[0].id
      draft.ingredientSections[0].lineDrafts = [
        RecipeIngredientLineDraft(id: eggsID, originalText: "2 eggs", sortOrder: 0),
        RecipeIngredientLineDraft(id: creamID, originalText: "1 cup cream", sortOrder: 1),
      ]

      draft.ingredientTextChanged(
        sectionID: originalSectionID,
        uuid: { uuids.next() }
      )

      expectNoDifference(draft.ingredientSections.map(\.id), [originalSectionID, SampleUUIDSequence.uuid(71_003)])
      expectNoDifference(draft.ingredientSections.map(\.name), ["", "For the sauce"])
      expectNoDifference(draft.ingredientSections.map(\.text), ["2 eggs", "1 cup cream"])
      expectNoDifference(draft.ingredientSections.map { $0.lineDrafts.map(\.id) }, [[eggsID], [creamID]])

      // Re-parsing the visible cards is idempotent: it neither mints another section nor loses a line ID.
      draft.ingredientTextChanged(
        sectionID: originalSectionID,
        uuid: { uuids.next() }
      )
      expectNoDifference(draft.ingredientSections.map(\.id), [originalSectionID, SampleUUIDSequence.uuid(71_003)])
      expectNoDifference(draft.ingredientSections.map { $0.lineDrafts.map(\.id) }, [[eggsID], [creamID]])
    }

    @Test
    func quantityBearingTrailingColonRemainsAnIngredient() {
      var draft = RecipeEditorDraft(ingredientText: "1 cup Salt:")
      let sectionID = draft.ingredientSections[0].id

      draft.ingredientTextChanged(sectionID: sectionID, uuid: { SampleUUIDSequence.uuid(71_100) })

      expectNoDifference(draft.ingredientSections.map(\.id), [sectionID])
      expectNoDifference(draft.ingredientSections.map(\.name), [""])
      expectNoDifference(draft.ingredientSections.map(\.text), ["1 cup Salt:"])
    }

    @Test
    func ordinaryEditsLeaveRawIngredientTextUntouched() {
      var draft = RecipeEditorDraft(ingredientText: "2 eggs\n\n  1 cup cream  \n")
      let sectionID = draft.ingredientSections[0].id

      draft.ingredientTextChanged(sectionID: sectionID, uuid: { SampleUUIDSequence.uuid(71_150) })

      expectNoDifference(draft.ingredientSections[0].text, "2 eggs\n\n  1 cup cream  \n")
      expectNoDifference(draft.ingredientSections[0].lineDrafts.map(\.originalText), ["2 eggs", "1 cup cream"])
    }

    @Test
    func explicitSectionActionAndClearingNameRoundTripLineIDs() {
      let tomatoesID = SampleUUIDSequence.uuid(71_201)
      let basilID = SampleUUIDSequence.uuid(71_202)
      var draft = RecipeEditorDraft(ingredientText: "2 tomatoes\nFor garnish\n1 basil sprig")
      let originalSectionID = draft.ingredientSections[0].id
      draft.ingredientSections[0].lineDrafts = [
        RecipeIngredientLineDraft(id: tomatoesID, originalText: "2 tomatoes", sortOrder: 0),
        RecipeIngredientLineDraft(id: basilID, originalText: "1 basil sprig", sortOrder: 1),
      ]

      draft.startIngredientSection(
        sectionID: originalSectionID,
        atLineIndex: 1,
        uuid: { SampleUUIDSequence.uuid(71_203) }
      )

      let garnishSectionID = SampleUUIDSequence.uuid(71_203)
      expectNoDifference(draft.ingredientSections.map(\.id), [originalSectionID, garnishSectionID])
      expectNoDifference(draft.ingredientSections.map(\.name), ["", "For garnish"])
      expectNoDifference(draft.ingredientSections.map { $0.lineDrafts.map(\.id) }, [[tomatoesID], [basilID]])

      draft.ingredientSections[1].name = ""
      draft.ingredientSectionNameChanged(sectionID: garnishSectionID)

      expectNoDifference(draft.ingredientSections.map(\.id), [originalSectionID])
      expectNoDifference(draft.ingredientSections.map(\.text), ["2 tomatoes\n1 basil sprig"])
      expectNoDifference(draft.ingredientSections[0].lineDrafts.map(\.id), [tomatoesID, basilID])
    }

    @Test
    func headerNameDoesNotAccumulateColonsAcrossSaveReloadSave() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 831_000_000)
      var uuids = SampleUUIDSequence(start: 71_300)
      let draft = RecipeEditorDraft(title: "Colon Cake", ingredientText: "For the batter:\n2 cups flour")

      try database.write { db in
        let recipeID = try RecipeRepository.save(draft: draft, in: db, now: now, uuid: { uuids.next() })
        let saved = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(saved.ingredientSections.map(\.name), ["For the batter"])
        expectNoDifference(saved.ingredientLines.map(\.isHeader), [false])

        _ = try RecipeRepository.save(
          draft: RecipeEditorDraft(detail: saved),
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { uuids.next() }
        )

        let roundTripped = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(roundTripped.ingredientSections.map(\.name), ["For the batter"])
      }
    }

    @Test
    func splittingThenSavingRetainsMovedLineIdentityAndEnrichment() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 831_100_000)
      let recipeID = SampleUUIDSequence.uuid(71_400)
      let sectionID = SampleUUIDSequence.uuid(71_401)
      let eggsID = SampleUUIDSequence.uuid(71_402)
      let creamID = SampleUUIDSequence.uuid(71_403)
      var uuids = SampleUUIDSequence(start: 71_500)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Eggs", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: eggsID, recipeID: recipeID, sectionID: sectionID, originalText: "2 eggs", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: creamID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 cup cream",
            canonicalName: "heavy cream",
            shoppingCategory: "Dairy",
            doNotShop: true,
            sortOrder: 1
          )
        }
        .execute(db)

        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        var draft = RecipeEditorDraft(detail: detail)
        draft.ingredientSections[0].text = "2 eggs\nFor the sauce:\n1 cup cream"
        draft.ingredientTextChanged(sectionID: sectionID, uuid: { uuids.next() })

        try RecipeRepository.save(draft: draft, in: db, now: now.addingTimeInterval(60), uuid: { uuids.next() })

        let saved = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let cream = try #require(saved.ingredientLines.first { $0.id == creamID })
        expectNoDifference(cream.sectionID, SampleUUIDSequence.uuid(71_500))
        expectNoDifference(cream.canonicalName, "heavy cream")
        expectNoDifference(cream.shoppingCategory, "Dairy")
        expectNoDifference(cream.doNotShop, true)
        expectNoDifference(saved.ingredientLines.map(\.id).contains(creamID), true)

        _ = try RecipeRepository.save(
          draft: RecipeEditorDraft(detail: saved),
          in: db,
          now: now.addingTimeInterval(120),
          uuid: { uuids.next() }
        )
        let noOpSaved = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(noOpSaved.ingredientLines.first { $0.id == creamID }?.canonicalName, "heavy cream")
      }
    }

    @Test
    func trailingHeaderPersistsAsAnEmptyNamedSection() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 831_200_000)
      var uuids = SampleUUIDSequence(start: 71_600)
      var draft = RecipeEditorDraft(title: "Sauce", ingredientText: "2 eggs\nFor the sauce:")
      draft.ingredientTextChanged(sectionID: draft.ingredientSections[0].id, uuid: { uuids.next() })

      try database.write { db in
        let recipeID = try RecipeRepository.save(draft: draft, in: db, now: now, uuid: { uuids.next() })
        let saved = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(saved.ingredientSections.map(\.name), [nil, "For the sauce"])
        expectNoDifference(saved.ingredientLines.map(\.originalText), ["2 eggs"])
      }
    }

    @Test
    func nonInteractiveDraftBuildersPromoteColonHeadingsBeforeSave() {
      let workbenchDraft = WorkbenchDraftRecipe(
        title: "Sauce",
        ingredientLines: ["For the sauce:", "1 cup cream"],
        instructionLines: [],
        notes: [],
        rationale: "Draft"
      )
      let draft = workbenchDraft.editorDraft(
        libraryPlacement: .reference,
        uuid: { SampleUUIDSequence.uuid(71_700) }
      )

      expectNoDifference(draft.ingredientSections.map(\.name), ["For the sauce"])
      expectNoDifference(draft.ingredientSections.map(\.text), ["1 cup cream"])
    }
  }
}
