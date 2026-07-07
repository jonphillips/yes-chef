import Foundation
import SQLiteData

public struct GroceryIngredientChoice: Identifiable, Equatable, Sendable {
  public var recipe: Recipe
  public var section: IngredientSection
  public var line: IngredientLine

  public init(recipe: Recipe, section: IngredientSection, line: IngredientLine) {
    self.recipe = recipe
    self.section = section
    self.line = line
  }

  public var id: IngredientLine.ID { line.id }

  public var isAssumedPantryStaple: Bool {
    GroceryPantryAssumptions.isPantryStaple(line)
  }

  public func isAssumedPantryStaple(pantryStaples: [String]) -> Bool {
    GroceryPantryAssumptions.isPantryStaple(line, pantryStaples: pantryStaples)
  }
}

public struct GroceryIngredientChoiceRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [GroceryIngredientChoice] {
    var choices: [GroceryIngredientChoice] = []
    for recipe in try Recipe.fetchAll(db) {
      guard let folded = try RecipeRepository.fetchDetailApplyingActiveVariation(recipeID: recipe.id, in: db)
      else { continue }
      let sectionsByID = Dictionary(uniqueKeysWithValues: folded.detail.ingredientSections.map { ($0.id, $0) })
      choices += folded.detail.ingredientLines
        .filter(\.isShoppableForGroceries)
        .compactMap { line in
          guard let section = sectionsByID[line.sectionID] else { return nil }
          return GroceryIngredientChoice(recipe: folded.detail.recipe, section: section, line: line)
        }
    }
    return choices.sorted(by: areGroceryIngredientChoicesInIncreasingOrder)
  }
}

private func areGroceryIngredientChoicesInIncreasingOrder(
  _ lhs: GroceryIngredientChoice,
  _ rhs: GroceryIngredientChoice
) -> Bool {
  let recipeComparison = lhs.recipe.title.localizedStandardCompare(rhs.recipe.title)
  if recipeComparison != .orderedSame {
    return recipeComparison == .orderedAscending
  }
  if lhs.section.sortOrder != rhs.section.sortOrder {
    return lhs.section.sortOrder < rhs.section.sortOrder
  }
  if lhs.line.sortOrder != rhs.line.sortOrder {
    return lhs.line.sortOrder < rhs.line.sortOrder
  }
  return lhs.line.id.uuidString < rhs.line.id.uuidString
}
