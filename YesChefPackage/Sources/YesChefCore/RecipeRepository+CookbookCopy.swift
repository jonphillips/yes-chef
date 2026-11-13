import Foundation
import SQLiteData

public struct CookbookCopyResult: Equatable, Sendable {
  public var recipeID: Recipe.ID
  public var textOnlyServeWith: [String]
  public var unlinkedRelated: [String]
  public var warnings: [String]
}

public enum CookbookCopyError: Error, Equatable {
  case missingParent(UUID)
  case duplicateID(UUID)
}

extension RecipeRepository {
  public static func existingCopies(of bundle: RecipeBundleCoding.RecipeBundle, in db: Database) throws -> [Recipe.ID] {
    try existingCopies(sourceURL: bundle.source?.url, title: bundle.recipe.title, in: db)
  }

  private static func existingCopies(sourceURL: String?, title: String, in db: Database) throws -> [Recipe.ID] {
    let key = RecipeImportIdentityKey(sourceURL: sourceURL, title: title)
    let refs = try RecipeImportRef.fetchAll(db)
    let sources = try RecipeSource.fetchAll(db)
    var ids = Set(refs.filter { $0.normalizedSourceURL == key.normalizedSourceURL && $0.normalizedTitle == key.normalizedTitle }.map(\.recipeID))
    if let url = key.normalizedSourceURL {
      ids.formUnion(sources.filter { RecipeImportIdentityKey.normalizedSourceURL($0.url) == url }.map(\.recipeID))
    }
    return try Recipe.fetchAll(db).filter { !$0.archived && ids.contains($0.id) }.map(\.id).sorted { $0.uuidString < $1.uuidString }
  }

  /// Copy preserves structured content and provenance, while resetting personal view state.
  public static func copyCookbookRecipe(
    _ bundle: RecipeBundleCoding.RecipeBundle, ownerName: String, displayImages: [RecipePhoto.ID: Data],
    in db: Database, now: Date, uuid: () -> UUID
  ) throws -> CookbookCopyResult {
    var result: CookbookCopyResult?
    try db.inSavepoint {
      result = try performCookbookCopy(bundle, ownerName: ownerName, displayImages: displayImages, in: db, now: now, uuid: uuid)
      return .commit
    }
    guard let result else { throw CookbookCopyError.missingParent(bundle.recipe.id) }
    return result
  }

  private static func performCookbookCopy(
    _ bundle: RecipeBundleCoding.RecipeBundle, ownerName: String, displayImages: [RecipePhoto.ID: Data],
    in db: Database, now: Date, uuid: () -> UUID
  ) throws -> CookbookCopyResult {
    func ids<T>(_ rows: [T], id: KeyPath<T, UUID>) throws -> [UUID: UUID] {
      var result: [UUID: UUID] = [:]
      for row in rows {
        let old = row[keyPath: id]
        guard result[old] == nil else { throw CookbookCopyError.duplicateID(old) }
        result[old] = uuid()
      }
      return result
    }
    let recipeID = uuid()
    let ownerID = bundle.recipe.id
    let childOwners = bundle.ingredientSections.map(\.recipeID) + bundle.ingredientLines.map(\.recipeID)
      + bundle.instructionSections.map(\.recipeID) + bundle.instructionSteps.map(\.recipeID)
      + bundle.recipeNotes.map(\.recipeID) + bundle.photos.map(\.recipeID)
      + bundle.serveWith.map(\.recipeID) + bundle.variations.map(\.recipeID)
      + (bundle.source.map { [$0.recipeID] } ?? [])
    if let invalid = childOwners.first(where: { $0 != ownerID }) {
      throw CookbookCopyError.missingParent(invalid)
    }
    if let invalid = bundle.relatedRecipes.first(where: { $0.recipeID != ownerID && $0.relatedRecipeID != ownerID }) {
      throw CookbookCopyError.missingParent(invalid.recipeID)
    }
    let ingredientSections = try ids(bundle.ingredientSections, id: \.id)
    let lines = try ids(bundle.ingredientLines, id: \.id)
    let instructionSections = try ids(bundle.instructionSections, id: \.id)
    let steps = try ids(bundle.instructionSteps, id: \.id)
    let photos = try ids(bundle.photos, id: \.id)
    let notes = try ids(bundle.recipeNotes, id: \.id)
    let serveRows = try ids(bundle.serveWith, id: \.id)
    let variations = try ids(bundle.variations, id: \.id)
    let old = bundle.recipe
    let cover: UUID?
    if let id = old.coverPhotoID {
      guard let mapped = photos[id] else { throw CookbookCopyError.missingParent(id) }
      cover = mapped
    } else { cover = nil }
    let recipe = Recipe(id: recipeID, title: old.title, subtitle: old.subtitle, summary: old.summary,
      servings: old.servings, servingsText: old.servingsText, yieldText: old.yieldText,
      prepTimeMinutes: old.prepTimeMinutes, cookTimeMinutes: old.cookTimeMinutes, totalTimeMinutes: old.totalTimeMinutes,
      cuisine: old.cuisine, course: old.course, difficulty: old.difficulty, rating: nil, favorite: false,
      archived: false, libraryPlacement: old.libraryPlacement, dateCreated: now, dateModified: now,
      originalSnapshot: old.originalSnapshot, makeAhead: old.makeAhead, chefItUp: old.chefItUp,
      serveWith: old.serveWith, viewScale: 1, coverPhotoID: cover)
    try Recipe.insert { recipe }.execute(db)
    let source = bundle.source
    let newSource = RecipeSource(id: uuid(), recipeID: recipeID, name: source?.name, url: source?.url,
      author: source?.author, publicationName: source?.publicationName, bookTitle: source?.bookTitle,
      pageNumber: source?.pageNumber, importedFrom: "Copied from \(ownerName)'s cookbook", dateImported: now,
      sourceNotes: source?.sourceNotes)
    try RecipeSource.insert { newSource }.execute(db)
    for row in bundle.ingredientSections {
      guard let id = ingredientSections[row.id] else { throw CookbookCopyError.missingParent(row.id) }
      let copy = IngredientSection(id: id, recipeID: recipeID, name: row.name, sortOrder: row.sortOrder)
      try IngredientSection.insert { copy }.execute(db)
    }
    for row in bundle.ingredientLines {
      guard let id = lines[row.id], let section = ingredientSections[row.sectionID] else { throw CookbookCopyError.missingParent(row.sectionID) }
      let copy = IngredientLine(id: id, recipeID: recipeID, sectionID: section, originalText: row.originalText,
        quantity: row.quantity, quantityText: row.quantityText, unit: row.unit, item: row.item,
        canonicalName: row.canonicalName, preparation: row.preparation, comment: row.comment,
        isOptional: row.isOptional, doNotShop: row.doNotShop, isHeader: row.isHeader, sortOrder: row.sortOrder, confidence: row.confidence)
      try IngredientLine.insert { copy }.execute(db)
    }
    for row in bundle.instructionSections {
      guard let id = instructionSections[row.id] else { throw CookbookCopyError.missingParent(row.id) }
      let copy = InstructionSection(id: id, recipeID: recipeID, name: row.name, sortOrder: row.sortOrder)
      try InstructionSection.insert { copy }.execute(db)
    }
    for row in bundle.instructionSteps {
      guard let id = steps[row.id], let section = instructionSections[row.sectionID] else { throw CookbookCopyError.missingParent(row.sectionID) }
      let copy = InstructionStep(id: id, recipeID: recipeID, sectionID: section, text: row.text, sortOrder: row.sortOrder, isOptional: row.isOptional)
      try InstructionStep.insert { copy }.execute(db)
    }
    for row in bundle.recipeNotes {
      guard let id = notes[row.id] else { throw CookbookCopyError.missingParent(row.id) }
      let copy = RecipeNote(id: id, recipeID: recipeID, text: row.text, noteType: row.noteType,
        dateCreated: row.dateCreated, dateModified: row.dateModified, pinned: row.pinned)
      try RecipeNote.insert { copy }.execute(db)
    }
    for row in bundle.photos {
      guard let id = photos[row.id] else { throw CookbookCopyError.missingParent(row.id) }
      let copy = RecipePhoto(id: id, recipeID: recipeID, imageDataReference: "recipePhotos/\(id.uuidString)",
        displayData: displayImages[row.id], thumbnailData: row.thumbnailData, mediaType: row.mediaType,
        pixelWidth: row.pixelWidth, pixelHeight: row.pixelHeight, originalSourcePath: row.originalSourcePath,
        sourceURL: row.sourceURL, checksum: row.checksum, kind: row.kind, caption: row.caption,
        source: row.source, sortOrder: row.sortOrder, dateCreated: row.dateCreated)
      try RecipePhoto.insert { copy }.execute(db)
    }
    var warnings: [String] = []
    for row in bundle.variations {
      guard let id = variations[row.id] else { throw CookbookCopyError.missingParent(row.id) }
      var deltas = row.deltas
      if let data = deltas {
        do {
          var payload = try RecipeVariationPayload.decode(data, variationID: row.id)
          func ingredient(_ ref: RecipeIngredientReference) -> RecipeIngredientReference {
            var ref = ref; ref.id = ref.id.flatMap { lines[$0] }; return ref
          }
          func step(_ ref: RecipeStepReference) -> RecipeStepReference {
            var ref = ref; ref.id = ref.id.flatMap { steps[$0] }; return ref
          }
          payload.ingredientOps = payload.ingredientOps.map { op in
            switch op {
            case .add: op
            case let .remove(ref): .remove(ingredient(ref))
            case let .substitute(ref, line): .substitute(ingredient(ref), line: line)
            case let .scale(ref, line): .scale(ingredient(ref), line: line)
            }
          }
          payload.methodStepReplacements = payload.methodStepReplacements.map { replacement in
            var replacement = replacement; replacement.id = replacement.id.flatMap { steps[$0] }; return replacement
          }
          payload.methodStepStructuralOps = payload.methodStepStructuralOps.map { op in
            switch op {
            case let .insert(after, sectionID, text): .insert(after: after.map(step), sectionID: sectionID.flatMap { instructionSections[$0] }, text: text)
            case let .remove(ref): .remove(step(ref))
            }
          }
          deltas = try payload.encodedData()
        } catch { warnings.append("Variation \(row.name) has unreadable deltas.") }
      }
      let copy = RecipeVariation(id: id, recipeID: recipeID, name: row.name, note: row.note,
        sortIndex: row.sortIndex, deltas: deltas, origin: row.origin, dateCreated: row.dateCreated, dateModified: row.dateModified)
      try RecipeVariation.insert { copy }.execute(db)
    }
    if bundle.version < 2 {
      try reconcileCategories(bundle.categoryNames, looseNames: bundle.tagNames, recipeID: recipeID, in: db, now: now, uuid: uuid)
    } else {
      try copyCookbookLabels(bundle.labels, recipeID: recipeID, in: db, now: now, uuid: uuid)
    }
    let targets = Dictionary(bundle.linkTargets.map { ($0.recipeID, $0) }, uniquingKeysWith: { first, _ in first })
    func resolve(_ id: UUID) throws -> UUID? {
      guard let target = targets[id] else { return nil }
      let matches = try existingCopies(sourceURL: target.sourceURL, title: target.title, in: db).filter { $0 != recipeID }
      return matches.count == 1 ? matches[0] : nil
    }
    var textOnly: [String] = []
    for row in bundle.serveWith {
      guard let id = serveRows[row.id] else { throw CookbookCopyError.missingParent(row.id) }
      let linked = try row.linkedRecipeID.flatMap { try resolve($0) }
      if linked == nil { textOnly.append(row.title) }
      let copy = RecipeServeWith(id: id, recipeID: recipeID, linkedRecipeID: linked, title: row.title, note: row.note,
        sortOrder: row.sortOrder, provenance: row.provenance, dateCreated: row.dateCreated, dateModified: row.dateModified)
      try RecipeServeWith.insert { copy }.execute(db)
    }
    var unlinked: [String] = []
    for row in bundle.relatedRecipes {
      let other = row.recipeID == old.id ? row.relatedRecipeID : row.recipeID
      if let resolved = try resolve(other), resolved != recipeID {
        try linkRelatedRecipes(recipeID, resolved, in: db, now: now, uuid: uuid)
      } else { unlinked.append(targets[other]?.title ?? other.uuidString) }
    }
    let key = RecipeImportIdentityKey(sourceURL: source?.url, title: old.title)
    let ref = RecipeImportRef(id: uuid(), recipeID: recipeID, normalizedSourceURL: key.normalizedSourceURL,
      normalizedTitle: key.normalizedTitle, dateCreated: now)
    try RecipeImportRef.insert { ref }.execute(db)
    return CookbookCopyResult(recipeID: recipeID, textOnlyServeWith: textOnly, unlinkedRelated: unlinked, warnings: warnings)
  }

  private static func copyCookbookLabels(_ labels: [RecipeBundleCoding.LabelPath], recipeID: UUID, in db: Database, now: Date, uuid: () -> UUID) throws {
    var facets = try Facet.fetchAll(db)
    var categories = try Category.fetchAll(db)
    var joined: Set<UUID> = []
    for label in labels {
      var facetID: UUID?
      if let name = label.facet {
        if let existing = facets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { facetID = existing.id }
        else {
          let facet = Facet(id: uuid(), name: name, sortOrder: facets.count, dateCreated: now)
          try Facet.insert { facet }.execute(db); facets.append(facet); facetID = facet.id
        }
      }
      var parentID: UUID?
      for component in label.path {
        if let existing = categories.first(where: { $0.facetID == facetID && $0.parentCategoryID == parentID && $0.name.caseInsensitiveCompare(component) == .orderedSame }) { parentID = existing.id }
        else {
          let category = Category(id: uuid(), name: component, facetID: facetID, parentCategoryID: parentID,
            sortOrder: categories.filter { $0.facetID == facetID && $0.parentCategoryID == parentID }.count, dateCreated: now)
          try Category.insert { category }.execute(db); categories.append(category); parentID = category.id
        }
      }
      guard let categoryID = parentID else { throw CategoryHierarchyError.emptyPath }
      if joined.insert(categoryID).inserted {
        let join = RecipeCategory(id: uuid(), recipeID: recipeID, categoryID: categoryID)
        try RecipeCategory.insert { join }.execute(db)
      }
    }
  }
}
