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
    let sourcesByRecipe = Dictionary(uniqueKeysWithValues: sources.map { ($0.recipeID, $0) })
    return assemble(recipesToBuild: recipes.filter { !$0.archived }, targets: recipes.map { recipe in
        .init(recipeID: recipe.id, title: recipe.title, sourceURL: sourcesByRecipe[recipe.id]?.url)
      }, sources: sources,
      ingredientSections: ingredientSections, ingredientLines: ingredientLines,
      instructionSections: instructionSections, instructionSteps: instructionSteps,
      notes: notes, photos: photos, categories: categories, facets: facets, joins: joins,
      serves: serves, related: related, variations: variations)
  }

  private static func assemble(
    recipesToBuild: [Recipe], targets: [RecipeBundleCoding.LinkTarget], sources: [RecipeSource],
    ingredientSections: [IngredientSection], ingredientLines: [IngredientLine],
    instructionSections: [InstructionSection], instructionSteps: [InstructionStep],
    notes: [RecipeNote], photos: [RecipePhoto], categories: [Category], facets: [Facet],
    joins: [RecipeCategory], serves: [RecipeServeWith], related: [RecipeRelatedRecipe],
    variations: [RecipeVariation]
  ) -> [RecipeBundleCoding.RecipeBundle] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let facetsByID = Dictionary(uniqueKeysWithValues: facets.map { ($0.id, $0) })
    let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.recipeID, $0) })
    let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.recipeID, $0) })
    let ingredientSectionsByRecipeID = Dictionary(grouping: ingredientSections, by: \.recipeID)
    let ingredientLinesByRecipeID = Dictionary(grouping: ingredientLines, by: \.recipeID)
    let instructionSectionsByRecipeID = Dictionary(grouping: instructionSections, by: \.recipeID)
    let instructionStepsByRecipeID = Dictionary(grouping: instructionSteps, by: \.recipeID)
    let notesByRecipeID = Dictionary(grouping: notes, by: \.recipeID)
    let photosByRecipeID = Dictionary(grouping: photos, by: \.recipeID)
    let joinsByRecipeID = Dictionary(grouping: joins, by: \.recipeID)
    let servesByRecipeID = Dictionary(grouping: serves, by: \.recipeID)
    let variationsByRecipeID = Dictionary(grouping: variations, by: \.recipeID)
    var relatedByRecipeID: [Recipe.ID: [RecipeRelatedRecipe]] = [:]
    for pair in related {
      relatedByRecipeID[pair.recipeID, default: []].append(pair)
      if pair.relatedRecipeID != pair.recipeID { relatedByRecipeID[pair.relatedRecipeID, default: []].append(pair) }
    }
    return recipesToBuild.sorted { $0.id.uuidString < $1.id.uuidString }.map { recipe in
      let id = recipe.id
      let ownCategories = joinsByRecipeID[id, default: []].compactMap { categoriesByID[$0.categoryID] }
      let labels = ownCategories.map { category in
        RecipeBundleCoding.LabelPath(
          facet: category.facetID.flatMap { facetsByID[$0]?.name },
          path: CategoryHierarchy.pathComponents(for: category, categoriesByID: categoriesByID)
        )
      }
      let ownServes = servesByRecipeID[id, default: []]
      let ownRelated = relatedByRecipeID[id, default: []]
      let targetIDs = Set(ownServes.compactMap(\.linkedRecipeID) + ownRelated.map { $0.recipeID == id ? $0.relatedRecipeID : $0.recipeID })
      let targets = targetIDs.compactMap { targetID -> RecipeBundleCoding.LinkTarget? in
        targetsByID[targetID]
      }
      return RecipeBundleCoding.RecipeBundle(
        version: RecipeBundleCoding.currentVersion, recipe: recipe, source: sourcesByID[id],
        ingredientSections: ingredientSectionsByRecipeID[id, default: []],
        ingredientLines: ingredientLinesByRecipeID[id, default: []],
        instructionSections: instructionSectionsByRecipeID[id, default: []],
        instructionSteps: instructionStepsByRecipeID[id, default: []],
        recipeNotes: notesByRecipeID[id, default: []],
        photos: photosByRecipeID[id, default: []].map { photo in
          var photo = photo
          photo.displayData = nil
          return photo
        },
        categoryNames: ownCategories.map(\.name).sorted(), labels: labels,
        serveWith: ownServes, relatedRecipes: ownRelated,
        variations: variationsByRecipeID[id, default: []], linkTargets: targets
      )
    }
  }

  public static func bundle(for id: Recipe.ID, in db: Database) throws -> RecipeBundleCoding.RecipeBundle? {
    guard let recipe = try Recipe.find(id).fetchOne(db), !recipe.archived else { return nil }
    let joins = try RecipeCategory.where { $0.recipeID.eq(id) }.fetchAll(db)
    var categories: [Category] = []
    var categoryIDs = Set<Category.ID>()
    for join in joins {
      var currentID: Category.ID? = join.categoryID
      while let categoryID = currentID, categoryIDs.insert(categoryID).inserted,
        let category = try Category.find(categoryID).fetchOne(db)
      {
        categories.append(category)
        currentID = category.parentCategoryID
      }
    }
    let facetIDs = Set(categories.compactMap(\.facetID))
    let facets = try facetIDs.compactMap { try Facet.find($0).fetchOne(db) }
    let serves = try RecipeServeWith.where { $0.recipeID.eq(id) }.fetchAll(db)
    let related = try RecipeRelatedRecipe.where { $0.recipeID.eq(id) || $0.relatedRecipeID.eq(id) }.fetchAll(db)
    let targetIDs = Set(serves.compactMap(\.linkedRecipeID) + related.map { $0.recipeID == id ? $0.relatedRecipeID : $0.recipeID })
    let sources = try (targetIDs.union([id])).compactMap { targetID in
      try RecipeSource.where { $0.recipeID.eq(targetID) }.fetchOne(db)
    }
    let sourceByRecipe = Dictionary(uniqueKeysWithValues: sources.map { ($0.recipeID, $0) })
    let targets = try targetIDs.compactMap { targetID -> RecipeBundleCoding.LinkTarget? in
      guard let title = try Recipe.find(targetID).select(\.title).fetchOne(db) else { return nil }
      return .init(recipeID: targetID, title: title, sourceURL: sourceByRecipe[targetID]?.url)
    }
    return try assemble(
      recipesToBuild: [recipe], targets: targets, sources: sources,
      ingredientSections: IngredientSection.where { $0.recipeID.eq(id) }.fetchAll(db),
      ingredientLines: IngredientLine.where { $0.recipeID.eq(id) }.fetchAll(db),
      instructionSections: InstructionSection.where { $0.recipeID.eq(id) }.fetchAll(db),
      instructionSteps: InstructionStep.where { $0.recipeID.eq(id) }.fetchAll(db),
      notes: RecipeNote.where { $0.recipeID.eq(id) }.fetchAll(db),
      photos: RecipePhoto.where { $0.recipeID.eq(id) }.fetchAll(db),
      categories: categories, facets: facets, joins: joins, serves: serves, related: related,
      variations: RecipeVariation.where { $0.recipeID.eq(id) }.fetchAll(db)
    ).first
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
