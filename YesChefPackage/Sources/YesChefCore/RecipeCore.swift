import Foundation
import SQLiteData

/// A slim projection of `RecipePhoto` for the detail screen: metadata plus the
/// small `thumbnailData` and a `hasDisplayData` presence flag, but **never** the
/// full-resolution `displayData` bytes. Carrying those in the observed
/// `RecipeDetailData` is what made every `SyncEngine` commit re-run a multi-MB
/// fetch synchronously on the writer connection (ADR-0029 Amendment 2, Finding 5),
/// and bloated the `Equatable` payload the animated re-publish diffs. Hero and
/// full-screen bytes are read on demand from the concurrent reader pool instead.
///
/// Deliberately not a `@Table` and not directly persistable — a slim row must
/// never round-trip back to the database (that would null out image bytes). See
/// `leanRecipePhoto` for the one allowed, byte-free conversion used by passive
/// snapshots.
public struct RecipeDetailPhoto: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var imageDataReference: String
  public var thumbnailData: Data?
  public var hasDisplayData: Bool
  public var mediaType: String?
  public var pixelWidth: Int?
  public var pixelHeight: Int?
  public var checksum: String?
  public var kind: RecipePhotoKind
  public var caption: String?
  public var source: PhotoSource
  public var sortOrder: Int
  public var dateCreated: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    imageDataReference: String,
    thumbnailData: Data? = nil,
    hasDisplayData: Bool = false,
    mediaType: String? = nil,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    checksum: String? = nil,
    kind: RecipePhotoKind = .gallery,
    caption: String? = nil,
    source: PhotoSource = .user,
    sortOrder: Int,
    dateCreated: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.imageDataReference = imageDataReference
    self.thumbnailData = thumbnailData
    self.hasDisplayData = hasDisplayData
    self.mediaType = mediaType
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.checksum = checksum
    self.kind = kind
    self.caption = caption
    self.source = source
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }

  /// Any image bytes are worth displaying — an on-demand hero read hydrates
  /// `displayData` even when the fetch carried only a thumbnail (or neither).
  public var isDisplayable: Bool {
    hasDisplayData || thumbnailData != nil
  }

  /// A metadata-only `RecipePhoto` (no image bytes) for passive snapshotting only.
  /// Never persist this — it deliberately carries no `displayData`/`thumbnailData`.
  public var leanRecipePhoto: RecipePhoto {
    RecipePhoto(
      id: id,
      recipeID: recipeID,
      imageDataReference: imageDataReference,
      displayData: nil,
      thumbnailData: nil,
      mediaType: mediaType,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      checksum: checksum,
      kind: kind,
      caption: caption,
      source: source,
      sortOrder: sortOrder,
      dateCreated: dateCreated
    )
  }
}

public struct RecipeDetailData: Equatable, Sendable {
  public var recipe: Recipe
  public var source: RecipeSource?
  public var ingredientSections: [IngredientSection]
  public var ingredientLines: [IngredientLine]
  public var instructionSections: [InstructionSection]
  public var instructionSteps: [InstructionStep]
  public var notes: [RecipeNote]
  public var photos: [RecipeDetailPhoto]
  public var categories: [Category]
  public var categoryDisplayNames: [String]
  public var equipment: [Equipment]
  public var recipeEquipment: [RecipeEquipment]
  public var learnings: [Learning]
  public var serveWith: [RecipeServeWith]
  public var variations: [RecipeVariation]
  public var deliberationLogEntries: [RecipeDeliberationLogEntry]
  public var activeVariationID: RecipeVariation.ID?

  public init(
    recipe: Recipe,
    source: RecipeSource? = nil,
    ingredientSections: [IngredientSection] = [],
    ingredientLines: [IngredientLine] = [],
    instructionSections: [InstructionSection] = [],
    instructionSteps: [InstructionStep] = [],
    notes: [RecipeNote] = [],
    photos: [RecipeDetailPhoto] = [],
    categories: [Category] = [],
    categoryDisplayNames: [String] = [],
    equipment: [Equipment] = [],
    recipeEquipment: [RecipeEquipment] = [],
    learnings: [Learning] = [],
    serveWith: [RecipeServeWith] = [],
    variations: [RecipeVariation] = [],
    deliberationLogEntries: [RecipeDeliberationLogEntry] = [],
    activeVariationID: RecipeVariation.ID? = nil
  ) {
    self.recipe = recipe
    self.source = source
    self.ingredientSections = ingredientSections
    self.ingredientLines = ingredientLines
    self.instructionSections = instructionSections
    self.instructionSteps = instructionSteps
    self.notes = notes
    self.photos = photos
    self.categories = categories
    self.categoryDisplayNames = categoryDisplayNames
    self.equipment = equipment
    self.recipeEquipment = recipeEquipment
    self.learnings = learnings
    self.serveWith = serveWith
    self.variations = variations
    self.deliberationLogEntries = deliberationLogEntries
    self.activeVariationID = activeVariationID
  }
}

public struct RecipeDetailRequest: FetchKeyRequest {
  public let recipeID: Recipe.ID

  public init(recipeID: Recipe.ID) {
    self.recipeID = recipeID
  }

  public func fetch(_ db: Database) throws -> RecipeDetailData? {
    let clock = ContinuousClock()
    let start = clock.now
    defer {
      let duration = String(describing: start.duration(to: clock.now))
      AppLog.performance.log("recipe-detail-request-fetch duration=\(duration, privacy: .public)")
    }
    return try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)
  }
}

/// Column projection backing `RecipeDetailData.photos`. Selects `thumbnailData`
/// and a `displayData IS NOT NULL` presence flag, but never the `displayData`
/// bytes themselves — the point of ADR-0029 Amendment 2 S5b.
@Selection
struct RecipeDetailPhotoRow: Equatable, Sendable {
  let id: UUID
  let recipeID: Recipe.ID
  let imageDataReference: String
  let thumbnailData: Data?
  let hasDisplayData: Bool
  let mediaType: String?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let checksum: String?
  let kind: RecipePhotoKind
  let caption: String?
  let source: PhotoSource
  let sortOrder: Int
  let dateCreated: Date

  var detailPhoto: RecipeDetailPhoto {
    RecipeDetailPhoto(
      id: id,
      recipeID: recipeID,
      imageDataReference: imageDataReference,
      thumbnailData: thumbnailData,
      hasDisplayData: hasDisplayData,
      mediaType: mediaType,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      checksum: checksum,
      kind: kind,
      caption: caption,
      source: source,
      sortOrder: sortOrder,
      dateCreated: dateCreated
    )
  }
}

public enum RecipeRepository {
  public static func fetchDetail(recipeID: Recipe.ID, in db: Database) throws -> RecipeDetailData? {
    guard let recipe = try (Recipe.where { $0.id.eq(recipeID) })
      .fetchOne(db)
    else { return nil }
    guard !recipe.archived else { return nil }

    let ingredientSections = try (IngredientSection.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .fetchAll(db)
    let ingredientLines = try (IngredientLine.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .fetchAll(db)
    let instructionSections = try (InstructionSection.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .fetchAll(db)
    let instructionSteps = try (InstructionStep.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .fetchAll(db)
    let notes = try (RecipeNote.where { $0.recipeID.eq(recipeID) })
      .order { $0.dateCreated.desc() }
      .fetchAll(db)
    let photos = try (RecipePhoto.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .select {
        RecipeDetailPhotoRow.Columns(
          id: $0.id,
          recipeID: $0.recipeID,
          imageDataReference: $0.imageDataReference,
          thumbnailData: $0.thumbnailData,
          hasDisplayData: $0.displayData.isNot(nil),
          mediaType: $0.mediaType,
          pixelWidth: $0.pixelWidth,
          pixelHeight: $0.pixelHeight,
          checksum: $0.checksum,
          kind: $0.kind,
          caption: $0.caption,
          source: $0.source,
          sortOrder: $0.sortOrder,
          dateCreated: $0.dateCreated
        )
      }
      .fetchAll(db)
      .map(\.detailPhoto)
    let source = try (RecipeSource.where { $0.recipeID.eq(recipeID) })
      .fetchOne(db)
    let recipeCategories = try (RecipeCategory.where { $0.recipeID.eq(recipeID) })
      .fetchAll(db)
    let recipeEquipment = try (RecipeEquipment.where { $0.recipeID.eq(recipeID) })
      .fetchAll(db)
    let variations = try (RecipeVariation.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortIndex }
      .fetchAll(db)
    let deliberationLogEntries = try (RecipeDeliberationLogEntry.where { $0.recipeID.eq(recipeID) })
      .order { $0.dateCreated.desc() }
      .fetchAll(db)
    let serveWith = try RecipeServeWith
      .where { $0.recipeID.eq(recipeID) }
      .fetchAll(db)
      .sorted(by: areServeWithInDisplayOrder)
    let activeVariationID = try activeVariationID(recipeID: recipeID, variations: variations, in: db)
    let allCategories = try CategoryRepository.visibleCategories(in: db)
    let categoriesByID = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })
    let categories = allCategories
      .filter { category in recipeCategories.contains { $0.categoryID == category.id } }
      .sorted { $0.sortOrder < $1.sortOrder }
    let categoryDisplayNames = categories.map {
      CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID)
    }
    let equipment = try Equipment.fetchAll(db)
      .filter { equipment in recipeEquipment.contains { $0.equipmentID == equipment.id } }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    let knownInstructionSectionIDs = Set(instructionSections.map(\.id))
    let orphanSteps = instructionSteps.filter { !knownInstructionSectionIDs.contains($0.sectionID) }
    if !orphanSteps.isEmpty {
      let orphanSectionIDs = Set(orphanSteps.map(\.sectionID))
        .map(\.uuidString)
        .sorted()
        .joined(separator: ",")
      AppLog.dataIntegrity.warning(
        "instruction-section-orphans recipeID=\(recipe.id.uuidString, privacy: .public) orphanStepCount=\(orphanSteps.count, privacy: .public) unknownSectionIDs=\(orphanSectionIDs, privacy: .public)"
      )
    }

    return RecipeDetailData(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines,
      instructionSections: instructionSections,
      instructionSteps: instructionSteps,
      notes: notes,
      photos: photos,
      categories: categories,
      categoryDisplayNames: categoryDisplayNames,
      equipment: equipment,
      recipeEquipment: recipeEquipment,
      learnings: try LearningRepository.learnings(sourceType: .recipe, sourceID: recipeID, in: db),
      serveWith: serveWith,
      variations: variations,
      deliberationLogEntries: deliberationLogEntries,
      activeVariationID: activeVariationID
    )
  }
}

extension RecipeRepository {
  @discardableResult
  public static func save(
    draft: RecipeEditorDraft,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Recipe.ID {
    var draft = draft
    // Most callers pass through the live editor, which promotes heading syntax as it is typed.
    // Normalize only flat, newly constructed cards here; persisted drafts already carry line identity,
    // including the small audited set of historical colon-terminated ingredient rows.
    for sectionID in draft.ingredientSections
      .filter(\.lineDrafts.isEmpty)
      .map(\.id) {
      _ = draft.ingredientTextChanged(sectionID: sectionID, uuid: uuid)
    }
    let recipeID = draft.id ?? uuid()
    let dateCreated = draft.dateCreated ?? now
    let existingDetail = try draft.id.flatMap { try fetchDetail(recipeID: $0, in: db) }
    // `existingDetail.photos` is now a slim projection with no `displayData` bytes
    // (ADR-0029 Amd2 S5b). The photo reconcile below must merge and re-write full
    // rows, so fetch the writable `RecipePhoto`s directly rather than reusing the
    // slim ones (which would null the image bytes on any retained row).
    let existingPhotos = try draft.id.flatMap { existingRecipeID in
      try RecipePhoto.where { $0.recipeID.eq(existingRecipeID) }.order { $0.sortOrder }.fetchAll(db)
    } ?? []
    let ingredientPlan = RecipeEditorSectionReconcile.ingredients(
      draftSections: draft.ingredientSections,
      existingSections: existingDetail?.ingredientSections ?? [],
      existingLines: existingDetail?.ingredientLines ?? [],
      recipeID: recipeID,
      uuid: uuid
    )
    let instructionPlan = RecipeEditorSectionReconcile.instructions(
      draftSections: draft.instructionSections,
      existingSections: existingDetail?.instructionSections ?? [],
      existingSteps: existingDetail?.instructionSteps ?? [],
      recipeID: recipeID,
      uuid: uuid
    )
    let generalNotes = reconcileGeneralNotes(
      draft.noteText,
      recipeID: recipeID,
      existing: existingDetail?.notes.filter { $0.noteType == .general } ?? [],
      now: now,
      uuid: uuid
    )

    let prepTimeMinutes: Int? = draft.prepTimeMinutes == 0 ? nil : draft.prepTimeMinutes
    let cookTimeMinutes: Int? = draft.cookTimeMinutes == 0 ? nil : draft.cookTimeMinutes
    let appliesEditableProseFields = draft.id == nil || draft.editsMakeAheadAndChefItUp
    var recipe = Recipe(
      id: recipeID,
      title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
      subtitle: draft.subtitle.nonEmpty,
      summary: draft.summary.nonEmpty,
      servings: ServingParser.servings(from: draft.servingsText),
      servingsText: draft.servingsText.nonEmpty,
      yieldText: draft.yieldText.nonEmpty,
      prepTimeMinutes: prepTimeMinutes,
      cookTimeMinutes: cookTimeMinutes,
      totalTimeMinutes: totalTime(prep: prepTimeMinutes, cook: cookTimeMinutes),
      cuisine: draft.cuisine.nonEmpty,
      course: draft.course.nonEmpty,
      favorite: draft.favorite,
      libraryPlacement: draft.libraryPlacement,
      dateCreated: dateCreated,
      dateModified: now,
      originalSnapshot: draft.originalSnapshot,
      makeAhead: appliesEditableProseFields ? draft.makeAhead.nonEmpty : existingDetail?.recipe.makeAhead,
      chefItUp: appliesEditableProseFields ? draft.chefItUp.nonEmpty : existingDetail?.recipe.chefItUp,
      serveWith: existingDetail?.recipe.serveWith,
      viewScale: existingDetail?.recipe.viewScale ?? 1.0,
      coverPhotoID: existingDetail?.recipe.coverPhotoID
    )
    let source = sourceFromDraft(
      draft,
      recipeID: recipeID,
      existingSource: existingDetail?.source,
      uuid: uuid
    )
    let snapshotIngredientSections = ingredientPlan.snapshotSections
    let snapshotIngredientLines = ingredientPlan.snapshotLines
    let snapshotInstructionSections = instructionPlan.snapshotSections
    let snapshotInstructionSteps = instructionPlan.snapshotSteps
    let snapshotNotes = (existingDetail?.notes.filter { $0.noteType != .general } ?? []) + generalNotes
    let photos = mergedPhotos(
      existingPhotos,
      pendingPhotos: draft.pendingPhotos,
      removesHeroPhoto: draft.removesHeroPhoto,
      recipeID: recipeID,
      now: now
    )
    let categoryNames = try categoryNames(from: draft, in: db)

    if recipe.originalSnapshot == nil {
      recipe.originalSnapshot = try RecipeBundleCoding.snapshotData(
        recipe: recipe,
        source: source,
        ingredientSections: snapshotIngredientSections,
        ingredientLines: snapshotIngredientLines,
        instructionSections: snapshotInstructionSections,
        instructionSteps: snapshotInstructionSteps,
        notes: snapshotNotes,
        tagNames: [],
        categoryNames: categoryNames,
        photos: photos,
        equipment: existingDetail?.equipment ?? [],
        recipeEquipment: existingDetail?.recipeEquipment ?? []
      )
    }

    try upsert(recipe, in: db)
    try replaceSource(source, recipeID: recipeID, in: db)
    try saveEditableChildren(
      recipeID: recipeID,
      ingredientPlan: ingredientPlan,
      existingIngredientLines: existingDetail?.ingredientLines ?? [],
      instructionPlan: instructionPlan,
      existingInstructionSteps: existingDetail?.instructionSteps ?? [],
      generalNotes: generalNotes,
      existingGeneralNotes: existingDetail?.notes.filter { $0.noteType == .general } ?? [],
      in: db
    )
    try reconcileCategories(from: draft, recipeID: recipeID, in: db, now: now, uuid: uuid)
    try reconcilePhotos(photos, existingPhotos: existingPhotos, in: db)

    return recipeID
  }

  public static func archive(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try #sql("DELETE FROM \"mealPlanItems\" WHERE \"recipeID\" = \(bind: recipeID)")
      .execute(db)
    try #sql("DELETE FROM \"menuItems\" WHERE \"recipeID\" = \(bind: recipeID)")
      .execute(db)
    try Recipe.find(recipeID).update {
      $0.archived = true
      $0.dateModified = now
    }
    .execute(db)
  }

  public static func restore(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try Recipe.find(recipeID).update {
      $0.archived = false
      $0.dateModified = now
    }
    .execute(db)
  }

  public static func setLibraryPlacement(
    _ libraryPlacement: RecipeLibraryPlacement,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try Recipe.find(recipeID).update {
      $0.libraryPlacement = libraryPlacement
      $0.dateModified = now
    }
    .execute(db)
  }

  public static func setCoverPhotoID(
    _ coverPhotoID: RecipePhoto.ID?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try Recipe.find(recipeID).update {
      $0.coverPhotoID = coverPhotoID
      $0.dateModified = now
    }
    .execute(db)
  }

  public static func permanentlyDelete(recipeID: Recipe.ID, in db: Database) throws {
    try Recipe.find(recipeID).delete().execute(db)
  }

  private static func categoryNames(from draft: RecipeEditorDraft, in db: Database) throws -> [String] {
    guard let selectedCategoryIDs = draft.selectedCategoryIDs else {
      return distinctCategoryNames(draft.categoryNames.listNames + draft.tagNames.listNames)
    }
    let categories = CategoryRepository.sortedCategories(try CategoryRepository.visibleCategories(in: db))
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    return categories
      .filter { selectedCategoryIDs.contains($0.id) }
      .map { CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID) }
  }

  private static func reconcileCategories(
    from draft: RecipeEditorDraft,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    if let selectedCategoryIDs = draft.selectedCategoryIDs {
      try reconcileCategoryIDs(Array(selectedCategoryIDs), recipeID: recipeID, in: db, uuid: uuid)
    } else {
      try reconcileCategories(
        distinctCategoryNames(draft.categoryNames.listNames),
        looseNames: distinctCategoryNames(draft.tagNames.listNames),
        recipeID: recipeID,
        in: db,
        now: now,
        uuid: uuid
      )
    }
  }

  private static func distinctCategoryNames(_ names: [String]) -> [String] {
    var seen: Set<String> = []
    return names.filter { name in
      seen.insert(name.normalizedLogicalName).inserted
    }
  }

  private static func upsert(_ recipe: Recipe, in db: Database) throws {
    try Recipe.upsert { recipe }.execute(db)
  }

  private static func sourceFromDraft(
    _ draft: RecipeEditorDraft,
    recipeID: Recipe.ID,
    existingSource: RecipeSource?,
    uuid: () -> UUID
  ) -> RecipeSource? {
    guard draft.hasSourceData else { return nil }
    return RecipeSource(
      id: existingSource?.id ?? uuid(),
      recipeID: recipeID,
      name: draft.sourceName.nonEmpty,
      url: draft.sourceURL.nonEmpty,
      author: draft.sourceAuthor.nonEmpty,
      publicationName: draft.sourcePublicationName.nonEmpty,
      bookTitle: draft.sourceBookTitle.nonEmpty,
      pageNumber: draft.sourcePageNumber.nonEmpty,
      importedFrom: existingSource?.importedFrom,
      dateImported: existingSource?.dateImported,
      sourceNotes: draft.sourceNotes.nonEmpty
    )
  }

  static func replaceSource(_ source: RecipeSource?, recipeID: Recipe.ID, in db: Database) throws {
    guard let source else {
      try #sql("DELETE FROM \"recipeSources\" WHERE \"recipeID\" = \(bind: recipeID)")
        .execute(db)
      return
    }

    try #sql("""
      DELETE FROM "recipeSources"
      WHERE "recipeID" = \(bind: recipeID)
        AND "id" != \(bind: source.id)
      """)
      .execute(db)
    try RecipeSource.upsert { source }.execute(db)
  }

  private static func saveEditableChildren(
    recipeID: Recipe.ID,
    ingredientPlan: RecipeEditorSectionReconcile.IngredientPlan,
    existingIngredientLines: [IngredientLine],
    instructionPlan: RecipeEditorSectionReconcile.InstructionPlan,
    existingInstructionSteps: [InstructionStep],
    generalNotes: [RecipeNote],
    existingGeneralNotes: [RecipeNote],
    in db: Database
  ) throws {
    for section in ingredientPlan.sections {
      try IngredientSection.upsert { section }.execute(db)
      let lines = ingredientPlan.linesBySectionID[section.id] ?? []
      for line in lines {
        try IngredientLine.upsert { line }.execute(db)
      }
    }
    // A draft line may have moved to a newly minted section. Delete only after every upsert, and
    // consider identity across the whole recipe rather than the line's former section.
    try deleteMissingRows(
      existingIngredientLines,
      keeping: Set(ingredientPlan.snapshotLines.map(\.id)),
      in: db
    )
    for sectionID in ingredientPlan.removedSectionIDs {
      try #sql("DELETE FROM \"ingredientSections\" WHERE \"id\" = \(bind: sectionID)").execute(db)
    }

    let existingInstructionStepsBySection = Dictionary(grouping: existingInstructionSteps, by: \.sectionID)
    for section in instructionPlan.sections {
      try InstructionSection.upsert { section }.execute(db)
      let steps = instructionPlan.stepsBySectionID[section.id] ?? []
      for step in steps {
        try InstructionStep.upsert { step }.execute(db)
      }
      try deleteMissingRows(
        existingInstructionStepsBySection[section.id] ?? [],
        keeping: Set(steps.map(\.id)),
        in: db
      )
    }
    for sectionID in instructionPlan.removedSectionIDs {
      try deleteMissingRows(existingInstructionStepsBySection[sectionID] ?? [], keeping: [], in: db)
      try #sql("DELETE FROM \"instructionSections\" WHERE \"id\" = \(bind: sectionID)").execute(db)
    }

    for note in generalNotes {
      try insert(note, in: db)
    }
    try deleteMissingRows(existingGeneralNotes, keeping: Set(generalNotes.map(\.id)), in: db)

    _ = recipeID
  }

  private static func insert(_ note: RecipeNote, in db: Database) throws {
    try RecipeNote.upsert { note }.execute(db)
  }

  static func reconcileInstructionSteps(
    _ parsedSteps: [InstructionStep],
    existing existingSteps: [InstructionStep]
  ) -> [InstructionStep] {
    var unmatchedExistingSteps = existingSteps.sorted { $0.sortOrder < $1.sortOrder }
    return parsedSteps.map { parsedStep in
      guard let matchIndex = unmatchedExistingSteps.firstIndex(where: { $0.text == parsedStep.text })
      else { return parsedStep }

      let existingStep = unmatchedExistingSteps.remove(at: matchIndex)
      return InstructionStep(
        id: existingStep.id,
        recipeID: parsedStep.recipeID,
        sectionID: parsedStep.sectionID,
        text: parsedStep.text,
        sortOrder: parsedStep.sortOrder,
        isOptional: existingStep.isOptional
      )
    }
  }

  private static func reconcileGeneralNotes(
    _ text: String,
    recipeID: Recipe.ID,
    existing existingNotes: [RecipeNote],
    now: Date,
    uuid: () -> UUID
  ) -> [RecipeNote] {
    var unmatchedExistingNotes = existingNotes.sorted { $0.dateCreated < $1.dateCreated }
    return text.noteParagraphs.map { paragraph in
      let noteID: RecipeNote.ID
      let dateCreated: Date
      if let matchIndex = unmatchedExistingNotes.firstIndex(where: { $0.text == paragraph }) {
        let existingNote = unmatchedExistingNotes.remove(at: matchIndex)
        noteID = existingNote.id
        dateCreated = existingNote.dateCreated
      } else {
        noteID = uuid()
        dateCreated = now
      }
      return RecipeNote(
        id: noteID,
        recipeID: recipeID,
        text: paragraph,
        noteType: .general,
        dateCreated: dateCreated,
        dateModified: now
      )
    }
  }

  private static func deleteMissingRows(
    _ rows: [IngredientLine],
    keeping keptIDs: Set<IngredientLine.ID>,
    in db: Database
  ) throws {
    for row in rows where !keptIDs.contains(row.id) {
      try #sql("DELETE FROM \"ingredientLines\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }

  private static func deleteMissingRows(
    _ rows: [InstructionStep],
    keeping keptIDs: Set<InstructionStep.ID>,
    in db: Database
  ) throws {
    for row in rows where !keptIDs.contains(row.id) {
      try #sql("DELETE FROM \"instructionSteps\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }

  private static func deleteMissingRows(
    _ rows: [RecipeNote],
    keeping keptIDs: Set<RecipeNote.ID>,
    in db: Database
  ) throws {
    for row in rows where !keptIDs.contains(row.id) {
      try #sql("DELETE FROM \"recipeNotes\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }

  private static func totalTime(prep: Int?, cook: Int?) -> Int? {
    switch (prep, cook) {
    case let (prep?, cook?): prep + cook
    case let (prep?, nil): prep
    case let (nil, cook?): cook
    case (nil, nil): nil
    }
  }
}

public enum InstructionParser {
  public static func steps(
    from text: String,
    recipeID: Recipe.ID,
    sectionID: InstructionSection.ID,
    uuid: () -> UUID
  ) -> [InstructionStep] {
    text
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .enumerated()
      .map { index, text in
        InstructionStep(
          id: uuid(),
          recipeID: recipeID,
          sectionID: sectionID,
          text: text,
          sortOrder: index
        )
      }
  }
}

public enum IngredientScaler {
  public static func scaledText(for line: IngredientLine, factor: Double) -> String {
    guard
      let quantity = line.quantity,
      factor != 1
    else { return line.originalText }

    let scaledQuantity = formattedQuantity(quantity * factor)
    return replacingLeadingMeasure(
      in: line.originalText,
      quantityText: line.quantityText,
      unit: line.unit,
      scaledQuantity: scaledQuantity,
      scaledValue: quantity * factor
    ) ?? line.originalText
  }

  private static func replacingLeadingMeasure(
    in originalText: String,
    quantityText: String?,
    unit: String?,
    scaledQuantity: String,
    scaledValue: Double
  ) -> String? {
    guard let quantityText else { return nil }

    let leadingWhitespace = originalText.prefix(while: \.isWhitespace)
    let remainingText = originalText.dropFirst(leadingWhitespace.count)
    guard remainingText.hasPrefix(quantityText) else { return nil }

    var suffix = remainingText.dropFirst(quantityText.count)
    guard let unit else {
      return "\(leadingWhitespace)\(scaledQuantity)\(suffix)"
    }

    let whitespace = suffix.prefix(while: \.isWhitespace)
    guard !whitespace.isEmpty else { return nil }
    suffix = suffix.dropFirst(whitespace.count)
    guard String(suffix.prefix(unit.count)).caseInsensitiveCompare(unit) == .orderedSame else {
      return nil
    }
    suffix = suffix.dropFirst(unit.count)
    guard suffix.first?.isLetter != true else { return nil }

    return "\(leadingWhitespace)\(scaledQuantity) \(pluralized(unit, quantity: scaledValue))\(suffix)"
  }

  public static func formattedQuantity(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(value - rounded) < 0.01 {
      return "\(Int(rounded))"
    }

    let whole = Int(value.rounded(.down))
    let fractionValue = value - Double(whole)
    if let fraction = commonFractions.min(by: { lhs, rhs in
      abs(lhs.value - fractionValue) < abs(rhs.value - fractionValue)
    }), abs(fraction.value - fractionValue) < 0.01 {
      if whole == 0 {
        return fraction.label
      }
      return "\(whole) \(fraction.label)"
    }

    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private static func pluralized(_ unit: String, quantity: Double) -> String {
    guard quantity != 1, !unit.hasSuffix("s") else { return unit }
    return unit + "s"
  }

  private static let commonFractions: [(value: Double, label: String)] = [
    (1.0 / 8.0, "⅛"),
    (1.0 / 6.0, "⅙"),
    (1.0 / 5.0, "⅕"),
    (1.0 / 4.0, "¼"),
    (1.0 / 3.0, "⅓"),
    (3.0 / 8.0, "⅜"),
    (2.0 / 5.0, "⅖"),
    (1.0 / 2.0, "½"),
    (3.0 / 5.0, "⅗"),
    (5.0 / 8.0, "⅝"),
    (2.0 / 3.0, "⅔"),
    (3.0 / 4.0, "¾"),
    (4.0 / 5.0, "⅘"),
    (5.0 / 6.0, "⅚"),
    (7.0 / 8.0, "⅞"),
  ]
}

public enum RecipeYieldScaler {
  /// Scales the yield/servings number in place, keeping the recipe's own phrasing: "Serves 2" at 3×
  /// reads "Serves 6", not "6 servings".
  ///
  /// Uses `firstQuantity`, not `leadingQuantity`. Anchoring at the start of the string meant every
  /// phrasing that leads with a word — "Serves 2", "Makes 4 dozen", "Yield: 6" — returned nil and
  /// scaled to nothing at all, silently, while "4–6 servings" scaled fine.
  public static func scaledText(_ text: String?, factor: Double) -> String? {
    guard let text, factor != 1, let quantity = QuantityParser.firstQuantity(in: text) else {
      return text
    }

    let scaledQuantityText: String
    if let upperBound = quantity.upperBound {
      scaledQuantityText = "\(IngredientScaler.formattedQuantity(quantity.value * factor))–\(IngredientScaler.formattedQuantity(upperBound * factor))"
    } else {
      scaledQuantityText = IngredientScaler.formattedQuantity(quantity.value * factor)
    }

    return String(text[..<quantity.range.lowerBound])
      + scaledQuantityText
      + String(text[quantity.range.upperBound...])
  }
}

public enum ServingParser {
  public static func servings(from text: String) -> Double? {
    let tokens = text.split(whereSeparator: \.isWhitespace)
    for index in tokens.indices {
      if let servings = QuantityParser.leadingValue(in: tokens[index...].joined(separator: " ")) {
        return servings
      }
    }
    return nil
  }
}

private extension String {
  var normalizedLogicalName: String {
    folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var listNames: [String] {
    split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var noteParagraphs: [String] {
    components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

func reconcileIngredientLines(
  _ parsedLines: [IngredientLine],
  drafts: [RecipeIngredientLineDraft],
  existingByID: [IngredientLine.ID: IngredientLine]
) -> [IngredientLine] {
  var unmatchedDrafts = drafts.sorted { $0.sortOrder < $1.sortOrder }
  return parsedLines.map { parsedLine in
    guard let matchIndex = unmatchedDrafts.firstIndex(where: {
      $0.originalText == parsedLine.originalText && $0.sortOrder == parsedLine.sortOrder
    }) ?? unmatchedDrafts.firstIndex(where: { $0.originalText == parsedLine.originalText })
    else { return parsedLine }

    let draft = unmatchedDrafts.remove(at: matchIndex)
    guard let existingLine = existingByID[draft.id] else {
      return IngredientLine(
        id: draft.id,
        recipeID: parsedLine.recipeID,
        sectionID: parsedLine.sectionID,
        originalText: parsedLine.originalText,
        quantity: parsedLine.quantity,
        quantityText: parsedLine.quantityText,
        unit: parsedLine.unit,
        item: parsedLine.item,
        canonicalName: parsedLine.canonicalName,
        preparation: parsedLine.preparation,
        comment: parsedLine.comment,
        isOptional: parsedLine.isOptional,
        shoppingCategory: parsedLine.shoppingCategory,
        doNotShop: parsedLine.doNotShop,
        isHeader: parsedLine.isHeader,
        sortOrder: parsedLine.sortOrder,
        confidence: parsedLine.confidence
      )
    }
    return IngredientLine(
      id: draft.id,
      recipeID: parsedLine.recipeID,
      sectionID: parsedLine.sectionID,
      originalText: parsedLine.originalText,
      quantity: parsedLine.quantity ?? existingLine.quantity,
      quantityText: parsedLine.quantityText ?? existingLine.quantityText,
      unit: parsedLine.unit ?? existingLine.unit,
      item: parsedLine.item ?? existingLine.item,
      // The stored canonical name is the durable grocery key. Parsing may improve the readable
      // ingredient fields, but cannot silently replace a classification a cook has already kept.
      canonicalName: existingLine.canonicalName
        ?? parsedLine.canonicalName
        ?? CanonicalIngredient.canonicalName((parsedLine.item ?? existingLine.item) ?? parsedLine.originalText),
      preparation: parsedLine.preparation ?? existingLine.preparation,
      comment: parsedLine.comment ?? existingLine.comment,
      isOptional: parsedLine.isOptional,
      shoppingCategory: existingLine.shoppingCategory,
      doNotShop: parsedLine.doNotShop || existingLine.doNotShop,
      // Historical header rows remain readable until Jon repairs the small audited set by hand.
      // New lines are produced with the model default (`false`); the editor no longer writes this flag.
      isHeader: existingLine.isHeader,
      sortOrder: parsedLine.sortOrder,
      confidence: mergedConfidence(parsedLine.confidence, existingLine.confidence)
    )
  }
}

private func mergedConfidence(
  _ parsedConfidence: ParseConfidence?,
  _ existingConfidence: ParseConfidence?
) -> ParseConfidence? {
  switch parsedConfidence {
  case .high, .medium:
    parsedConfidence
  case .low, nil:
    existingConfidence ?? parsedConfidence
  }
}

private extension RecipeEditorDraft {
  var hasSourceData: Bool {
    sourceName.nonEmpty != nil
      || sourceURL.nonEmpty != nil
      || sourceAuthor.nonEmpty != nil
      || sourcePublicationName.nonEmpty != nil
      || sourceBookTitle.nonEmpty != nil
      || sourcePageNumber.nonEmpty != nil
      || sourceNotes.nonEmpty != nil
  }
}
