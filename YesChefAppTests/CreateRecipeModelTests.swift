import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct CreateRecipeModelTests {
  @Test
  func movingRecipeSectionsReordersDraftAndMarksItDirty() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_000_000)
    } operation: {
    let firstIngredientID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let secondIngredientID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let firstInstructionID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let secondInstructionID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    var draft = RecipeEditorDraft()
    draft.ingredientSections = [
      RecipeEditorIngredientSectionDraft(id: firstIngredientID, name: "First"),
      RecipeEditorIngredientSectionDraft(id: secondIngredientID, name: "Second"),
    ]
    draft.instructionSections = [
      RecipeEditorInstructionSectionDraft(id: firstInstructionID, name: "First"),
      RecipeEditorInstructionSectionDraft(id: secondInstructionID, name: "Second"),
    ]

    let model = RecipeEditorModel(seededDraft: draft)
    #expect(!model.hasUnsavedEdits)

    model.moveIngredientSection(id: secondIngredientID, up: true)
    model.moveInstructionSection(id: firstInstructionID, up: false)

    #expect(model.draft.ingredientSections.map(\.id) == [secondIngredientID, firstIngredientID])
    #expect(model.draft.instructionSections.map(\.id) == [secondInstructionID, firstInstructionID])
    #expect(model.hasUnsavedEdits)

    model.moveIngredientSection(id: secondIngredientID, up: true)
    model.moveInstructionSection(id: firstInstructionID, up: false)
    #expect(model.draft.ingredientSections.map(\.id) == [secondIngredientID, firstIngredientID])
    #expect(model.draft.instructionSections.map(\.id) == [secondInstructionID, firstInstructionID])
    }
  }

  @Test
  func pastedImageDataCreatesPendingHeroPhotoWithPastedSourcePath() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      let model = RecipeEditorModel(seededDraft: RecipeEditorDraft())

      await model.heroPhotoSelected(
        sourceData: Data([0x01, 0x02, 0x03, 0x04]),
        sourcePath: "Pasted Image.png"
      )

      let photo = try #require(model.draft.pendingPhotos.first)
      #expect(photo.kind == .hero)
      #expect(photo.originalSourcePath == "Pasted Image.png")
    }
  }

  @Test
  func emptyShortcutTextFailsWithoutStagingASession() async {
    let coordinator = CreateRecipeCoordinator()

    await withDependencies {
      $0.createRecipeCoordinator = coordinator
    } operation: {
      await #expect(throws: CaptureRecipeError.emptyText) {
        try await CaptureRecipeFromText(text: "  \n ").perform()
      }

      #expect(coordinator.stagedText == nil)
    }
  }

  @Test
  func referralIntentKeepsRawTextAndTypedProvenanceWithMachineID() async throws {
    let provenance = FindProvenance(
      sender: "news@example.com",
      publisher: "Example Kitchen",
      seriesID: "weekly-recipes",
      contentPieceToken: "opaque-content-piece",
      note: "This looked worth trying."
    )

    var coordinator: CreateRecipeCoordinator?
    try await withDependencies {
      $0.uuid = .incrementing
      coordinator = CreateRecipeCoordinator()
      $0.createRecipeCoordinator = coordinator!
    } operation: {
      let coordinator = coordinator!
      _ = try await CaptureRecipeFromText(
        rawText: "Newsletter chrome\nRecipe body\nFooter",
        provenance: provenance,
        referralID: "opaque-referral"
      ).perform()

      #expect(coordinator.stagedText?.text == "Newsletter chrome\nRecipe body\nFooter")
      #expect(coordinator.referralID == "opaque-referral")
      #expect(coordinator.stagedText?.referral?.provenance == provenance)
      #expect(coordinator.stagedText?.referral?.provenance.contentPieceToken == "opaque-content-piece")
    }
  }

  @Test
  func referralSaveEmitsAnAdmittedVerdictWithoutPersistingReferralMetadata() async throws {
    let recorder = AppFindReturnRecorder()
    let referral = FindReferral(
      referralID: "referral-save",
      rawText: "A recipe from Find",
      provenance: FindProvenance(contentPieceToken: "cockpit-token")
    )

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_000)
      $0.recipeExtractionClient = RecipeExtractionClient { _ in
        RecipeExtraction(
          title: "Find Beans",
          ingredientSections: [.init(lines: ["1 cup beans"])],
          instructionSections: [.init(steps: ["Simmer the beans."])]
        )
      }
      $0.findReturnEmitter = FindReturnEmitter { verdict in
        await recorder.record(verdict)
      }
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      coordinator.stage(referral: referral)
      await coordinator.applyStagedText(to: model)

      let recipeID = try #require(await coordinator.saveButtonTapped(for: model))
      let verdicts = await recorder.verdicts

      #expect(verdicts == [FindVerdict(referralID: "referral-save", outcomes: [.admitted(FindRecipeRef(recipeID))])])
      #expect(coordinator.referralID == nil)
      #expect(model.referralProvenance?.contentPieceToken == "cockpit-token")
    }
  }

  @Test
  func referralDismissalEmitsAFirstClassDecline() async throws {
    let recorder = AppFindReturnRecorder()

    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { verdict in
        await recorder.record(verdict)
      }
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      coordinator.stage(
        referral: FindReferral(
          referralID: "referral-dismissed",
          rawText: "not yet reviewed",
          provenance: FindProvenance()
        )
      )
      await coordinator.declineReferral(.duplicate)

      #expect(await recorder.verdicts == [.declined(referralID: "referral-dismissed", .duplicate)])
      #expect(coordinator.referralID == nil)
    }
  }

  @Test
  func shortcutTextSeedsAndExtractsAnEmptySessionWithoutSaving() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .init { _ in
        RecipeExtraction(title: "Shortcut Lentils", ingredientSections: [.init(lines: ["1 cup lentils"])])
      }
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      let text = "1 cup lentils"

      coordinator.stage(text: text)
      await coordinator.applyStagedText(to: model)

      #expect(model.sources.count == 1)
      #expect(model.sources.first?.kind == .pastedText)
      #expect(model.sources.first?.content == text)
      #expect(model.editorModel.draft.title == "Shortcut Lentils")
      #expect(coordinator.stagedText == nil)
      let recipeCount = try await database.read { db in try Recipe.fetchAll(db).count }
      #expect(recipeCount == 0)
    }
  }

  @Test
  func shortcutTextPreservesFencedMarkerVerbatim() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .init { _ in
        RecipeExtraction(title: "Marked Recipe")
      }
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      let text = """
      ```json
      YC-HANDOFF: future-marker
      {\"@type\":\"Recipe\"}
      ```
      """

      coordinator.stage(text: text)
      await coordinator.applyStagedText(to: model)

      #expect(model.sources.first?.content == text)
    }
  }

  @Test
  func shortcutTextDoesNotClobberANonEmptySession() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      let existingText = "Existing family recipe notes"
      let incomingText = "New shortcut recipe"
      model.composeText = existingText
      model.composeTextChanged()
      model.editorModel.draft.title = "Existing Draft"

      coordinator.stage(text: incomingText)
      await coordinator.applyStagedText(to: model)

      #expect(model.composeText == existingText)
      #expect(model.editorModel.draft.title == "Existing Draft")
      expectNoDifference(model.sources.map(\.content), [existingText])
      expectNoDifference(model.destination, .incomingPastedTextOffer(.init(content: incomingText)))

      model.acceptIncomingPastedText(incomingText)

      #expect(model.composeText == incomingText)
      #expect(model.editorModel.draft.title == "Existing Draft")
      expectNoDifference(model.sources.map(\.content), [existingText, incomingText])
      #expect(model.sources.last?.kind == .pastedText)
      #expect(model.destination == nil)
    }
  }

  @Test
  func shortcutJSONLDUsesTheDeterministicTierWithoutAModelCall() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .testValue
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      let text = """
      ```json
      {"@context":"https://schema.org","@type":"Recipe","name":"Shortcut Broth","recipeIngredient":["1 onion"],"recipeInstructions":["Simmer."]}
      ```
      """

      coordinator.stage(text: text)
      await coordinator.applyStagedText(to: model)

      #expect(model.editorModel.draft.title == "Shortcut Broth")
      #expect(model.extractionError == nil)
    }
  }

  @Test
  func shortcutNonRecipeTextStaysTransientWhenExtractionFails() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .testValue
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      let text = "a reminder to buy lemons"

      coordinator.stage(text: text)
      await coordinator.applyStagedText(to: model)

      #expect(model.sources.first?.content == text)
      #expect(model.extractionError != nil)
      let recipeCount = try await database.read { db in try Recipe.fetchAll(db).count }
      #expect(recipeCount == 0)
    }
  }

  @Test
  func typedMaterialIsRecordedBeforeAFailedExtraction() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .testValue
    } operation: {
      let model = CreateRecipeModel()
      model.composeText = "1 cup lentils"

      await model.extractButtonTapped()

      expectNoDifference(model.sources.count, 1)
      expectNoDifference(model.sources.first?.kind, .typedText)
      expectNoDifference(model.sources.first?.content, "1 cup lentils")
      #expect(model.composeText == "1 cup lentils")
      #expect(model.extractionError != nil)
    }
  }

  @Test
  func pastedMaterialKeepsItsDistinctSourceKind() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      let model = CreateRecipeModel()

      model.pastedTextReceived(["1 cup lentils"])

      expectNoDifference(model.sources.count, 1)
      expectNoDifference(model.sources.first?.kind, .pastedText)
      expectNoDifference(model.sources.first?.content, "1 cup lentils")
      #expect(model.composeText == "1 cup lentils")
    }
  }

  @Test
  func extractedMaterialRemainsVisibleForReview() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .init { _ in
        RecipeExtraction(title: "Lentils", ingredientSections: [.init(lines: ["1 cup lentils"])])
      }
    } operation: {
      let model = CreateRecipeModel()
      model.pastedTextReceived(["1 cup lentils"])

      await model.extractButtonTapped()

      #expect(model.composeText == "1 cup lentils")
      expectNoDifference(model.sources.first?.kind, .pastedText)
      expectNoDifference(model.sources.first?.content, "1 cup lentils")
    }
  }

  @Test
  func correctionAfterAnExtractionKeepsTheOriginalSource() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.recipeExtractionClient = .init { _ in
        RecipeExtraction(title: "Lentils", ingredientSections: [.init(lines: ["1 cup lentils"])])
      }
    } operation: {
      let model = CreateRecipeModel()
      model.pastedTextReceived(["1 cup lentils"])
      await model.extractButtonTapped()

      model.composeText = "1 cup lentils\n1 onion"
      model.composeTextChanged()

      expectNoDifference(model.sources.map(\.content), ["1 cup lentils", "1 cup lentils\n1 onion"])
      expectNoDifference(model.sources.map(\.kind), [.pastedText, .typedText])
    }
  }
}

private actor AppFindReturnRecorder {
  private(set) var verdicts: [FindVerdict] = []

  func record(_ verdict: FindVerdict) {
    verdicts.append(verdict)
  }
}
