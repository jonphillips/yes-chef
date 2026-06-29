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

extension RecipeRepository {
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
    let titleOnlyBatchCounts = bundles
      .map { importIdentityKey(for: $0) }
      .filter(\.isTitleOnly)
      .reduce(into: [RecipeImportIdentityKey: Int]()) { counts, key in
        counts[key, default: 0] += 1
      }
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

  private static func importBundle(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    importRefs: inout [RecipeImportRef],
    titleOnlyBatchCount: Int
  ) throws -> RecipeImportBundleResult {
    let key = importIdentityKey(for: bundle)
    let matchingRefs = matchingImportRefs(for: key, in: importRefs)

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

  private static func matchingImportRefs(
    for key: RecipeImportIdentityKey,
    in importRefs: [RecipeImportRef]
  ) -> [RecipeImportRef] {
    importRefs.filter {
      $0.normalizedTitle == key.normalizedTitle
        && $0.normalizedSourceURL == key.normalizedSourceURL
    }
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
