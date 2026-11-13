import CryptoKit
import Foundation
import SQLiteData

/// Intentionally omits full-size display images; those travel as separate assets.
public enum CookbookPayload {
  public static func bundles(in db: Database) throws -> [RecipeBundleCoding.RecipeBundle] {
    let recipes = try Recipe.fetchAll(db)
    let sources = try RecipeSource.fetchAll(db)
    let ingredientSections = try IngredientSection.fetchAll(db)
    let ingredientLines = try IngredientLine.fetchAll(db)
    let instructionSections = try InstructionSection.fetchAll(db)
    let instructionSteps = try InstructionStep.fetchAll(db)
    let notes = try RecipeNote.fetchAll(db)
    let photos = try RecipePhoto.fetchAll(db)
    let categories = try Category.fetchAll(db)
    let facets = try Facet.fetchAll(db)
    let joins = try RecipeCategory.fetchAll(db)
    let serves = try RecipeServeWith.fetchAll(db)
    let related = try RecipeRelatedRecipe.fetchAll(db)
    let variations = try RecipeVariation.fetchAll(db)
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let facetsByID = Dictionary(uniqueKeysWithValues: facets.map { ($0.id, $0) })
    let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.recipeID, $0) })
    return recipes.filter { !$0.archived }.sorted { $0.id.uuidString < $1.id.uuidString }.map { recipe in
      let id = recipe.id
      let ownCategories = joins.filter { $0.recipeID == id }.compactMap { categoriesByID[$0.categoryID] }
      let labels = ownCategories.map { category in
        RecipeBundleCoding.LabelPath(
          facet: category.facetID.flatMap { facetsByID[$0]?.name },
          path: CategoryHierarchy.pathComponents(for: category, categoriesByID: categoriesByID)
        )
      }
      let ownServes = serves.filter { $0.recipeID == id }
      let ownRelated = related.filter { $0.recipeID == id || $0.relatedRecipeID == id }
      let targetIDs = Set(ownServes.compactMap(\.linkedRecipeID) + ownRelated.map { $0.recipeID == id ? $0.relatedRecipeID : $0.recipeID })
      let targets = targetIDs.compactMap { targetID -> RecipeBundleCoding.LinkTarget? in
        guard let target = recipesByID[targetID] else { return nil }
        return .init(recipeID: targetID, title: target.title, sourceURL: sourcesByID[targetID]?.url)
      }
      return RecipeBundleCoding.RecipeBundle(
        version: RecipeBundleCoding.currentVersion, recipe: recipe, source: sourcesByID[id],
        ingredientSections: ingredientSections.filter { $0.recipeID == id },
        ingredientLines: ingredientLines.filter { $0.recipeID == id },
        instructionSections: instructionSections.filter { $0.recipeID == id },
        instructionSteps: instructionSteps.filter { $0.recipeID == id },
        recipeNotes: notes.filter { $0.recipeID == id },
        photos: photos.filter { $0.recipeID == id }.map { photo in
          var photo = photo
          photo.displayData = nil
          return photo
        },
        categoryNames: ownCategories.map(\.name).sorted(), labels: labels,
        serveWith: ownServes, relatedRecipes: ownRelated,
        variations: variations.filter { $0.recipeID == id }, linkTargets: targets
      )
    }
  }

  public static func encodedPayload(_ bundle: RecipeBundleCoding.RecipeBundle) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    func sorted<T: Encodable>(_ values: [T]) throws -> [T] {
      try values.map { (try encoder.encode($0), $0) }
        .sorted { $0.0.lexicographicallyPrecedes($1.0) }.map(\.1)
    }
    var canonical = bundle
    canonical.ingredientSections = try sorted(bundle.ingredientSections)
    canonical.ingredientLines = try sorted(bundle.ingredientLines)
    canonical.instructionSections = try sorted(bundle.instructionSections)
    canonical.instructionSteps = try sorted(bundle.instructionSteps)
    canonical.recipeNotes = try sorted(bundle.recipeNotes)
    canonical.photos = try sorted(bundle.photos)
    canonical.tagNames = bundle.tagNames.sorted()
    canonical.categoryNames = bundle.categoryNames.sorted()
    canonical.labels = try sorted(bundle.labels)
    canonical.serveWith = try sorted(bundle.serveWith)
    canonical.relatedRecipes = try sorted(bundle.relatedRecipes)
    canonical.variations = try sorted(bundle.variations)
    canonical.linkTargets = try sorted(bundle.linkTargets)
    return try encoder.encode(canonical)
  }

  public static func contentHash(_ bundle: RecipeBundleCoding.RecipeBundle) throws -> String {
    try SHA256.hash(data: encodedPayload(bundle)).map { String(format: "%02x", $0) }.joined()
  }
}
