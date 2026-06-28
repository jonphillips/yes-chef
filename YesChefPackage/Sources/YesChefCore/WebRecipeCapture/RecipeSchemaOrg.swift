import Foundation

enum RecipeSchemaOrg {
  static let recipeTypes: Set<String> = ["Recipe"]

  static let scalarProperties: [String: RecipePageAttribute] = [
    "name": .title,
    "description": .summary,
    "author": .author,
    "publisher": .publisherName,
    "url": .sourceURL,
    "recipeYield": .servingsText,
    "prepTime": .prepTime,
    "cookTime": .cookTime,
    "totalTime": .totalTime,
    "aggregateRating": .rating,
  ]
}
