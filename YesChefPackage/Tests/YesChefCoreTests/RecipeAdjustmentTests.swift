import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeAdjustmentTests {
    @Test
    func parsesStructuredDeltaJSON() {
      let ingredientID = SampleUUIDSequence.uuid(31_001)
      let stepID = SampleUUIDSequence.uuid(31_002)

      let proposal = RecipeAdjustmentClient.parse(
        """
        Here is the delta:
        {"summary":"Make it brighter","ingredientOps":[{"op":"substitute","baseIngredientID":"\(ingredientID.uuidString)","originalText":"1 tablespoon lemon juice","line":"2 tablespoons lime juice"},{"op":"add","line":"1 teaspoon lime zest","sectionName":"Sauce"}],"methodNote":"Taste before serving.","methodStepReplacements":[{"baseStepID":"\(stepID.uuidString)","stepNumber":2,"originalText":"Serve.","replacementText":"Taste, adjust, and serve."}]}
        """
      )

      expectNoDifference(
        proposal,
        RecipeAdjustmentProposal(
          summary: "Make it brighter",
          ingredientOps: [
            .substitute(
              RecipeIngredientReference(id: ingredientID, originalText: "1 tablespoon lemon juice"),
              line: "2 tablespoons lime juice"
            ),
            .add(line: "1 teaspoon lime zest", sectionName: "Sauce"),
          ],
          methodNote: "Taste before serving.",
          methodStepReplacements: [
            RecipeMethodStepReplacement(
              id: stepID,
              stepNumber: 2,
              originalText: "Serve.",
              replacementText: "Taste, adjust, and serve."
            )
          ]
        )
      )
    }

    @Test
    func appliesIngredientAndWholeStepDeltaToPreview() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_000_000)
      let recipeID = SampleUUIDSequence.uuid(31_100)
      let sectionID = SampleUUIDSequence.uuid(31_101)
      let instructionSectionID = SampleUUIDSequence.uuid(31_102)
      let lemonID = SampleUUIDSequence.uuid(31_103)
      let saltID = SampleUUIDSequence.uuid(31_104)
      let stepID = SampleUUIDSequence.uuid(31_105)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Lemon Pasta", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        ingredientLines: [
          IngredientLine(
            id: lemonID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 tablespoon lemon juice",
            sortOrder: 0
          ),
          IngredientLine(
            id: saltID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 teaspoon kosher salt",
            sortOrder: 1
          ),
        ],
        instructionSections: [InstructionSection(id: instructionSectionID, recipeID: recipeID, sortOrder: 0)],
        instructionSteps: [
          InstructionStep(id: stepID, recipeID: recipeID, sectionID: instructionSectionID, text: "Toss and serve.", sortOrder: 0)
        ]
      )
      let proposal = RecipeAdjustmentProposal(
        summary: "Make it brighter.",
        ingredientOps: [
          .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
          .remove(RecipeIngredientReference(originalText: "1 teaspoon kosher salt")),
          .add(line: "1 teaspoon lime zest", sectionName: nil),
        ],
        methodNote: "Taste for salt at the end.",
        methodStepReplacements: [
          RecipeMethodStepReplacement(id: stepID, replacementText: "Toss, taste for salt, and serve.")
        ]
      )
      var uuids = SampleUUIDSequence(start: 31_200)

      let preview = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { uuids.next() })

      expectNoDifference(
        preview.ingredientLines.map(\.originalText),
        ["2 tablespoons lime juice", "1 teaspoon lime zest"]
      )
      expectNoDifference(preview.instructionSteps.map(\.text), ["Toss, taste for salt, and serve."])
      expectNoDifference(preview.notes.map(\.text), ["Taste for salt at the end."])
    }

    @Test
    func appliesIngredientDeltaAcrossSectionsPreservingIDs() throws {
      let now = Date(timeIntervalSinceReferenceDate: 819_050_000)
      let recipeID = SampleUUIDSequence.uuid(31_210)
      let chickenSectionID = SampleUUIDSequence.uuid(31_211)
      let sauceSectionID = SampleUUIDSequence.uuid(31_212)
      let prepSectionID = SampleUUIDSequence.uuid(31_213)
      let cookSectionID = SampleUUIDSequence.uuid(31_214)
      let chickenID = SampleUUIDSequence.uuid(31_215)
      let lemonID = SampleUUIDSequence.uuid(31_216)
      let honeyID = SampleUUIDSequence.uuid(31_217)
      let prepStepID = SampleUUIDSequence.uuid(31_218)
      let cookStepID = SampleUUIDSequence.uuid(31_219)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Lemon Chicken", dateCreated: now, dateModified: now),
        ingredientSections: [
          IngredientSection(id: chickenSectionID, recipeID: recipeID, name: "For the chicken", sortOrder: 0),
          IngredientSection(id: sauceSectionID, recipeID: recipeID, name: "For the sauce", sortOrder: 1),
        ],
        ingredientLines: [
          IngredientLine(id: chickenID, recipeID: recipeID, sectionID: chickenSectionID, originalText: "1 pound chicken thighs", sortOrder: 0),
          IngredientLine(id: lemonID, recipeID: recipeID, sectionID: sauceSectionID, originalText: "1 tablespoon lemon juice", sortOrder: 0),
          IngredientLine(id: honeyID, recipeID: recipeID, sectionID: sauceSectionID, originalText: "1 teaspoon honey", sortOrder: 1),
        ],
        instructionSections: [
          InstructionSection(id: prepSectionID, recipeID: recipeID, name: "Prep", sortOrder: 0),
          InstructionSection(id: cookSectionID, recipeID: recipeID, name: "Cook", sortOrder: 1),
        ],
        instructionSteps: [
          InstructionStep(id: prepStepID, recipeID: recipeID, sectionID: prepSectionID, text: "Season the chicken.", sortOrder: 0),
          InstructionStep(id: cookStepID, recipeID: recipeID, sectionID: cookSectionID, text: "Simmer the sauce.", sortOrder: 0),
        ]
      )
      let proposal = RecipeAdjustmentProposal(
        ingredientOps: [
          .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
          .add(line: "1 teaspoon grated ginger", sectionName: "for the sauce"),
          .remove(RecipeIngredientReference(originalText: "1 teaspoon honey")),
        ],
        methodStepReplacements: [
          RecipeMethodStepReplacement(stepNumber: 2, replacementText: "Simmer the sauce until glossy.")
        ]
      )
      var uuids = SampleUUIDSequence(start: 31_220)

      let preview = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { uuids.next() })

      let linesBySection = Dictionary(grouping: preview.ingredientLines) { $0.sectionID }
      expectNoDifference(linesBySection[chickenSectionID]?.map(\.originalText), ["1 pound chicken thighs"])
      expectNoDifference(linesBySection[sauceSectionID]?.map(\.originalText), ["2 tablespoons lime juice", "1 teaspoon grated ginger"])
      let replacedLine = try #require(preview.ingredientLines.first { $0.id == lemonID })
      expectNoDifference(replacedLine.sectionID, sauceSectionID)
      expectNoDifference(replacedLine.sortOrder, 0)
      expectNoDifference(replacedLine.item, "lime juice")
      expectNoDifference(preview.ingredientLines.contains { $0.id == honeyID }, false)
      let addedLine = try #require(preview.ingredientLines.first { $0.originalText == "1 teaspoon grated ginger" })
      expectNoDifference(addedLine.sectionID, sauceSectionID)
      expectNoDifference(addedLine.sortOrder, 2)
      let replacedStep = try #require(preview.instructionSteps.first { $0.id == cookStepID })
      expectNoDifference(replacedStep.sectionID, cookSectionID)
      expectNoDifference(replacedStep.text, "Simmer the sauce until glossy.")
    }

    @Test
    func overwriteAndUndoRestoreTheRecipeWhileKeepingTheDeliberationRecord() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_100_000)
      let later = now.addingTimeInterval(60)
      let recipeID = SampleUUIDSequence.uuid(31_300)
      let originalSnapshot = Data("original import baseline".utf8)
      var uuids = SampleUUIDSequence(start: 31_400)

      _ = try database.write { db in
        try RecipeRepository.save(
          draft: RecipeEditorDraft(
            id: recipeID,
            title: "Lemon Pasta",
            servingsText: "4 servings",
            ingredientText: "1 tablespoon lemon juice\n1 teaspoon kosher salt",
            instructionText: "Toss and serve.",
            originalSnapshot: originalSnapshot,
            dateCreated: now
          ),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
      }

      let restorePoint = try database.write { db in
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        let lemonLine = try #require(detail.ingredientLines.first { $0.originalText == "1 tablespoon lemon juice" })
        return try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          RecipeAdjustmentProposal(
            summary: "Use lime.",
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonLine.id), line: "2 tablespoons lime juice")
            ],
            methodStepReplacements: [
              RecipeMethodStepReplacement(stepNumber: 1, replacementText: "Toss, taste, and serve.")
            ]
          ),
          recipeID: recipeID,
          deliberationBody: "Use lime.",
          in: db,
          now: later,
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let adjusted = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(adjusted.ingredientLines.map(\.originalText), ["2 tablespoons lime juice", "1 teaspoon kosher salt"])
        expectNoDifference(adjusted.instructionSteps.map(\.text), ["Toss, taste, and serve."])
        expectNoDifference(adjusted.recipe.originalSnapshot, originalSnapshot)
      }

      try database.write { db in
        try RecipeRepository.restoreRecipeAdjustment(
          restorePoint,
          recipeID: recipeID,
          in: db,
          now: later.addingTimeInterval(60),
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let restored = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(restored.ingredientLines.map(\.originalText), ["1 tablespoon lemon juice", "1 teaspoon kosher salt"])
        expectNoDifference(restored.instructionSteps.map(\.text), ["Toss and serve."])
        expectNoDifference(restored.recipe.originalSnapshot, originalSnapshot)
        expectNoDifference(restored.deliberationLogEntries.map(\.body), ["Use lime."])
      }
    }

    @Test
    func overwriteAndRestorePreserveTwoSectionRecipeAndUnrelatedData() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_150_000)
      let later = now.addingTimeInterval(60)
      let restoredAt = now.addingTimeInterval(120)
      let recipeID = SampleUUIDSequence.uuid(31_600)
      let chickenSectionID = SampleUUIDSequence.uuid(31_601)
      let sauceSectionID = SampleUUIDSequence.uuid(31_602)
      let prepSectionID = SampleUUIDSequence.uuid(31_603)
      let cookSectionID = SampleUUIDSequence.uuid(31_604)
      let chickenID = SampleUUIDSequence.uuid(31_605)
      let lemonID = SampleUUIDSequence.uuid(31_606)
      let honeyID = SampleUUIDSequence.uuid(31_607)
      let prepStepID = SampleUUIDSequence.uuid(31_608)
      let cookStepID = SampleUUIDSequence.uuid(31_609)
      let sourceID = SampleUUIDSequence.uuid(31_610)
      let photoID = SampleUUIDSequence.uuid(31_611)
      let tagID = SampleUUIDSequence.uuid(31_612)
      let recipeTagID = SampleUUIDSequence.uuid(31_613)
      let categoryID = SampleUUIDSequence.uuid(31_614)
      let recipeCategoryID = SampleUUIDSequence.uuid(31_615)
      let generalNoteID = SampleUUIDSequence.uuid(31_616)
      let adaptationNoteID = SampleUUIDSequence.uuid(31_617)
      let originalSnapshot = Data("original import baseline".utf8)
      var uuids = SampleUUIDSequence(start: 31_700)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Lemon Chicken",
            dateCreated: now,
            dateModified: now,
            originalSnapshot: originalSnapshot,
            coverPhotoID: photoID
          )
        }
        .execute(db)
        try RecipeSource.insert {
          RecipeSource(id: sourceID, recipeID: recipeID, name: "Notebook", url: "https://example.com/lemon-chicken")
        }
        .execute(db)
        for section in [
          IngredientSection(id: chickenSectionID, recipeID: recipeID, name: "For the chicken", sortOrder: 0),
          IngredientSection(id: sauceSectionID, recipeID: recipeID, name: "For the sauce", sortOrder: 1),
        ] {
          try IngredientSection.insert { section }.execute(db)
        }
        for line in [
          IngredientLine(id: chickenID, recipeID: recipeID, sectionID: chickenSectionID, originalText: "1 pound chicken thighs", sortOrder: 0),
          IngredientLine(id: lemonID, recipeID: recipeID, sectionID: sauceSectionID, originalText: "1 tablespoon lemon juice", sortOrder: 0),
          IngredientLine(id: honeyID, recipeID: recipeID, sectionID: sauceSectionID, originalText: "1 teaspoon honey", sortOrder: 1),
        ] {
          try IngredientLine.insert { line }.execute(db)
        }
        for section in [
          InstructionSection(id: prepSectionID, recipeID: recipeID, name: "Prep", sortOrder: 0),
          InstructionSection(id: cookSectionID, recipeID: recipeID, name: "Cook", sortOrder: 1),
        ] {
          try InstructionSection.insert { section }.execute(db)
        }
        for step in [
          InstructionStep(id: prepStepID, recipeID: recipeID, sectionID: prepSectionID, text: "Season the chicken.", sortOrder: 0),
          InstructionStep(id: cookStepID, recipeID: recipeID, sectionID: cookSectionID, text: "Simmer the sauce.", sortOrder: 0),
        ] {
          try InstructionStep.insert { step }.execute(db)
        }
        for note in [
          RecipeNote(id: generalNoteID, recipeID: recipeID, text: "Serve hot.", dateCreated: now, dateModified: now),
          RecipeNote(id: adaptationNoteID, recipeID: recipeID, text: "Works with thighs.", noteType: .adaptation, dateCreated: now, dateModified: now),
        ] {
          try RecipeNote.insert { note }.execute(db)
        }
        try RecipePhoto.insert {
          RecipePhoto(id: photoID, recipeID: recipeID, imageDataReference: "recipePhotos/\(photoID.uuidString)", displayData: Data([1]), sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try Tag.insert { Tag(id: tagID, name: "Dinner", sortOrder: 0, dateCreated: now) }.execute(db)
        try RecipeTag.insert { RecipeTag(id: recipeTagID, recipeID: recipeID, tagID: tagID, sortOrder: 0) }.execute(db)
        try Category.insert { Category(id: categoryID, name: "Chicken", sortOrder: 0, dateCreated: now) }.execute(db)
        try RecipeCategory.insert { RecipeCategory(id: recipeCategoryID, recipeID: recipeID, categoryID: categoryID) }.execute(db)
      }

      let restorePoint = try database.write { db in
        try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          RecipeAdjustmentProposal(
            ingredientOps: [
              .substitute(RecipeIngredientReference(id: lemonID), line: "2 tablespoons lime juice"),
              .add(line: "1 teaspoon grated ginger", sectionName: "For the sauce"),
              .remove(RecipeIngredientReference(id: honeyID)),
            ],
            methodNote: "Taste before serving.",
            methodStepReplacements: [
              RecipeMethodStepReplacement(id: cookStepID, replacementText: "Simmer the sauce until glossy.")
            ]
          ),
          recipeID: recipeID,
          deliberationBody: nil,
          in: db,
          now: later,
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let adjusted = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(adjusted.ingredientSections.map(\.name), ["For the chicken", "For the sauce"])
        expectNoDifference(adjusted.ingredientLines.map(\.originalText), [
          "1 pound chicken thighs",
          "2 tablespoons lime juice",
          "1 teaspoon grated ginger",
        ])
        expectNoDifference(adjusted.instructionSteps.map(\.text), ["Season the chicken.", "Simmer the sauce until glossy."])
        expectNoDifference(adjusted.notes.filter { $0.noteType == .general }.map(\.text).sorted(), ["Serve hot.", "Taste before serving."])
        expectNoDifference(adjusted.notes.filter { $0.noteType == .adaptation }.map(\.text), ["Works with thighs."])
        expectNoDifference(adjusted.source?.url, "https://example.com/lemon-chicken")
        expectNoDifference(adjusted.photos.map(\.id), [photoID])
        expectNoDifference(adjusted.tags.map(\.name), ["Dinner"])
        expectNoDifference(adjusted.categoryDisplayNames, ["Chicken"])
        expectNoDifference(adjusted.recipe.originalSnapshot, originalSnapshot)
        expectNoDifference(adjusted.recipe.coverPhotoID, photoID)
      }

      try database.write { db in
        try RecipeRepository.restoreRecipeAdjustment(
          restorePoint,
          recipeID: recipeID,
          in: db,
          now: restoredAt,
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let restored = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(restored.ingredientSections.map(\.name), ["For the chicken", "For the sauce"])
        expectNoDifference(restored.ingredientLines.map(\.originalText), [
          "1 pound chicken thighs",
          "1 tablespoon lemon juice",
          "1 teaspoon honey",
        ])
        expectNoDifference(restored.instructionSections.map(\.name), ["Prep", "Cook"])
        expectNoDifference(restored.instructionSteps.map(\.text), ["Season the chicken.", "Simmer the sauce."])
        expectNoDifference(restored.notes.filter { $0.noteType == .general }.map(\.text), ["Serve hot."])
        expectNoDifference(restored.notes.filter { $0.noteType == .adaptation }.map(\.text), ["Works with thighs."])
        expectNoDifference(restored.source?.url, "https://example.com/lemon-chicken")
        expectNoDifference(restored.photos.map(\.id), [photoID])
        expectNoDifference(restored.tags.map(\.name), ["Dinner"])
        expectNoDifference(restored.categoryDisplayNames, ["Chicken"])
        expectNoDifference(restored.recipe.originalSnapshot, originalSnapshot)
        expectNoDifference(restored.recipe.coverPhotoID, photoID)
      }
    }

    @Test
    func liveClientThrowsOnTruncatedResponse() async throws {
      await #expect(throws: RecipeAdjustmentError.responseTruncated) {
        try await withDependencies {
          $0.modelClient = StubModelClient { _ in ModelResponse(text: "", stopReason: "length") }
        } operation: {
          try await RecipeAdjustmentClient.liveValue(
            selection: "make it brighter",
            messages: [],
            detail: RecipeDetailData(
              recipe: Recipe(
                id: SampleUUIDSequence.uuid(31_500),
                title: "Lemon Pasta",
                dateCreated: Date(timeIntervalSinceReferenceDate: 819_200_000),
                dateModified: Date(timeIntervalSinceReferenceDate: 819_200_000)
              )
            ),
            tier: .onDevice,
            tierResolution: .callerProvided
          )
        }
      }
    }
  }
}
