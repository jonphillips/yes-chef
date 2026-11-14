import Dependencies
import Foundation
import SQLiteData
import GRDB

public struct CookbookMirrorState: Equatable, Sendable {
  public var changeToken: Data?
  public var payloadVersion: Int
  public var displayName: String?
  public var recipeCount: Int?
  public var publishedAt: Date?
  public var fetchedAt: Date?
  public var fullFetchActive: Bool

  public init(
    changeToken: Data? = nil, payloadVersion: Int = 0, displayName: String? = nil, recipeCount: Int? = nil,
    publishedAt: Date? = nil, fetchedAt: Date? = nil, fullFetchActive: Bool = false
  ) {
    self.changeToken = changeToken
    self.payloadVersion = payloadVersion
    self.displayName = displayName
    self.recipeCount = recipeCount
    self.publishedAt = publishedAt
    self.fetchedAt = fetchedAt
    self.fullFetchActive = fullFetchActive
  }
}

public struct CookbookMirrorPage: Sendable {
  public var bundles: [RecipeBundleCoding.RecipeBundle]
  public var deletedRecipeIDs: [Recipe.ID]
  public var seenRecordNames: [String]
  public var profile: CookbookPublishProfile?
  public var lensBundle: CookbookLensBundle?
  public var deletesLensRecord: Bool
  public var skippedRecords: [String: Int]
  public var changeToken: Data?
  public var payloadVersion: Int
  public var startsFullFetch: Bool
  public var finishesFullFetch: Bool

  public init(
    bundles: [RecipeBundleCoding.RecipeBundle] = [], deletedRecipeIDs: [Recipe.ID] = [],
    seenRecordNames: [String] = [], profile: CookbookPublishProfile? = nil,
    lensBundle: CookbookLensBundle? = nil, deletesLensRecord: Bool = false,
    skippedRecords: [String: Int] = [:], changeToken: Data? = nil,
    payloadVersion: Int = RecipeBundleCoding.currentVersion, startsFullFetch: Bool = false,
    finishesFullFetch: Bool = false
  ) {
    self.bundles = bundles
    self.deletedRecipeIDs = deletedRecipeIDs
    self.seenRecordNames = seenRecordNames
    self.profile = profile
    self.lensBundle = lensBundle
    self.deletesLensRecord = deletesLensRecord
    self.skippedRecords = skippedRecords
    self.changeToken = changeToken
    self.payloadVersion = payloadVersion
    self.startsFullFetch = startsFullFetch
    self.finishesFullFetch = finishesFullFetch
  }
}

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
    try pool.write { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS cookbookMirrorState (
          id INTEGER PRIMARY KEY CHECK (id = 1), changeToken BLOB, payloadVersion INTEGER NOT NULL DEFAULT 0,
          displayName TEXT, recipeCount INTEGER, publishedAt REAL, fetchedAt REAL, fullFetchActive INTEGER NOT NULL DEFAULT 0
        )
        """)
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS cookbookMirrorSkipped (
          recordName TEXT PRIMARY KEY NOT NULL, payloadVersion INTEGER NOT NULL
        )
        """)
      try db.execute(sql: "CREATE TABLE IF NOT EXISTS cookbookMirrorSeen (recordName TEXT PRIMARY KEY NOT NULL)")
      try db.execute(sql: "INSERT OR IGNORE INTO cookbookMirrorState(id) VALUES (1)")
    }
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

  public func apply(page: CookbookMirrorPage) throws {
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid
    try database.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA query_only = 0")
      defer { try? db.execute(sql: "PRAGMA query_only = 1") }
      try db.inTransaction {
        if page.startsFullFetch { try db.execute(sql: "DELETE FROM cookbookMirrorSeen") }
        if page.startsFullFetch { try db.execute(sql: "UPDATE cookbookMirrorState SET fullFetchActive = 1 WHERE id = 1") }
        for bundle in page.bundles {
          try Self.upsert(bundle, in: db, now: now, uuid: { uuid() })
          try db.execute(sql: "DELETE FROM cookbookMirrorSkipped WHERE recordName = ?", arguments: [bundle.recipe.id.uuidString])
        }
        for id in page.deletedRecipeIDs {
          try RecipeRelatedRecipe.where { $0.recipeID.eq(id) || $0.relatedRecipeID.eq(id) }.delete().execute(db)
          try Recipe.find(id).delete().execute(db)
          try db.execute(sql: "DELETE FROM cookbookMirrorSkipped WHERE recordName = ?", arguments: [id.uuidString])
        }
        for recordName in page.seenRecordNames {
          try db.execute(sql: "INSERT OR IGNORE INTO cookbookMirrorSeen(recordName) VALUES (?)", arguments: [recordName])
        }
        if let lensBundle = page.lensBundle {
          let invalidLensNames = try Self.replaceLenses(lensBundle, in: db)
          try db.execute(sql: "DELETE FROM cookbookMirrorSkipped WHERE recordName = 'lenses' OR recordName LIKE 'lens-%'")
          for name in invalidLensNames {
            try db.execute(
              sql: "INSERT OR REPLACE INTO cookbookMirrorSkipped(recordName, payloadVersion) VALUES (?, ?)",
              arguments: [name, CookbookLensBundle.currentVersion]
            )
          }
        } else if page.deletesLensRecord {
          _ = try Self.replaceLenses(CookbookLensBundle(lenses: [], shelves: [], categories: [], facets: []), in: db)
          try db.execute(sql: "DELETE FROM cookbookMirrorSkipped WHERE recordName = 'lenses' OR recordName LIKE 'lens-%'")
        }
        for (name, version) in page.skippedRecords {
          try db.execute(sql: "INSERT OR REPLACE INTO cookbookMirrorSkipped(recordName, payloadVersion) VALUES (?, ?)", arguments: [name, version])
        }
        if let profile = page.profile {
          try db.execute(sql: "UPDATE cookbookMirrorState SET displayName = ?, recipeCount = ?, publishedAt = ?, fetchedAt = ? WHERE id = 1",
            arguments: [profile.displayName, profile.recipeCount, profile.publishedAt, now])
        } else {
          try db.execute(sql: "UPDATE cookbookMirrorState SET fetchedAt = ? WHERE id = 1", arguments: [now])
        }
        if let token = page.changeToken {
          try db.execute(sql: "UPDATE cookbookMirrorState SET changeToken = ?, payloadVersion = ? WHERE id = 1",
            arguments: [token, page.payloadVersion])
        }
        if page.finishesFullFetch {
          let seen = Set(try String.fetchAll(db, sql: "SELECT recordName FROM cookbookMirrorSeen"))
          let recipeIDs = try Recipe.fetchAll(db).map(\.id)
          for id in recipeIDs where !seen.contains(id.uuidString) {
            try RecipeRelatedRecipe.where { $0.recipeID.eq(id) || $0.relatedRecipeID.eq(id) }.delete().execute(db)
            try Recipe.find(id).delete().execute(db)
          }
          try db.execute(sql: "DELETE FROM cookbookMirrorSeen")
          try db.execute(sql: "UPDATE cookbookMirrorState SET fullFetchActive = 0 WHERE id = 1")
        }
        let currentLensBundle: CookbookLensBundle?
        if let lensBundle = page.lensBundle {
          currentLensBundle = lensBundle
        } else if page.deletesLensRecord {
          currentLensBundle = nil
        } else {
          currentLensBundle = try CookbookLensBundle.read(from: db)
        }
        try Self.pruneLabels(in: db, preserving: currentLensBundle)
        return .commit
      }
    }
  }

  public func fetchState() throws -> CookbookMirrorState {
    try database.read { db in
      guard let row = try Row.fetchOne(db, sql: "SELECT changeToken, payloadVersion, displayName, recipeCount, publishedAt, fetchedAt, fullFetchActive FROM cookbookMirrorState WHERE id = 1") else {
        return CookbookMirrorState()
      }
      return CookbookMirrorState(
        changeToken: row["changeToken"], payloadVersion: row["payloadVersion"], displayName: row["displayName"],
        recipeCount: row["recipeCount"], publishedAt: row["publishedAt"], fetchedAt: row["fetchedAt"],
        fullFetchActive: row["fullFetchActive"]
      )
    }
  }

  public func skippedRecordCount() throws -> Int {
    try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cookbookMirrorSkipped") ?? 0 }
  }

  public func resetChangeTokenForFullFetch() throws {
    try database.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA query_only = 0")
      defer { try? db.execute(sql: "PRAGMA query_only = 1") }
      try db.inTransaction {
        try db.execute(sql: "UPDATE cookbookMirrorState SET changeToken = NULL, fullFetchActive = 0 WHERE id = 1")
        try db.execute(sql: "DELETE FROM cookbookMirrorSeen")
        return .commit
      }
    }
  }

  public func cacheDisplayImage(_ data: Data, photoID: RecipePhoto.ID) throws {
    try database.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA query_only = 0")
      defer { try? db.execute(sql: "PRAGMA query_only = 1") }
      try db.inTransaction {
        guard var photo = try RecipePhoto.find(photoID).fetchOne(db) else { return .commit }
        photo.displayData = data
        try RecipePhoto.upsert { photo }.execute(db)
        return .commit
      }
    }
  }

  private static func replaceLenses(_ bundle: CookbookLensBundle, in db: Database) throws -> [String] {
    try RecipeLensShelf.fetchAll(db).forEach { try RecipeLensShelf.find($0.id).delete().execute(db) }
    try RecipeLens.fetchAll(db).forEach { try RecipeLens.find($0.id).delete().execute(db) }
    for facet in bundle.facets { try Facet.upsert { facet }.execute(db) }
    for category in bundle.categories { try Category.upsert { category }.execute(db) }
    func decodes(_ value: String) -> Bool { (try? RecipeLensQueryCodec.decode(value)) != nil }
    let invalidLensIDs = Set(bundle.lenses.filter { !decodes($0.baseQuery) }.map(\.id)
      + bundle.shelves.filter { !decodes($0.query) }.map(\.lensID))
    let valid = bundle.lenses.filter { !invalidLensIDs.contains($0.id) && decodes($0.baseQuery) }
    let validIDs = Set(valid.map(\.id))
    for lens in valid { try RecipeLens.upsert { lens }.execute(db) }
    for shelf in bundle.shelves where validIDs.contains(shelf.lensID) && decodes(shelf.query) {
      try RecipeLensShelf.upsert { shelf }.execute(db)
    }
    return invalidLensIDs.sorted { $0.uuidString < $1.uuidString }.map { "lens-\($0.uuidString)" }
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

  private static func pruneLabels(in db: Database, preserving lenses: CookbookLensBundle? = nil) throws {
    let categories = try Category.fetchAll(db)
    let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    var used = Set(try RecipeCategory.fetchAll(db).map(\.categoryID))
    let lensCategoryIDs = Set(lenses?.categories.map(\.id) ?? [])
    used.formUnion(lensCategoryIDs)
    for id in Array(used) {
      var parent = byID[id]?.parentCategoryID
      while let id = parent, used.insert(id).inserted { parent = byID[id]?.parentCategoryID }
    }
    for category in categories where !used.contains(category.id) {
      try Category.find(category.id).delete().execute(db)
    }
    let usedFacets = Set(categories.filter { used.contains($0.id) }.compactMap(\.facetID))
      .union(lenses?.facets.map(\.id) ?? [])
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
