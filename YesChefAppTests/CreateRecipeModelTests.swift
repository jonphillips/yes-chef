import CustomDump
import Dependencies
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct CreateRecipeModelTests {
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
