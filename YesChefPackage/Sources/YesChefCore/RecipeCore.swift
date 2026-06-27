import Foundation
import SQLiteData

public struct RecipeDetailData: Equatable, Sendable {
  public var recipe: Recipe
  public var source: RecipeSource?
  public var ingredientSections: [IngredientSection]
  public var ingredientLines: [IngredientLine]
  public var instructionSections: [InstructionSection]
  public var instructionSteps: [InstructionStep]
  public var notes: [RecipeNote]
  public var photos: [RecipePhoto]
  public var tags: [Tag]
  public var categories: [Category]
  public var categoryDisplayNames: [String]
  public var equipment: [Equipment]
  public var recipeEquipment: [RecipeEquipment]

  public init(
    recipe: Recipe,
    source: RecipeSource? = nil,
    ingredientSections: [IngredientSection] = [],
    ingredientLines: [IngredientLine] = [],
    instructionSections: [InstructionSection] = [],
    instructionSteps: [InstructionStep] = [],
    notes: [RecipeNote] = [],
    photos: [RecipePhoto] = [],
    tags: [Tag] = [],
    categories: [Category] = [],
    categoryDisplayNames: [String] = [],
    equipment: [Equipment] = [],
    recipeEquipment: [RecipeEquipment] = []
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
  }
}

public struct RecipeDetailRequest: FetchKeyRequest {
  public let recipeID: Recipe.ID

  public init(recipeID: Recipe.ID) {
    self.recipeID = recipeID
  }

  public func fetch(_ db: Database) throws -> RecipeDetailData? {
    try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)
  }
}

public struct RecipeEditorDraft: Equatable, Sendable {
  public var id: Recipe.ID?
  public var title: String
  public var subtitle: String
  public var summary: String
  public var sourceName: String
  public var sourceURL: String
  public var sourceAuthor: String
  public var sourcePublicationName: String
  public var sourceBookTitle: String
  public var sourcePageNumber: String
  public var sourceNotes: String
  public var servingsText: String
  public var yieldText: String
  public var prepTimeMinutes: Int
  public var cookTimeMinutes: Int
  public var cuisine: String
  public var course: String
  public var libraryPlacement: RecipeLibraryPlacement
  public var favorite: Bool
  public var ingredientText: String
  public var instructionText: String
  public var noteText: String
  public var tagNames: String
  public var categoryNames: String
  public var selectedCategoryIDs: Set<Category.ID>?
  public var originalSnapshot: Data?
  public var dateCreated: Date?

  public init(
    id: Recipe.ID? = nil,
    title: String = "",
    subtitle: String = "",
    summary: String = "",
    sourceName: String = "",
    sourceURL: String = "",
    sourceAuthor: String = "",
    sourcePublicationName: String = "",
    sourceBookTitle: String = "",
    sourcePageNumber: String = "",
    sourceNotes: String = "",
    servingsText: String = "",
    yieldText: String = "",
    prepTimeMinutes: Int = 0,
    cookTimeMinutes: Int = 0,
    cuisine: String = "",
    course: String = "",
    libraryPlacement: RecipeLibraryPlacement = .main,
    favorite: Bool = false,
    ingredientText: String = "",
    instructionText: String = "",
    noteText: String = "",
    tagNames: String = "",
    categoryNames: String = "",
    selectedCategoryIDs: Set<Category.ID>? = nil,
    originalSnapshot: Data? = nil,
    dateCreated: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.summary = summary
    self.sourceName = sourceName
    self.sourceURL = sourceURL
    self.sourceAuthor = sourceAuthor
    self.sourcePublicationName = sourcePublicationName
    self.sourceBookTitle = sourceBookTitle
    self.sourcePageNumber = sourcePageNumber
    self.sourceNotes = sourceNotes
    self.servingsText = servingsText
    self.yieldText = yieldText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.cuisine = cuisine
    self.course = course
    self.libraryPlacement = libraryPlacement
    self.favorite = favorite
    self.ingredientText = ingredientText
    self.instructionText = instructionText
    self.noteText = noteText
    self.tagNames = tagNames
    self.categoryNames = categoryNames
    self.selectedCategoryIDs = selectedCategoryIDs
    self.originalSnapshot = originalSnapshot
    self.dateCreated = dateCreated
  }

  public init(detail: RecipeDetailData) {
    let firstIngredientSectionID = detail.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }.first?.id
    let editableIngredientLines = firstIngredientSectionID.map { sectionID in
      detail.ingredientLines.filter { $0.sectionID == sectionID }
    } ?? detail.ingredientLines
    let firstInstructionSectionID = detail.instructionSections.sorted { $0.sortOrder < $1.sortOrder }.first?.id
    let editableInstructionSteps = firstInstructionSectionID.map { sectionID in
      detail.instructionSteps.filter { $0.sectionID == sectionID }
    } ?? detail.instructionSteps

    self.init(
      id: detail.recipe.id,
      title: detail.recipe.title,
      subtitle: detail.recipe.subtitle ?? "",
      summary: detail.recipe.summary ?? "",
      sourceName: detail.source?.name ?? "",
      sourceURL: detail.source?.url ?? "",
      sourceAuthor: detail.source?.author ?? "",
      sourcePublicationName: detail.source?.publicationName ?? "",
      sourceBookTitle: detail.source?.bookTitle ?? "",
      sourcePageNumber: detail.source?.pageNumber ?? "",
      sourceNotes: detail.source?.sourceNotes ?? "",
      servingsText: detail.recipe.servingsText ?? "",
      yieldText: detail.recipe.yieldText ?? "",
      prepTimeMinutes: detail.recipe.prepTimeMinutes ?? 0,
      cookTimeMinutes: detail.recipe.cookTimeMinutes ?? 0,
      cuisine: detail.recipe.cuisine ?? "",
      course: detail.recipe.course ?? "",
      libraryPlacement: detail.recipe.libraryPlacement,
      favorite: detail.recipe.favorite,
      ingredientText: editableIngredientLines
        .sorted { $0.sortOrder < $1.sortOrder }
        .map(\.originalText)
        .joined(separator: "\n"),
      instructionText: editableInstructionSteps
        .sorted { $0.sortOrder < $1.sortOrder }
        .map(\.text)
        .joined(separator: "\n\n"),
      noteText: detail.notes
        .filter { $0.noteType == .general }
        .sorted { $0.dateCreated < $1.dateCreated }
        .map(\.text)
        .joined(separator: "\n\n"),
      tagNames: detail.tags.map(\.name).joined(separator: ", "),
      categoryNames: detail.categoryDisplayNames.joined(separator: ", "),
      selectedCategoryIDs: Set(detail.categories.map(\.id)),
      originalSnapshot: detail.recipe.originalSnapshot,
      dateCreated: detail.recipe.dateCreated
    )
  }
}

public enum RecipeRepository {
  public static func fetchDetail(recipeID: Recipe.ID, in db: Database) throws -> RecipeDetailData? {
    guard let recipe = try (Recipe.where { $0.id.eq(recipeID) })
      .fetchOne(db)
    else { return nil }

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
      .fetchAll(db)
    let source = try (RecipeSource.where { $0.recipeID.eq(recipeID) })
      .fetchOne(db)
    let recipeTags = try (RecipeTag.where { $0.recipeID.eq(recipeID) })
      .order { $0.sortOrder }
      .fetchAll(db)
    let recipeCategories = try (RecipeCategory.where { $0.recipeID.eq(recipeID) })
      .fetchAll(db)
    let recipeEquipment = try (RecipeEquipment.where { $0.recipeID.eq(recipeID) })
      .fetchAll(db)
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
      recipeEquipment: recipeEquipment
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
    let existingIngredientSection = existingDetail?.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }.first
    let existingInstructionSection = existingDetail?.instructionSections.sorted { $0.sortOrder < $1.sortOrder }.first
    let ingredientSection = existingIngredientSection
      ?? IngredientSection(id: uuid(), recipeID: recipeID, name: nil, sortOrder: 0)
    let instructionSection = existingInstructionSection
      ?? InstructionSection(id: uuid(), recipeID: recipeID, name: nil, sortOrder: 0)
    let ingredientLines = IngredientParser.lines(
      from: draft.ingredientText,
      recipeID: recipeID,
      sectionID: ingredientSection.id,
      uuid: uuid
    )
    let reconciledIngredientLines = reconcileIngredientLines(
      ingredientLines,
      existing: existingDetail?.ingredientLines.filter { $0.sectionID == ingredientSection.id } ?? []
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
      originalSnapshot: draft.originalSnapshot
    )
    let source = sourceFromDraft(
      draft,
      recipeID: recipeID,
      existingSource: existingDetail?.source,
      uuid: uuid
    )
    let snapshotIngredientSections = mergedSections(
      existingDetail?.ingredientSections ?? [],
      replacing: ingredientSection
    )
    let snapshotIngredientLines = mergedIngredientLines(
      existingDetail?.ingredientLines ?? [],
      replacingSectionID: ingredientSection.id,
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
        photos: existingDetail?.photos ?? [],
        equipment: existingDetail?.equipment ?? [],
        recipeEquipment: existingDetail?.recipeEquipment ?? []
      )
    }

    try upsert(recipe, in: db)
    try replaceSource(source, recipeID: recipeID, in: db)
    try saveEditableChildren(
      recipeID: recipeID,
      ingredientSection: ingredientSection,
      ingredientLines: reconciledIngredientLines,
      existingIngredientLines: existingDetail?.ingredientLines.filter { $0.sectionID == ingredientSection.id } ?? [],
      instructionSection: instructionSection,
      instructionSteps: reconciledInstructionSteps,
      existingInstructionSteps: existingDetail?.instructionSteps.filter { $0.sectionID == instructionSection.id } ?? [],
      generalNotes: generalNotes,
      existingGeneralNotes: existingDetail?.notes.filter { $0.noteType == .general } ?? [],
      in: db
    )
    try reconcileTags(draft.tagNames.listNames, recipeID: recipeID, in: db, now: now, uuid: uuid)
    try reconcileCategories(from: draft, recipeID: recipeID, in: db, now: now, uuid: uuid)

    return recipeID
  }

  public static func archive(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try Recipe.find(recipeID).update {
      $0.archived = true
      $0.dateModified = now
    }
    .execute(db)
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

  @discardableResult
  public static func importBundle(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    in db: Database,
    now: Date,
    uuid: () -> UUID
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

    try upsert(recipe, in: db)
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
      try insert(note, in: db)
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

    return recipe.id
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

  private static func replaceSource(_ source: RecipeSource?, recipeID: Recipe.ID, in db: Database) throws {
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

  private static func reconcileTags(
    _ names: [String],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    var existingTags = try Tag.fetchAll(db)
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

  private static func reconcileIngredientLines(
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

  private static func mergedConfidence(
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
    if value.rounded() == value {
      return "\(Int(value))"
    }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private static func pluralized(_ unit: String, quantity: Double) -> String {
    guard quantity != 1, !unit.hasSuffix("s") else { return unit }
    return unit + "s"
  }
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
    let snapshot = RecipeBundle(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines.sorted { $0.sortOrder < $1.sortOrder },
      instructionSections: instructionSections,
      instructionSteps: instructionSteps.sorted { $0.sortOrder < $1.sortOrder },
      recipeNotes: notes.sorted { $0.dateCreated < $1.dateCreated },
      photos: photos.sorted { $0.sortOrder < $1.sortOrder },
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
}

private extension String {
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
