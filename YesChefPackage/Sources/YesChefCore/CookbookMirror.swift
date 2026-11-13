import Dependencies
import Foundation
import SQLiteData

/// A disposable, unsynchronized cache. All consumers share this guarded database pool.
public final class CookbookMirror: Sendable {
  public let database: any DatabaseWriter
  public let fileURL: URL

  public init(id: UUID, directory: URL? = nil) throws {
    var folder = try directory ?? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("Cookbooks", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    let fileURL = folder.appendingPathComponent(id.uuidString).appendingPathExtension("sqlite")
    let migrator = YesChefSchema.migrator()
    if FileManager.default.fileExists(atPath: fileURL.path) {
      let inspection = try DatabaseQueue(path: fileURL.path)
      let applied = try inspection.read { db in
        try db.tableExists("grdb_migrations")
          ? String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") : []
      }
      try inspection.close()
      if applied != migrator.migrations {
        try Self.removeFiles(at: fileURL)
      }
    }
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      let creation = try DatabaseQueue(path: fileURL.path)
      try migrator.migrate(creation)
      try creation.close()
    }
    let pool = try DatabasePool(path: fileURL.path)
    try pool.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }
    self.database = pool
    self.fileURL = fileURL
  }

  /// Lossless-or-loud cache update: malformed or incomplete rows roll back the whole batch.
  public func apply(upserting bundles: [RecipeBundleCoding.RecipeBundle], deleting ids: [Recipe.ID]) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid
    try database.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA query_only = 0")
      defer { try? db.execute(sql: "PRAGMA query_only = 1") }
      try db.inTransaction {
        for bundle in bundles {
          try Self.upsert(bundle, in: db, now: now, uuid: { uuid() })
        }
        for id in ids {
          try RecipeRelatedRecipe.where { $0.recipeID.eq(id) || $0.relatedRecipeID.eq(id) }.delete().execute(db)
          try Recipe.find(id).delete().execute(db)
        }
        try Self.pruneLabels(in: db)
        return .commit
      }
    }
  }

  private static func upsert(
    _ bundle: RecipeBundleCoding.RecipeBundle, in db: Database, now: Date, uuid: () -> UUID
  ) throws {
    let id = bundle.recipe.id
    let owners = bundle.ingredientSections.map(\.recipeID) + bundle.ingredientLines.map(\.recipeID)
      + bundle.instructionSections.map(\.recipeID) + bundle.instructionSteps.map(\.recipeID)
      + bundle.recipeNotes.map(\.recipeID) + bundle.photos.map(\.recipeID)
      + bundle.variations.map(\.recipeID) + bundle.serveWith.map(\.recipeID)
      + (bundle.source.map { [$0.recipeID] } ?? [])
    if let invalid = owners.first(where: { $0 != id }) { throw CookbookCopyError.missingParent(invalid) }
    if let invalid = bundle.relatedRecipes.first(where: { $0.recipeID != id && $0.relatedRecipeID != id }) {
      throw CookbookCopyError.missingParent(invalid.recipeID)
    }
    let oldLabels = try CookbookPayload.bundle(for: id, in: db)?.labels ?? []
    if try Recipe.find(id).fetchOne(db) != bundle.recipe {
      try Recipe.upsert { bundle.recipe }.execute(db)
    }
    let sourceRows = bundle.source.map { [$0] } ?? []
    let oldSource = try RecipeSource.where { $0.recipeID.eq(id) }.fetchAll(db)
    let sourceByID = Dictionary(uniqueKeysWithValues: oldSource.map { ($0.id, $0) })
    for row in sourceRows where sourceByID[row.id] != row {
      try RecipeSource.upsert { row }.execute(db)
    }
    let ingredientSectionRows = bundle.ingredientSections
    let oldIngredientsection = try IngredientSection.where { $0.recipeID.eq(id) }.fetchAll(db)
    let ingredientSectionByID = Dictionary(uniqueKeysWithValues: oldIngredientsection.map { ($0.id, $0) })
    for row in ingredientSectionRows where ingredientSectionByID[row.id] != row {
      try IngredientSection.upsert { row }.execute(db)
    }
    let instructionSectionRows = bundle.instructionSections
    let oldInstructionsection = try InstructionSection.where { $0.recipeID.eq(id) }.fetchAll(db)
    let instructionSectionByID = Dictionary(uniqueKeysWithValues: oldInstructionsection.map { ($0.id, $0) })
    for row in instructionSectionRows where instructionSectionByID[row.id] != row {
      try InstructionSection.upsert { row }.execute(db)
    }
    let ingredientLineRows = bundle.ingredientLines
    let oldIngredientline = try IngredientLine.where { $0.recipeID.eq(id) }.fetchAll(db)
    let ingredientLineByID = Dictionary(uniqueKeysWithValues: oldIngredientline.map { ($0.id, $0) })
    for row in ingredientLineRows where ingredientLineByID[row.id] != row {
      try IngredientLine.upsert { row }.execute(db)
    }
    let instructionStepRows = bundle.instructionSteps
    let oldInstructionstep = try InstructionStep.where { $0.recipeID.eq(id) }.fetchAll(db)
    let instructionStepByID = Dictionary(uniqueKeysWithValues: oldInstructionstep.map { ($0.id, $0) })
    for row in instructionStepRows where instructionStepByID[row.id] != row {
      try InstructionStep.upsert { row }.execute(db)
    }
    let noteRows = bundle.recipeNotes
    let oldNote = try RecipeNote.where { $0.recipeID.eq(id) }.fetchAll(db)
    let noteByID = Dictionary(uniqueKeysWithValues: oldNote.map { ($0.id, $0) })
    for row in noteRows where noteByID[row.id] != row {
      try RecipeNote.upsert { row }.execute(db)
    }
    let photoRows = bundle.photos
    let oldPhoto = try RecipePhoto.where { $0.recipeID.eq(id) }.fetchAll(db)
    let photoByID = Dictionary(uniqueKeysWithValues: oldPhoto.map { ($0.id, $0) })
    for row in photoRows where photoByID[row.id] != row {
      try RecipePhoto.upsert { row }.execute(db)
    }
    let variationRows = bundle.variations
    let oldVariation = try RecipeVariation.where { $0.recipeID.eq(id) }.fetchAll(db)
    let variationByID = Dictionary(uniqueKeysWithValues: oldVariation.map { ($0.id, $0) })
    for row in variationRows where variationByID[row.id] != row {
      try RecipeVariation.upsert { row }.execute(db)
    }
    let serveRows = bundle.serveWith
    let oldServe = try RecipeServeWith.where { $0.recipeID.eq(id) }.fetchAll(db)
    let serveByID = Dictionary(uniqueKeysWithValues: oldServe.map { ($0.id, $0) })
    for row in serveRows where serveByID[row.id] != row {
      try RecipeServeWith.upsert { row }.execute(db)
    }
    let sourceIDs = Set(sourceRows.map(\.id))
    for row in oldSource where !sourceIDs.contains(row.id) {
      try RecipeSource.find(row.id).delete().execute(db)
    }
    let ingredientSectionIDs = Set(ingredientSectionRows.map(\.id))
    for row in oldIngredientsection where !ingredientSectionIDs.contains(row.id) {
      try IngredientSection.find(row.id).delete().execute(db)
    }
    let instructionSectionIDs = Set(instructionSectionRows.map(\.id))
    for row in oldInstructionsection where !instructionSectionIDs.contains(row.id) {
      try InstructionSection.find(row.id).delete().execute(db)
    }
    let ingredientLineIDs = Set(ingredientLineRows.map(\.id))
    for row in oldIngredientline where !ingredientLineIDs.contains(row.id) {
      try IngredientLine.find(row.id).delete().execute(db)
    }
    let instructionStepIDs = Set(instructionStepRows.map(\.id))
    for row in oldInstructionstep where !instructionStepIDs.contains(row.id) {
      try InstructionStep.find(row.id).delete().execute(db)
    }
    let noteIDs = Set(noteRows.map(\.id))
    for row in oldNote where !noteIDs.contains(row.id) {
      try RecipeNote.find(row.id).delete().execute(db)
    }
    let photoIDs = Set(photoRows.map(\.id))
    for row in oldPhoto where !photoIDs.contains(row.id) {
      try RecipePhoto.find(row.id).delete().execute(db)
    }
    let variationIDs = Set(variationRows.map(\.id))
    for row in oldVariation where !variationIDs.contains(row.id) {
      try RecipeVariation.find(row.id).delete().execute(db)
    }
    let serveIDs = Set(serveRows.map(\.id))
    for row in oldServe where !serveIDs.contains(row.id) {
      try RecipeServeWith.find(row.id).delete().execute(db)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let oldLabelKeys = try oldLabels.map { try encoder.encode($0) }.sorted { $0.lexicographicallyPrecedes($1) }
    let newLabelKeys = try bundle.labels.map { try encoder.encode($0) }.sorted { $0.lexicographicallyPrecedes($1) }
    if oldLabelKeys != newLabelKeys {
      try RecipeCategory.where { $0.recipeID.eq(id) }.delete().execute(db)
      try RecipeRepository.copyCookbookLabels(bundle.labels, recipeID: id, in: db, now: now, uuid: uuid)
    }
    let existing = try RecipeRelatedRecipe.where { $0.recipeID.eq(id) || $0.relatedRecipeID.eq(id) }.fetchAll(db)
    let wanted = Set(bundle.relatedRecipes.map(\.id))
    for row in existing where !wanted.contains(row.id) {
      try RecipeRelatedRecipe.find(row.id).delete().execute(db)
    }
    for row in bundle.relatedRecipes {
      guard try Recipe.find(row.recipeID).fetchOne(db) != nil,
        try Recipe.find(row.relatedRecipeID).fetchOne(db) != nil else { continue }
      if try RecipeRelatedRecipe.find(row.id).fetchOne(db) != row {
        try RecipeRelatedRecipe.upsert { row }.execute(db)
      }
    }
  }

  private static func pruneLabels(in db: Database) throws {
    let categories = try Category.fetchAll(db)
    let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    var used = Set(try RecipeCategory.fetchAll(db).map(\.categoryID))
    for id in Array(used) {
      var parent = byID[id]?.parentCategoryID
      while let id = parent, used.insert(id).inserted { parent = byID[id]?.parentCategoryID }
    }
    for category in categories where !used.contains(category.id) {
      try Category.find(category.id).delete().execute(db)
    }
    let usedFacets = Set(categories.filter { used.contains($0.id) }.compactMap(\.facetID))
    for facet in try Facet.fetchAll(db) where !usedFacets.contains(facet.id) {
      try Facet.find(facet.id).delete().execute(db)
    }
  }

  public func deleteMirror() throws {
    try database.close()
    try Self.removeFiles(at: fileURL)
  }

  private static func removeFiles(at url: URL) throws {
    for path in [url.path, url.path + "-wal", url.path + "-shm"] {
      if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.removeItem(atPath: path)
      }
    }
  }
}
