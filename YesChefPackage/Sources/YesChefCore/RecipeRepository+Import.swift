import Foundation
import SQLiteData

public enum RecipeImportOutcome: String, Equatable, Sendable {
  case imported
  case alreadyImported
}

public struct RecipeImportWarning: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case titleOnlyCollision
    case ambiguousImportIdentity
  }

  public var kind: Kind
  public var title: String
  public var message: String

  public init(kind: Kind, title: String, message: String) {
    self.kind = kind
    self.title = title
    self.message = message
  }
}

public struct RecipeImportBundleResult: Equatable, Sendable {
  public var recipeID: Recipe.ID
  public var title: String
  public var outcome: RecipeImportOutcome
  public var warnings: [RecipeImportWarning]

  public init(
    recipeID: Recipe.ID,
    title: String,
    outcome: RecipeImportOutcome,
    warnings: [RecipeImportWarning] = []
  ) {
    self.recipeID = recipeID
    self.title = title
    self.outcome = outcome
    self.warnings = warnings
  }
}

public struct RecipeImportBatchResult: Equatable, Sendable {
  public var results: [RecipeImportBundleResult]

  public init(results: [RecipeImportBundleResult]) {
    self.results = results
  }

  public var importedCount: Int {
    results.filter { $0.outcome == .imported }.count
  }

  public var alreadyImportedCount: Int {
    results.filter { $0.outcome == .alreadyImported }.count
  }

  public var importedIDs: [Recipe.ID] {
    results.filter { $0.outcome == .imported }.map(\.recipeID)
  }

  public var warnings: [RecipeImportWarning] {
    results.flatMap(\.warnings)
  }
}

public enum RecipeImportPreviewStatus: String, Equatable, Sendable {
  case new
  case alreadyImported
  case titleOnlyCollision
}

public struct RecipeImportPreviewResult: Identifiable, Equatable, Sendable {
  public var id: Recipe.ID { recipeID }
  public var recipeID: Recipe.ID
  public var title: String
  public var status: RecipeImportPreviewStatus
  public var warnings: [RecipeImportWarning]

  public init(
    recipeID: Recipe.ID,
    title: String,
    status: RecipeImportPreviewStatus,
    warnings: [RecipeImportWarning] = []
  ) {
    self.recipeID = recipeID
    self.title = title
    self.status = status
    self.warnings = warnings
  }
}

public struct RecipeImportBatchPreview: Equatable, Sendable {
  public var results: [RecipeImportPreviewResult]

  public init(results: [RecipeImportPreviewResult]) {
    self.results = results
  }

  public var newCount: Int {
    results.filter { $0.status == .new }.count
  }

  public var alreadyImportedCount: Int {
    results.filter { $0.status == .alreadyImported }.count
  }

  public var titleOnlyCollisionCount: Int {
    results.filter { $0.status == .titleOnlyCollision }.count
  }

  public var warnings: [RecipeImportWarning] {
    results.flatMap(\.warnings)
  }
}

public struct RecipeImportRollbackResult: Equatable, Sendable {
  public var recipes: Int
  public var recipeSources: Int
  public var recipeImportRefs: Int
  public var ingredientSections: Int
  public var ingredientLines: Int
  public var instructionSections: Int
  public var instructionSteps: Int
  public var recipeNotes: Int
  public var recipePhotos: Int
  public var tags: Int
  public var categories: Int
  public var equipment: Int
  public var recipeTags: Int
  public var recipeCategories: Int
  public var recipeEquipment: Int

  public init(
    recipes: Int = 0,
    recipeSources: Int = 0,
    recipeImportRefs: Int = 0,
    ingredientSections: Int = 0,
    ingredientLines: Int = 0,
    instructionSections: Int = 0,
    instructionSteps: Int = 0,
    recipeNotes: Int = 0,
    recipePhotos: Int = 0,
    tags: Int = 0,
    categories: Int = 0,
    equipment: Int = 0,
    recipeTags: Int = 0,
    recipeCategories: Int = 0,
    recipeEquipment: Int = 0
  ) {
    self.recipes = recipes
    self.recipeSources = recipeSources
    self.recipeImportRefs = recipeImportRefs
    self.ingredientSections = ingredientSections
    self.ingredientLines = ingredientLines
    self.instructionSections = instructionSections
    self.instructionSteps = instructionSteps
    self.recipeNotes = recipeNotes
    self.recipePhotos = recipePhotos
    self.tags = tags
    self.categories = categories
    self.equipment = equipment
    self.recipeTags = recipeTags
    self.recipeCategories = recipeCategories
    self.recipeEquipment = recipeEquipment
  }
}

extension RecipeRepository {
  public static func previewImportBundles(
    _ bundles: [RecipeBundleCoding.RecipeBundle],
    against importRefs: [RecipeImportRef]
  ) -> RecipeImportBatchPreview {
    let titleOnlyBatchCounts = titleOnlyBatchCounts(for: bundles)
    var simulatedImportRefs = importRefs
    var results: [RecipeImportPreviewResult] = []

    for bundle in bundles {
      let key = importIdentityKey(for: bundle)
      let titleOnlyBatchCount = key.isTitleOnly ? titleOnlyBatchCounts[key, default: 1] : 1
      let result = previewImportBundle(
        bundle,
        importRefs: simulatedImportRefs,
        titleOnlyBatchCount: titleOnlyBatchCount
      )
      results.append(result)

      if result.status != .alreadyImported {
        simulatedImportRefs.append(
          RecipeImportRef(
            id: bundle.recipe.id,
            recipeID: bundle.recipe.id,
            normalizedSourceURL: key.normalizedSourceURL,
            normalizedTitle: key.normalizedTitle,
            dateCreated: .distantPast
          )
        )
      }
    }

    return RecipeImportBatchPreview(results: results)
  }

  @discardableResult
  public static func importBundle(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeImportBundleResult {
    var importRefs = try RecipeImportRef.fetchAll(db)
    return try importBundle(
      bundle,
      in: db,
      now: now,
      uuid: uuid,
      importRefs: &importRefs,
      titleOnlyBatchCount: 1
    )
  }

  @discardableResult
  public static func importBundles(
    _ bundles: [RecipeBundleCoding.RecipeBundle],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeImportBatchResult {
    let titleOnlyBatchCounts = titleOnlyBatchCounts(for: bundles)
    var importRefs = try RecipeImportRef.fetchAll(db)
    var results: [RecipeImportBundleResult] = []

    for bundle in bundles {
      let key = importIdentityKey(for: bundle)
      let titleOnlyBatchCount = key.isTitleOnly ? titleOnlyBatchCounts[key, default: 1] : 1
      let result = try importBundle(
        bundle,
        in: db,
        now: now,
        uuid: uuid,
        importRefs: &importRefs,
        titleOnlyBatchCount: titleOnlyBatchCount
      )
      results.append(result)
    }

    return RecipeImportBatchResult(results: results)
  }

  @discardableResult
  public static func rollbackImportedRecipes(
    recipeIDs: [Recipe.ID],
    in db: Database
  ) throws -> RecipeImportRollbackResult {
    let recipeIDSet = Set(recipeIDs)
    guard !recipeIDSet.isEmpty else { return RecipeImportRollbackResult() }

    let recipes = try Recipe.fetchAll(db).filter { recipeIDSet.contains($0.id) }
    let existingRecipeIDs = Set(recipes.map(\.id))
    guard !existingRecipeIDs.isEmpty else { return RecipeImportRollbackResult() }

    let importRefs = try RecipeImportRef.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let importDates = Set(importRefs.map(\.dateCreated))
    let recipeSources = try RecipeSource.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let ingredientSections = try IngredientSection.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let ingredientLines = try IngredientLine.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let instructionSections = try InstructionSection.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let instructionSteps = try InstructionStep.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let recipeNotes = try RecipeNote.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let recipePhotos = try RecipePhoto.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let recipeTags = try RecipeTag.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let recipeCategories = try RecipeCategory.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let recipeEquipment = try RecipeEquipment.fetchAll(db)
      .filter { existingRecipeIDs.contains($0.recipeID) }
    let tagIDs = Set(recipeTags.map(\.tagID))
    let categoryIDs = Set(recipeCategories.map(\.categoryID))
    let linkedTags = try Tag.fetchAll(db).filter { tagIDs.contains($0.id) }
    let linkedCategories = try Category.fetchAll(db).filter { categoryIDs.contains($0.id) }

    for recipeID in existingRecipeIDs {
      try Recipe.find(recipeID).delete().execute(db)
    }

    var deletedTagCount = 0
    for tag in linkedTags where importDates.contains(tag.dateCreated) {
      let remainingLinks = try RecipeTag.fetchAll(db).filter { $0.tagID == tag.id }
      guard remainingLinks.isEmpty else { continue }
      try Tag.find(tag.id).delete().execute(db)
      deletedTagCount += 1
    }

    var deletedCategoryCount = 0
    for category in linkedCategories where importDates.contains(category.dateCreated) {
      let remainingLinks = try RecipeCategory.fetchAll(db).filter { $0.categoryID == category.id }
      guard remainingLinks.isEmpty else { continue }
      try Category.find(category.id).delete().execute(db)
      deletedCategoryCount += 1
    }

    return RecipeImportRollbackResult(
      recipes: recipes.count,
      recipeSources: recipeSources.count,
      recipeImportRefs: importRefs.count,
      ingredientSections: ingredientSections.count,
      ingredientLines: ingredientLines.count,
      instructionSections: instructionSections.count,
      instructionSteps: instructionSteps.count,
      recipeNotes: recipeNotes.count,
      recipePhotos: recipePhotos.count,
      tags: deletedTagCount,
      categories: deletedCategoryCount,
      // Equipment has no batch-provenance column. Preserve orphaned equipment until an
      // importer actually creates it and can prove which rows belong to an undo batch.
      equipment: 0,
      recipeTags: recipeTags.count,
      recipeCategories: recipeCategories.count,
      recipeEquipment: recipeEquipment.count
    )
  }

  private static func importBundle(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    importRefs: inout [RecipeImportRef],
    titleOnlyBatchCount: Int
  ) throws -> RecipeImportBundleResult {
    let key = importIdentityKey(for: bundle)
    let matchingRefs = try matchingImportRefs(for: key, in: db, importRefs: &importRefs)

    if key.isTitleOnly {
      if titleOnlyBatchCount > 1, matchingRefs.count == titleOnlyBatchCount {
        return RecipeImportBundleResult(
          recipeID: matchingRefs[0].recipeID,
          title: bundle.recipe.title,
          outcome: .alreadyImported
        )
      }
      if titleOnlyBatchCount == 1, matchingRefs.count == 1 {
        return RecipeImportBundleResult(
          recipeID: matchingRefs[0].recipeID,
          title: bundle.recipe.title,
          outcome: .alreadyImported
        )
      }

      let warnings = matchingRefs.isEmpty
        ? []
        : [titleOnlyCollisionWarning(title: bundle.recipe.title)]
      let recipeID = try insertImportedBundle(
        bundle,
        identityKey: key,
        in: db,
        now: now,
        uuid: uuid,
        importRefs: &importRefs
      )
      return RecipeImportBundleResult(
        recipeID: recipeID,
        title: bundle.recipe.title,
        outcome: .imported,
        warnings: warnings
      )
    }

    switch matchingRefs.count {
    case 1:
      return RecipeImportBundleResult(
        recipeID: matchingRefs[0].recipeID,
        title: bundle.recipe.title,
        outcome: .alreadyImported
      )
    case 0:
      let recipeID = try insertImportedBundle(
        bundle,
        identityKey: key,
        in: db,
        now: now,
        uuid: uuid,
        importRefs: &importRefs
      )
      return RecipeImportBundleResult(recipeID: recipeID, title: bundle.recipe.title, outcome: .imported)
    default:
      let recipeID = try insertImportedBundle(
        bundle,
        identityKey: key,
        in: db,
        now: now,
        uuid: uuid,
        importRefs: &importRefs
      )
      return RecipeImportBundleResult(
        recipeID: recipeID,
        title: bundle.recipe.title,
        outcome: .imported,
        warnings: [ambiguousImportIdentityWarning(title: bundle.recipe.title)]
      )
    }
  }

  private static func insertImportedBundle(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    identityKey: RecipeImportIdentityKey,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    importRefs: inout [RecipeImportRef]
  ) throws -> Recipe.ID {
    var recipe = bundle.recipe
    if recipe.originalSnapshot == nil {
      recipe.originalSnapshot = try RecipeBundleCoding.snapshotData(
        recipe: recipe,
        source: bundle.source,
        ingredientSections: bundle.ingredientSections,
        ingredientLines: bundle.ingredientLines,
        instructionSections: bundle.instructionSections,
        instructionSteps: bundle.instructionSteps,
        notes: bundle.recipeNotes,
        tagNames: bundle.tagNames,
        categoryNames: bundle.categoryNames,
        photos: bundle.photos,
        equipment: bundle.equipment,
        recipeEquipment: bundle.recipeEquipment
      )
    }

    try Recipe.upsert { recipe }.execute(db)
    try replaceSource(bundle.source, recipeID: recipe.id, in: db)

    for section in bundle.ingredientSections {
      try IngredientSection.upsert { section }.execute(db)
    }
    for line in bundle.ingredientLines {
      try IngredientLine.upsert { line }.execute(db)
    }
    for section in bundle.instructionSections {
      try InstructionSection.upsert { section }.execute(db)
    }
    for step in bundle.instructionSteps {
      try InstructionStep.upsert { step }.execute(db)
    }
    for note in bundle.recipeNotes {
      try RecipeNote.upsert { note }.execute(db)
    }
    for photo in bundle.photos {
      try RecipePhoto.upsert { photo }.execute(db)
    }
    for equipment in bundle.equipment {
      try Equipment.upsert { equipment }.execute(db)
    }
    for recipeEquipment in bundle.recipeEquipment {
      try RecipeEquipment.upsert { recipeEquipment }.execute(db)
    }

    try reconcileTags(bundle.tagNames, recipeID: recipe.id, in: db, now: now, uuid: uuid)
    try reconcileCategories(bundle.categoryNames, recipeID: recipe.id, in: db, now: now, uuid: uuid)

    let importRef = RecipeImportRef(
      id: uuid(),
      recipeID: recipe.id,
      normalizedSourceURL: identityKey.normalizedSourceURL,
      normalizedTitle: identityKey.normalizedTitle,
      dateCreated: now
    )
    try RecipeImportRef.upsert { importRef }.execute(db)
    importRefs.append(importRef)

    return recipe.id
  }

  private static func importIdentityKey(
    for bundle: RecipeBundleCoding.RecipeBundle
  ) -> RecipeImportIdentityKey {
    RecipeImportIdentityKey(sourceURL: bundle.source?.url, title: bundle.recipe.title)
  }

  private static func titleOnlyBatchCounts(
    for bundles: [RecipeBundleCoding.RecipeBundle]
  ) -> [RecipeImportIdentityKey: Int] {
    bundles
      .map { importIdentityKey(for: $0) }
      .filter(\.isTitleOnly)
      .reduce(into: [RecipeImportIdentityKey: Int]()) { counts, key in
        counts[key, default: 0] += 1
      }
  }

  private static func previewImportBundle(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    importRefs: [RecipeImportRef],
    titleOnlyBatchCount: Int
  ) -> RecipeImportPreviewResult {
    let key = importIdentityKey(for: bundle)
    let matchingRefs = matchingImportRefsForPreview(for: key, in: importRefs)

    if key.isTitleOnly {
      if titleOnlyBatchCount > 1, matchingRefs.count == titleOnlyBatchCount {
        return RecipeImportPreviewResult(
          recipeID: matchingRefs[0].recipeID,
          title: bundle.recipe.title,
          status: .alreadyImported
        )
      }
      if titleOnlyBatchCount == 1, matchingRefs.count == 1 {
        return RecipeImportPreviewResult(
          recipeID: matchingRefs[0].recipeID,
          title: bundle.recipe.title,
          status: .alreadyImported
        )
      }

      let warnings = matchingRefs.isEmpty
        ? []
        : [titleOnlyCollisionWarning(title: bundle.recipe.title)]
      return RecipeImportPreviewResult(
        recipeID: bundle.recipe.id,
        title: bundle.recipe.title,
        status: matchingRefs.isEmpty ? .new : .titleOnlyCollision,
        warnings: warnings
      )
    }

    switch matchingRefs.count {
    case 1:
      return RecipeImportPreviewResult(
        recipeID: matchingRefs[0].recipeID,
        title: bundle.recipe.title,
        status: .alreadyImported
      )
    case 0:
      return RecipeImportPreviewResult(recipeID: bundle.recipe.id, title: bundle.recipe.title, status: .new)
    default:
      return RecipeImportPreviewResult(
        recipeID: bundle.recipe.id,
        title: bundle.recipe.title,
        status: .new,
        warnings: [ambiguousImportIdentityWarning(title: bundle.recipe.title)]
      )
    }
  }

  private static func matchingImportRefs(
    for key: RecipeImportIdentityKey,
    in db: Database,
    importRefs: inout [RecipeImportRef]
  ) throws -> [RecipeImportRef] {
    let refs = rawMatchingImportRefs(for: key, in: importRefs)
    guard !key.isTitleOnly, refs.count > 1 else { return refs }

    let canonicalRef = refs[0]
    let duplicateRefs = Array(refs.dropFirst())
    try mergeDuplicateImportedRecipes(
      canonicalRecipeID: canonicalRef.recipeID,
      duplicateRecipeIDs: Set(duplicateRefs.map(\.recipeID)).subtracting([canonicalRef.recipeID]),
      in: db
    )
    for ref in duplicateRefs {
      try RecipeImportRef.find(ref.id).delete().execute(db)
    }

    let duplicateRefIDs = Set(duplicateRefs.map(\.id))
    importRefs.removeAll { duplicateRefIDs.contains($0.id) }
    return [canonicalRef]
  }

  private static func matchingImportRefsForPreview(
    for key: RecipeImportIdentityKey,
    in importRefs: [RecipeImportRef]
  ) -> [RecipeImportRef] {
    let refs = rawMatchingImportRefs(for: key, in: importRefs)
    guard !key.isTitleOnly, refs.count > 1 else { return refs }
    return Array(refs.prefix(1))
  }

  private static func rawMatchingImportRefs(
    for key: RecipeImportIdentityKey,
    in importRefs: [RecipeImportRef]
  ) -> [RecipeImportRef] {
    importRefs.filter {
      $0.normalizedTitle == key.normalizedTitle
        && $0.normalizedSourceURL == key.normalizedSourceURL
    }
    .sorted(by: areImportRefsInCanonicalOrder)
  }

  private static func mergeDuplicateImportedRecipes(
    canonicalRecipeID: Recipe.ID,
    duplicateRecipeIDs: Set<Recipe.ID>,
    in db: Database
  ) throws {
    guard !duplicateRecipeIDs.isEmpty else { return }

    for var item in try MealPlanItem.fetchAll(db) where item.recipeID.map(duplicateRecipeIDs.contains) == true {
      item.recipeID = canonicalRecipeID
      try MealPlanItem.upsert { item }.execute(db)
    }
    for var item in try MenuItem.fetchAll(db) where item.recipeID.map(duplicateRecipeIDs.contains) == true {
      item.recipeID = canonicalRecipeID
      try MenuItem.upsert { item }.execute(db)
    }
    for var source in try GroceryItemSource.fetchAll(db) where source.recipeID.map(duplicateRecipeIDs.contains) == true {
      source.recipeID = canonicalRecipeID
      try GroceryItemSource.upsert { source }.execute(db)
    }

    for recipeID in duplicateRecipeIDs {
      try Recipe.find(recipeID).delete().execute(db)
    }
  }

  private static func areImportRefsInCanonicalOrder(_ lhs: RecipeImportRef, _ rhs: RecipeImportRef) -> Bool {
    if lhs.dateCreated != rhs.dateCreated {
      return lhs.dateCreated < rhs.dateCreated
    }
    if lhs.id != rhs.id {
      return lhs.id.uuidString < rhs.id.uuidString
    }
    return lhs.recipeID.uuidString < rhs.recipeID.uuidString
  }

  private static func titleOnlyCollisionWarning(title: String) -> RecipeImportWarning {
    RecipeImportWarning(
      kind: .titleOnlyCollision,
      title: title,
      message: "A title-only import identity matched another recipe, so this recipe was imported as new."
    )
  }

  private static func ambiguousImportIdentityWarning(title: String) -> RecipeImportWarning {
    RecipeImportWarning(
      kind: .ambiguousImportIdentity,
      title: title,
      message: "An import identity matched more than one existing recipe, so this recipe was imported as new."
    )
  }
}
