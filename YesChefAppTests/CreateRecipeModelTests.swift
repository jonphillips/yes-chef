import CustomDump
import Dependencies
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct CreateRecipeModelTests {
  @Test
  func typedMaterialIsRecordedBeforeAFailedExtraction() async {
    await withDependencies {
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
  func pastedMaterialKeepsItsDistinctSourceKind() {
    withDependencies {
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
