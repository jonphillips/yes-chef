import Foundation

public enum RecipeContractStagingError: Error, Equatable, LocalizedError, Sendable {
  case notJSON
  case noRecipeNode
  case missingIngredientsOrInstructions

  public var errorDescription: String? {
    switch self {
    case .notJSON:
      "The recipe must be a JSON-LD object."
    case .noRecipeNode:
      "The JSON-LD object has no schema.org Recipe node."
    case .missingIngredientsOrInstructions:
      "The recipe needs both ingredients and instructions."
    }
  }
}

/// Deterministic, lossless-or-loud validation for recipes staged by the local helper.
public enum RecipeContractStaging {
  public static func validate(_ jsonLDText: String) throws -> RecipeExtraction {
    var builder = RecipeParseBuilder(sourceURL: nil, originalHTML: "")
    let result = RecipeJSONLDExtractor.extract(fromJSONLD: jsonLDText, into: &builder)
    switch result {
    case .notJSON:
      throw RecipeContractStagingError.notJSON
    case .noRecipeNode:
      throw RecipeContractStagingError.noRecipeNode
    case .incompleteRecipe:
      throw RecipeContractStagingError.missingIngredientsOrInstructions
    case .extracted:
      break
    }

    let page = builder.build(capturedAt: Date(timeIntervalSince1970: 0))
    guard !page.ingredientSections.allSatisfy(\.lines.isEmpty),
      !page.instructionSections.allSatisfy(\.steps.isEmpty)
    else {
      throw RecipeContractStagingError.missingIngredientsOrInstructions
    }
    return RecipeExtraction(page: page).cleaned
  }
}
