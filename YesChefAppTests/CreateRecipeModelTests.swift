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
  func shortcutIntentStagesTextOnly() async throws {
    var coordinator: CreateRecipeCoordinator?
    try await withDependencies {
      $0.uuid = .incrementing
      coordinator = CreateRecipeCoordinator()
      $0.createRecipeCoordinator = coordinator!
    } operation: {
      let coordinator = coordinator!
      _ = try await CaptureRecipeFromText(rawText: "Newsletter chrome\nRecipe body\nFooter").perform()

      #expect(coordinator.stagedText?.text == "Newsletter chrome\nRecipe body\nFooter")
      #expect(coordinator.referralID == nil)
      #expect(coordinator.stagedText?.referral == nil)
    }
  }

  @Test
  func referralSaveEmitsAnAdmittedVerdictWithoutPersistingReferralMetadata() async throws {
    let recorder = AppFindReturnRecorder()
    let suiteName = "FindReferralSingleSave-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
      let coordinator = CreateRecipeCoordinator(defaults: defaults)
      let model = CreateRecipeModel()
      await coordinator.stage(referral: referral)
      await coordinator.applyStagedText(to: model)

      guard case let .saved(recipeID, true) = await coordinator.saveButtonTapped(for: model) else {
        Issue.record("Expected the single recipe save to complete the session")
        return
      }
      let verdicts = await recorder.verdicts

      #expect(verdicts == [FindVerdict(referralID: "referral-save", outcomes: [.admitted(FindRecipeRef(recipeID))])])
      #expect(coordinator.referralID == nil)
      #expect(model.referralProvenance?.contentPieceToken == "cockpit-token")
    }
  }

  @Test
  func savingEveryCandidateEmitsOneVerdictWithEveryAdmittedRecipe() async throws {
    let recorder = AppFindReturnRecorder()
    let suiteName = "FindReferralMultiSave-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let referral = FindReferral(referralID: "referral-multi-save", rawText: "Two recipes", provenance: FindProvenance())

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_001)
      $0.recipeExtractionClient = RecipeExtractionClient(
        extract: { _ in RecipeExtraction(title: "unused") },
        extractMany: { _ in [
          RecipeExtraction(title: "Green Beans", ingredientSections: [.init(lines: ["1 cup beans"]) ]),
          RecipeExtraction(title: "Roast Carrots", ingredientSections: [.init(lines: ["2 carrots"]) ]),
        ] }
      )
      $0.findReturnEmitter = FindReturnEmitter { await recorder.record($0) }
    } operation: {
      let coordinator = CreateRecipeCoordinator(defaults: defaults)
      let model = CreateRecipeModel()
      await coordinator.stage(referral: referral)
      await coordinator.applyStagedText(to: model)
      let first = try #require(model.extractionCandidates.first)
      model.selectExtraction(id: first.id)

      guard case let .saved(firstID, firstComplete) = await coordinator.saveButtonTapped(for: model) else {
        Issue.record("Expected first candidate to save")
        return
      }
      #expect(!firstComplete)
      #expect(await recorder.verdicts.isEmpty)
      #expect(model.savedExtractionIDs == [first.id])
      #expect(model.editorModel.draft.title == "Roast Carrots")
      #expect(model.selectedExtractionID == model.extractionCandidates.last?.id)

      guard case let .saved(secondID, secondComplete) = await coordinator.saveButtonTapped(for: model) else {
        Issue.record("Expected second candidate to save")
        return
      }
      #expect(secondComplete)
      let expected = FindVerdict(
        referralID: referral.referralID,
        outcomes: [.admitted(FindRecipeRef(firstID)), .admitted(FindRecipeRef(secondID))]
      )
      #expect(await recorder.verdicts == [expected])
      #expect(coordinator.referralID == nil)
    }
  }

  @Test
  func savedCandidateCannotBeSelectedOrSavedAgain() async throws {
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_002)
      $0.recipeExtractionClient = RecipeExtractionClient(
        extract: { _ in RecipeExtraction(title: "unused") },
        extractMany: { _ in [RecipeExtraction(title: "One"), RecipeExtraction(title: "Two")] }
      )
    } operation: {
      let model = CreateRecipeModel()
      model.pastedTextReceived(["two recipes"])
      await model.extractButtonTapped()
      let first = try #require(model.extractionCandidates.first)
      model.selectExtraction(id: first.id)
      _ = try #require(await model.saveButtonTapped())

      #expect(model.isSavingDisabled == false)
      let currentTitle = model.editorModel.draft.title
      model.selectExtraction(id: first.id)
      #expect(model.editorModel.draft.title == currentTitle)
      #expect(model.selectedExtractionID == model.extractionCandidates.last?.id)
      #expect(model.savedExtractionIDs.contains(first.id))
    }
  }

  @Test
  func relaunchReconcilesThePersistedAdmittedSetInsteadOfDismissal() async throws {
    let suiteName = "FindReferralMultiSave-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let recorder = AppFindReturnRecorder()
    let referral = FindReferral(referralID: "referral-relaunch-multi", rawText: "Two recipes", provenance: FindProvenance())

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_003)
      $0.recipeExtractionClient = RecipeExtractionClient(
        extract: { _ in RecipeExtraction(title: "unused") },
        extractMany: { _ in [RecipeExtraction(title: "First"), RecipeExtraction(title: "Second")] }
      )
      $0.findReturnEmitter = FindReturnEmitter { await recorder.record($0) }
    } operation: {
      let coordinator = CreateRecipeCoordinator(defaults: defaults)
      let model = CreateRecipeModel()
      await coordinator.stage(referral: referral)
      await coordinator.applyStagedText(to: model)
      let first = try #require(model.extractionCandidates.first)
      model.selectExtraction(id: first.id)
      guard case let .saved(recipeID, _) = await coordinator.saveButtonTapped(for: model) else {
        Issue.record("Expected the first candidate to save")
        return
      }

      #expect(await recorder.verdicts.isEmpty)
      #expect(defaults.stringArray(forKey: CreateRecipeCoordinator.admittedReferralRecipeIDsDefaultsKey) == [recipeID.uuidString])

      let relaunchedCoordinator = CreateRecipeCoordinator(defaults: defaults)
      await relaunchedCoordinator.reconcilePersistedReferralAfterLaunch()

      #expect(await recorder.verdicts == [FindVerdict(
        referralID: referral.referralID,
        outcomes: [.admitted(FindRecipeRef(recipeID))]
      )])
      #expect(defaults.string(forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey) == nil)
      #expect(defaults.object(forKey: CreateRecipeCoordinator.admittedReferralRecipeIDsDefaultsKey) == nil)
    }
  }

  @Test
  func partialReferralCanCloseThroughDoneClearLeavingOrSupersedingIntake() async throws {
    let recorder = AppFindReturnRecorder()
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_004)
      $0.recipeExtractionClient = RecipeExtractionClient(
        extract: { _ in RecipeExtraction(title: "unused") },
        extractMany: { _ in [RecipeExtraction(title: "First"), RecipeExtraction(title: "Second")] }
      )
      $0.findReturnEmitter = FindReturnEmitter { await recorder.record($0) }
    } operation: {
      for closeStyle in ["done", "clear", "leave", "supersede"] {
        let suiteName = "FindReferralClose-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let coordinator = CreateRecipeCoordinator(defaults: defaults)
        let model = CreateRecipeModel()
        let referralID = "referral-\(closeStyle)"
        await coordinator.stage(referral: FindReferral(
          referralID: referralID,
          rawText: "Two recipes",
          provenance: FindProvenance()
        ))
        await coordinator.applyStagedText(to: model)
        let first = try #require(model.extractionCandidates.first)
        model.selectExtraction(id: first.id)
        guard case .saved(_, false) = await coordinator.saveButtonTapped(for: model) else {
          Issue.record("Expected the first candidate to save")
          return
        }

        switch closeStyle {
        case "done", "clear":
          await coordinator.declineReferral()
        case "leave":
          await coordinator.abandonOutstandingReferral()
        default:
          await coordinator.stage(referral: FindReferral(
            referralID: "replacement-\(referralID)",
            rawText: "Replacement",
            provenance: FindProvenance()
          ))
        }

        let verdict = try #require(await recorder.verdicts.last)
        #expect(verdict.referralID == referralID)
        #expect(verdict.admitted.count == 1)
        #expect(verdict.outcomes.allSatisfy { if case .admitted = $0 { true } else { false } })
        defaults.removePersistentDomain(forName: suiteName)
      }
      #expect(await recorder.verdicts.count == 4)
    }
  }

  @Test
  func referralDismissalEmitsAFirstClassDecline() async throws {
    let recorder = AppFindReturnRecorder()
    let suiteName = "FindReferralDismissal-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { verdict in
        await recorder.record(verdict)
      }
    } operation: {
      let coordinator = CreateRecipeCoordinator(defaults: defaults)
      await coordinator.stage(
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
  func stalePersistedReferralIsDismissedAndNewReferralStillStages() async throws {
    let suiteName = "FindReferralTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("referral-crashed", forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey)
    let recorder = AppFindReturnRecorder()

    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { verdict in await recorder.record(verdict) }
    } operation: {
      let coordinator = CreateRecipeCoordinator(defaults: defaults)
      let staged = await coordinator.stage(
        referral: FindReferral(referralID: "referral-new", rawText: "new recipe", provenance: FindProvenance())
      )

      #expect(staged)
      #expect(coordinator.referralID == "referral-new")
      #expect(coordinator.stagedText?.text == "new recipe")
      #expect(defaults.string(forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey) == "referral-new")
    }

    #expect(await recorder.verdicts == [.declined(referralID: "referral-crashed", .dismissed)])
  }

  @Test
  func staleReferralWriteFailurePreservesOutstandingStateAndDefersNewReferral() async throws {
    let suiteName = "FindReferralTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("referral-unwritable", forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey)
    defaults.set([UUID().uuidString], forKey: CreateRecipeCoordinator.admittedReferralRecipeIDsDefaultsKey)
    let admittedIDs = defaults.stringArray(forKey: CreateRecipeCoordinator.admittedReferralRecipeIDsDefaultsKey)

    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { _ in throw FindReturnWriteError.failed }
    } operation: {
      let coordinator = CreateRecipeCoordinator(defaults: defaults)
      let staged = await coordinator.stage(
        referral: FindReferral(referralID: "referral-after-failure", rawText: "new recipe", provenance: FindProvenance())
      )

      #expect(!staged)
      #expect(coordinator.referralID == nil)
      #expect(coordinator.stagedText == nil)
      #expect(defaults.string(forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey) == "referral-unwritable")
      #expect(defaults.stringArray(forKey: CreateRecipeCoordinator.admittedReferralRecipeIDsDefaultsKey) == admittedIDs)
    }
  }

  @Test
  func abandonedReferralEmitsExactlyOneDismissalAndSupersessionDoesNotStrandIt() async {
    let recorder = AppFindReturnRecorder()

    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { verdict in
        await recorder.record(verdict)
      }
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      await coordinator.stage(
        referral: FindReferral(
          referralID: "referral-abandoned",
          rawText: "recipe text",
          provenance: FindProvenance()
        )
      )
      await coordinator.stage(text: "ordinary text replaces the referral")
      await coordinator.abandonOutstandingReferral()

      #expect(await recorder.verdicts == [.declined(referralID: "referral-abandoned", .dismissed)])
      #expect(coordinator.referralID == nil)
    }
  }

  @Test
  func mailboxReceivePersistsBeforeDeletingAndRelaunchRetriesDismissal() async throws {
    let suiteName = "FindReferralTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let mailbox = FindReferralMailbox(rootURL: root)
    let referral = FindReferral(referralID: "ref-relaunch", rawText: "recipe", provenance: FindProvenance())
    let referralURL = root.appendingPathComponent("find-referrals", isDirectory: true).appendingPathComponent("ref-relaunch.json")
    try FileManager.default.createDirectory(at: referralURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(referral).write(to: referralURL)

    let recorder = AppFindReturnRecorder()
    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { verdict in await recorder.record(verdict) }
    } operation: {
      let receivingCoordinator = CreateRecipeCoordinator(defaults: defaults)
      let didReceive: Bool
      do {
        didReceive = try await receivingCoordinator.receiveReferral(id: referral.referralID, from: mailbox)
      } catch {
        Issue.record(error)
        return
      }
      #expect(didReceive)
      #expect(defaults.string(forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey) == referral.referralID)
      #expect(!FileManager.default.fileExists(atPath: referralURL.path))
    }

    await withDependencies {
      $0.uuid = .incrementing
      $0.findReturnEmitter = FindReturnEmitter { verdict in await recorder.record(verdict) }
    } operation: {
      let relaunchedCoordinator = CreateRecipeCoordinator(defaults: defaults)
      await relaunchedCoordinator.reconcilePersistedReferralAfterLaunch()
    }

    #expect(await recorder.verdicts == [.declined(referralID: "ref-relaunch", .dismissed)])
    #expect(defaults.string(forKey: CreateRecipeCoordinator.outstandingReferralDefaultsKey) == nil)
  }

  @Test
  func acceptedReferralOfferWithNoRecipeEmitsADecline() async throws {
    let recorder = AppFindReturnRecorder()

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_004)
      $0.recipeExtractionClient = RecipeExtractionClient(
        extract: { _ in RecipeExtraction(title: "unused") },
        extractMany: { _ in [] }
      )
      $0.findReturnEmitter = FindReturnEmitter { verdict in
        await recorder.record(verdict)
      }
    } operation: {
      let coordinator = CreateRecipeCoordinator()
      let model = CreateRecipeModel()
      model.composeText = "Existing recipe draft"
      model.composeTextChanged()

      await coordinator.stage(
        referral: FindReferral(
          referralID: "referral-offer-no-recipe",
          rawText: "newsletter with no complete recipe",
          provenance: FindProvenance()
        )
      )
      await coordinator.applyStagedText(to: model)
      model.acceptIncomingPastedText("newsletter with no complete recipe")
      await coordinator.extractButtonTapped(for: model)

      #expect(await recorder.verdicts == [.declined(referralID: "referral-offer-no-recipe", .noRecipeFound)])
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

      await coordinator.stage(text: text)
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

      await coordinator.stage(text: text)
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

      await coordinator.stage(text: incomingText)
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

      await coordinator.stage(text: text)
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

      await coordinator.stage(text: text)
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

private enum FindReturnWriteError: Error {
  case failed
}
