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
  public var tags: [Tag]
  public var categories: [Category]
  public var categoryDisplayNames: [String]
  public var equipment: [Equipment]
  public var recipeEquipment: [RecipeEquipment]
  public var variations: [RecipeVariation]
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
    tags: [Tag] = [],
    categories: [Category] = [],
    categoryDisplayNames: [String] = [],
    equipment: [Equipment] = [],
    recipeEquipment: [RecipeEquipment] = [],
    variations: [RecipeVariation] = [],
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
    self.tags = tags
    self.categories = categories
    self.categoryDisplayNames = categoryDisplayNames
    self.equipment = equipment
    self.recipeEquipment = recipeEquipment
    self.variations = variations
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
    let recipeTags = try (RecipeTag.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .fetchAll(db)
    let recipeCategories = try (RecipeCategory.where { $0.recipeID.eq(recipeID) })
      .fetchAll(db)
    let recipeEquipment = try (RecipeEquipment.where { $0.recipeID.eq(recipeID) })
      .fetchAll(db)
    let variations = try (RecipeVariation.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortIndex }
      .fetchAll(db)
    let activeVariationID = try activeVariationID(recipeID: recipeID, variations: variations, in: db)
    let tags = try Tag.fetchAll(db)
      .filter { tag in recipeTags.contains { $0.tagID == tag.id } }
      .sorted { lhs, rhs in
        let lhsOrder = recipeTags.first { $0.tagID == lhs.id }?.sortOrder ?? 0
        let rhsOrder = recipeTags.first { $0.tagID == rhs.id }?.sortOrder ?? 0
        return lhsOrder < rhsOrder
      }
    let allCategories = try Category.fetchAll(db)
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

    return RecipeDetailData(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines,
      instructionSections: instructionSections,
      instructionSteps: instructionSteps,
      notes: notes,
      photos: photos,
      tags: tags,
      categories: categories,
      categoryDisplayNames: categoryDisplayNames,
      equipment: equipment,
      recipeEquipment: recipeEquipment,
      variations: variations,
      activeVariationID: activeVariationID
    )
  }

  @discardableResult
  public static func save(
    draft: RecipeEditorDraft,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Recipe.ID {
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
    let existingIngredientSection = existingDetail?.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }.first
    let existingInstructionSection = existingDetail?.instructionSections.sorted { $0.sortOrder < $1.sortOrder }.first
    let ingredientSection = existingIngredientSection
      ?? IngredientSection(id: uuid(), recipeID: recipeID, name: nil, sortOrder: 0)
    var editableIngredientSection = ingredientSection
    editableIngredientSection.name = draft.ingredientSectionName.nonEmpty
    let instructionSection = existingInstructionSection
      ?? InstructionSection(id: uuid(), recipeID: recipeID, name: nil, sortOrder: 0)
    let ingredientLines = IngredientParser.lines(
      from: draft.ingredientText,
      recipeID: recipeID,
      sectionID: editableIngredientSection.id,
      uuid: uuid
    )
    let reconciledIngredientLines = applyIngredientLineDrafts(
      draft.ingredientLineDrafts,
      to: reconcileIngredientLines(
        ingredientLines,
        existing: existingDetail?.ingredientLines.filter { $0.sectionID == editableIngredientSection.id } ?? []
      )
    )
    let instructionSteps = InstructionParser.steps(
      from: draft.instructionText,
      recipeID: recipeID,
      sectionID: instructionSection.id,
      uuid: uuid
    )
    let reconciledInstructionSteps = reconcileInstructionSteps(
      instructionSteps,
      existing: existingDetail?.instructionSteps.filter { $0.sectionID == instructionSection.id } ?? []
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
    let snapshotIngredientSections = mergedSections(
      existingDetail?.ingredientSections ?? [],
      replacing: editableIngredientSection
    )
    let snapshotIngredientLines = mergedIngredientLines(
      existingDetail?.ingredientLines ?? [],
      replacingSectionID: editableIngredientSection.id,
      with: reconciledIngredientLines
    )
    let snapshotInstructionSections = mergedSections(
      existingDetail?.instructionSections ?? [],
      replacing: instructionSection
    )
    let snapshotInstructionSteps = mergedInstructionSteps(
      existingDetail?.instructionSteps ?? [],
      replacingSectionID: instructionSection.id,
      with: reconciledInstructionSteps
    )
    let snapshotNotes = (existingDetail?.notes.filter { $0.noteType != .general } ?? []) + generalNotes
    let photos = mergedPhotos(
      existingPhotos,
      pendingPhotos: draft.pendingPhotos,
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
        tagNames: draft.tagNames.listNames,
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
      ingredientSection: editableIngredientSection,
      ingredientLines: reconciledIngredientLines,
      existingIngredientLines: existingDetail?.ingredientLines.filter { $0.sectionID == editableIngredientSection.id } ?? [],
      instructionSection: instructionSection,
      instructionSteps: reconciledInstructionSteps,
      existingInstructionSteps: existingDetail?.instructionSteps.filter { $0.sectionID == instructionSection.id } ?? [],
      generalNotes: generalNotes,
      existingGeneralNotes: existingDetail?.notes.filter { $0.noteType == .general } ?? [],
      in: db
    )
    try reconcileTags(draft.tagNames.listNames, recipeID: recipeID, in: db, now: now, uuid: uuid)
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
      return draft.categoryNames.listNames
    }
    let categories = CategoryRepository.sortedCategories(try Category.fetchAll(db))
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
      try reconcileCategories(draft.categoryNames.listNames, recipeID: recipeID, in: db, now: now, uuid: uuid)
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
    ingredientSection: IngredientSection,
    ingredientLines: [IngredientLine],
    existingIngredientLines: [IngredientLine],
    instructionSection: InstructionSection,
    instructionSteps: [InstructionStep],
    existingInstructionSteps: [InstructionStep],
    generalNotes: [RecipeNote],
    existingGeneralNotes: [RecipeNote],
    in db: Database
  ) throws {
    try IngredientSection.upsert { ingredientSection }.execute(db)

    for line in ingredientLines {
      try IngredientLine.upsert { line }.execute(db)
    }
    try deleteMissingRows(existingIngredientLines, keeping: Set(ingredientLines.map(\.id)), in: db)

    try InstructionSection.upsert { instructionSection }.execute(db)

    for step in instructionSteps {
      try InstructionStep.upsert { step }.execute(db)
    }
    try deleteMissingRows(existingInstructionSteps, keeping: Set(instructionSteps.map(\.id)), in: db)

    for note in generalNotes {
      try insert(note, in: db)
    }
    try deleteMissingRows(existingGeneralNotes, keeping: Set(generalNotes.map(\.id)), in: db)

    if ingredientLines.isEmpty {
      try #sql("DELETE FROM \"ingredientSections\" WHERE \"id\" = \(bind: ingredientSection.id)").execute(db)
    }
    if instructionSteps.isEmpty {
      try #sql("DELETE FROM \"instructionSections\" WHERE \"id\" = \(bind: instructionSection.id)").execute(db)
    }

    _ = recipeID
  }

  private static func insert(_ note: RecipeNote, in db: Database) throws {
    try RecipeNote.upsert { note }.execute(db)
  }

  static func reconcileTags(
    _ names: [String],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    var existingTags = try Tag.fetchAll(db)
    try reconcileDuplicateTags(in: db, tags: &existingTags)
    let existingRecipeTags = try RecipeTag.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    var keptRecipeTagIDs: Set<RecipeTag.ID> = []

    for (index, name) in names.enumerated() {
      let tag = existingTags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        ?? Tag(id: uuid(), name: name, color: nil, sortOrder: existingTags.count, dateCreated: now)
      if !existingTags.contains(where: { $0.id == tag.id }) {
        try Tag.insert { tag }.execute(db)
        existingTags.append(tag)
      }
      let recipeTag = RecipeTag(
        id: existingRecipeTags.first { $0.tagID == tag.id }?.id ?? uuid(),
        recipeID: recipeID,
        tagID: tag.id,
        sortOrder: index
      )
      keptRecipeTagIDs.insert(recipeTag.id)
      try RecipeTag.upsert { recipeTag }.execute(db)
    }

    try deleteMissingRows(existingRecipeTags, keeping: keptRecipeTagIDs, in: db)
  }

  private static func reconcileInstructionSteps(
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

  private static func mergedSections(
    _ sections: [IngredientSection],
    replacing section: IngredientSection
  ) -> [IngredientSection] {
    (sections.filter { $0.id != section.id } + [section])
      .sorted { $0.sortOrder < $1.sortOrder }
  }

  private static func mergedSections(
    _ sections: [InstructionSection],
    replacing section: InstructionSection
  ) -> [InstructionSection] {
    (sections.filter { $0.id != section.id } + [section])
      .sorted { $0.sortOrder < $1.sortOrder }
  }

  private static func mergedIngredientLines(
    _ lines: [IngredientLine],
    replacingSectionID sectionID: IngredientSection.ID,
    with replacementLines: [IngredientLine]
  ) -> [IngredientLine] {
    (lines.filter { $0.sectionID != sectionID } + replacementLines)
      .sorted { lhs, rhs in
        if lhs.sectionID == rhs.sectionID {
          lhs.sortOrder < rhs.sortOrder
        } else {
          lhs.sectionID.uuidString < rhs.sectionID.uuidString
        }
      }
  }

  private static func mergedInstructionSteps(
    _ steps: [InstructionStep],
    replacingSectionID sectionID: InstructionSection.ID,
    with replacementSteps: [InstructionStep]
  ) -> [InstructionStep] {
    (steps.filter { $0.sectionID != sectionID } + replacementSteps)
      .sorted { lhs, rhs in
        if lhs.sectionID == rhs.sectionID {
          lhs.sortOrder < rhs.sortOrder
        } else {
          lhs.sectionID.uuidString < rhs.sectionID.uuidString
        }
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

  private static func deleteMissingRows(
    _ rows: [RecipeTag],
    keeping keptIDs: Set<RecipeTag.ID>,
    in db: Database
  ) throws {
    for row in rows where !keptIDs.contains(row.id) {
      try #sql("DELETE FROM \"recipeTags\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }

  private static func reconcileDuplicateTags(
    in db: Database,
    tags: inout [Tag]
  ) throws {
    let groups = Dictionary(grouping: tags, by: { $0.name.normalizedLogicalName })
    for group in groups.values where group.count > 1 {
      let sortedGroup = group.sorted(by: areTagsInCanonicalOrder)
      guard let canonicalTag = sortedGroup.first else { continue }
      let duplicateTags = sortedGroup.dropFirst()
      let duplicateTagIDs = Set(duplicateTags.map(\.id))

      for var recipeTag in try RecipeTag.fetchAll(db) where duplicateTagIDs.contains(recipeTag.tagID) {
        let hasCanonicalRecipeTag = try RecipeTag.fetchAll(db).contains {
          $0.recipeID == recipeTag.recipeID && $0.tagID == canonicalTag.id
        }
        if hasCanonicalRecipeTag {
          try RecipeTag.find(recipeTag.id).delete().execute(db)
        } else {
          recipeTag.tagID = canonicalTag.id
          try RecipeTag.upsert { recipeTag }.execute(db)
        }
      }

      for tag in duplicateTags {
        try Tag.find(tag.id).delete().execute(db)
      }
    }

    tags = try Tag.fetchAll(db)
  }

  private static func areTagsInCanonicalOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
    if lhs.dateCreated != rhs.dateCreated {
      return lhs.dateCreated < rhs.dateCreated
    }
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
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
      let item = line.item,
      factor != 1
    else { return line.originalText }

    let scaledQuantity = format(quantity * factor)
    guard let unit = line.unit else {
      return "\(scaledQuantity) \(item)"
    }
    return "\(scaledQuantity) \(pluralized(unit, quantity: quantity * factor)) \(item)"
  }

  private static func format(_ value: Double) -> String {
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

public enum ServingParser {
  public static func servings(from text: String) -> Double? {
    text
      .split(separator: " ")
      .lazy
      .compactMap { Double($0) }
      .first
  }
}

public enum RecipeBundleCoding {
  public struct RecipeBundle: Codable, Equatable, Sendable {
    public var version: Int
    public var recipe: Recipe
    public var source: RecipeSource?
    public var ingredientSections: [IngredientSection]
    public var ingredientLines: [IngredientLine]
    public var instructionSections: [InstructionSection]
    public var instructionSteps: [InstructionStep]
    public var recipeNotes: [RecipeNote]
    public var photos: [RecipePhoto]
    public var tagNames: [String]
    public var categoryNames: [String]
    public var equipment: [Equipment]
    public var recipeEquipment: [RecipeEquipment]

    public init(
      version: Int = 1,
      recipe: Recipe,
      source: RecipeSource? = nil,
      ingredientSections: [IngredientSection] = [],
      ingredientLines: [IngredientLine] = [],
      instructionSections: [InstructionSection] = [],
      instructionSteps: [InstructionStep] = [],
      recipeNotes: [RecipeNote] = [],
      photos: [RecipePhoto] = [],
      tagNames: [String] = [],
      categoryNames: [String] = [],
      equipment: [Equipment] = [],
      recipeEquipment: [RecipeEquipment] = []
    ) {
      self.version = version
      self.recipe = recipe
      self.source = source
      self.ingredientSections = ingredientSections
      self.ingredientLines = ingredientLines
      self.instructionSections = instructionSections
      self.instructionSteps = instructionSteps
      self.recipeNotes = recipeNotes
      self.photos = photos
      self.tagNames = tagNames
      self.categoryNames = categoryNames
      self.equipment = equipment
      self.recipeEquipment = recipeEquipment
    }

    public var ingredients: [String] {
      ingredientLines.sorted { $0.sortOrder < $1.sortOrder }.map(\.originalText)
    }

    public var instructions: [String] {
      instructionSteps.sorted { $0.sortOrder < $1.sortOrder }.map(\.text)
    }

    public var notes: [String] {
      recipeNotes.sorted { $0.dateCreated < $1.dateCreated }.map(\.text)
    }

    public var tags: [String] {
      tagNames
    }

    public var categories: [String] {
      categoryNames
    }
  }

  public typealias Snapshot = RecipeBundle

  public static func snapshotData(
    recipe: Recipe,
    source: RecipeSource?,
    ingredientSections: [IngredientSection],
    ingredientLines: [IngredientLine],
    instructionSections: [InstructionSection],
    instructionSteps: [InstructionStep],
    notes: [RecipeNote],
    tagNames: [String],
    categoryNames: [String],
    photos: [RecipePhoto] = [],
    equipment: [Equipment] = [],
    recipeEquipment: [RecipeEquipment] = []
  ) throws -> Data {
    var recipe = recipe
    recipe.originalImportText = nil
    let snapshot = RecipeBundle(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines.sorted { $0.sortOrder < $1.sortOrder },
      instructionSections: instructionSections,
      instructionSteps: instructionSteps.sorted { $0.sortOrder < $1.sortOrder },
      recipeNotes: notes.sorted { $0.dateCreated < $1.dateCreated },
      photos: leanSnapshotPhotos(photos),
      tagNames: tagNames,
      categoryNames: categoryNames,
      equipment: equipment,
      recipeEquipment: recipeEquipment
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(snapshot)
  }

  public static func decodeSnapshot(_ data: Data) throws -> RecipeBundle {
    try JSONDecoder().decode(RecipeBundle.self, from: data)
  }

  private static func leanSnapshotPhotos(_ photos: [RecipePhoto]) -> [RecipePhoto] {
    photos
      .sorted { $0.sortOrder < $1.sortOrder }
      .map { photo in
        var photo = photo
        photo.displayData = nil
        photo.thumbnailData = nil
        return photo
      }
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

private func applyIngredientLineDrafts(
  _ drafts: [RecipeIngredientLineDraft],
  to lines: [IngredientLine]
) -> [IngredientLine] {
  var unmatchedDrafts = drafts.sorted { $0.sortOrder < $1.sortOrder }
  return lines.map { line in
    var line = line
    let matchIndex = unmatchedDrafts.firstIndex { draft in
      draft.id == line.id
        || (draft.originalText == line.originalText && draft.sortOrder == line.sortOrder)
    }
    guard let matchIndex else { return line }
    let draft = unmatchedDrafts.remove(at: matchIndex)
    line.isHeader = draft.isHeader
    return line
  }
}

private func reconcileIngredientLines(
  _ parsedLines: [IngredientLine],
  existing existingLines: [IngredientLine]
) -> [IngredientLine] {
  var unmatchedExistingLines = existingLines.sorted { $0.sortOrder < $1.sortOrder }
  return parsedLines.map { parsedLine in
    guard let matchIndex = unmatchedExistingLines.firstIndex(where: { $0.originalText == parsedLine.originalText })
    else { return parsedLine }

    let existingLine = unmatchedExistingLines.remove(at: matchIndex)
    return IngredientLine(
      id: existingLine.id,
      recipeID: parsedLine.recipeID,
      sectionID: parsedLine.sectionID,
      originalText: parsedLine.originalText,
      quantity: parsedLine.quantity ?? existingLine.quantity,
      quantityText: parsedLine.quantityText ?? existingLine.quantityText,
      unit: parsedLine.unit ?? existingLine.unit,
      item: parsedLine.item ?? existingLine.item,
      canonicalName: parsedLine.canonicalName
        ?? existingLine.canonicalName
        ?? CanonicalIngredient.canonicalName((parsedLine.item ?? existingLine.item) ?? parsedLine.originalText),
      preparation: parsedLine.preparation ?? existingLine.preparation,
      comment: parsedLine.comment ?? existingLine.comment,
      isOptional: parsedLine.isOptional,
      shoppingCategory: existingLine.shoppingCategory,
      doNotShop: parsedLine.doNotShop || existingLine.doNotShop,
      isHeader: parsedLine.isHeader,
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
