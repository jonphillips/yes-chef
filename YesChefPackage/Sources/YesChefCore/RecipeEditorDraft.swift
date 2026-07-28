import Foundation

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
  public var makeAhead: String
  public var chefItUp: String
  public var editsMakeAheadAndChefItUp: Bool
  public var cuisine: String
  public var course: String
  public var libraryPlacement: RecipeLibraryPlacement
  public var favorite: Bool
  public var ingredientSections: [RecipeEditorIngredientSectionDraft]
  public var instructionSections: [RecipeEditorInstructionSectionDraft]
  public var noteText: String
  public var tagNames: String
  public var categoryNames: String
  public var selectedCategoryIDs: Set<Category.ID>?
  public var originalSnapshot: Data?
  public var dateCreated: Date?
  public var pendingPhotos: [RecipeEditorPhotoDraft]
  public var removesHeroPhoto: Bool

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
    makeAhead: String = "",
    chefItUp: String = "",
    editsMakeAheadAndChefItUp: Bool? = nil,
    cuisine: String = "",
    course: String = "",
    libraryPlacement: RecipeLibraryPlacement = .main,
    favorite: Bool = false,
    ingredientSectionName: String = "",
    ingredientText: String = "",
    ingredientLineDrafts: [RecipeIngredientLineDraft] = [],
    instructionText: String = "",
    noteText: String = "",
    tagNames: String = "",
    categoryNames: String = "",
    selectedCategoryIDs: Set<Category.ID>? = nil,
    originalSnapshot: Data? = nil,
    dateCreated: Date? = nil,
    pendingPhotos: [RecipeEditorPhotoDraft] = [],
    removesHeroPhoto: Bool = false
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
    self.makeAhead = makeAhead
    self.chefItUp = chefItUp
    self.editsMakeAheadAndChefItUp = editsMakeAheadAndChefItUp ?? (!makeAhead.isEmpty || !chefItUp.isEmpty)
    self.cuisine = cuisine
    self.course = course
    self.libraryPlacement = libraryPlacement
    self.favorite = favorite
    // Flat-text callers (a new recipe, `SampleData`, `WorkbenchDraftRecipe`) describe a single
    // section; `init(detail:)` overwrites these with the recipe's real per-section shape.
    self.ingredientSections = [
      RecipeEditorIngredientSectionDraft(
        name: ingredientSectionName,
        text: ingredientText,
        lineDrafts: ingredientLineDrafts
      )
    ]
    self.instructionSections = [
      RecipeEditorInstructionSectionDraft(text: instructionText)
    ]
    self.noteText = noteText
    self.tagNames = tagNames
    self.categoryNames = categoryNames
    self.selectedCategoryIDs = selectedCategoryIDs
    self.originalSnapshot = originalSnapshot
    self.dateCreated = dateCreated
    self.pendingPhotos = pendingPhotos
    self.removesHeroPhoto = removesHeroPhoto
  }

  public init(detail: RecipeDetailData) {
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
      makeAhead: detail.recipe.makeAhead ?? "",
      chefItUp: detail.recipe.chefItUp ?? "",
      editsMakeAheadAndChefItUp: true,
      cuisine: detail.recipe.cuisine ?? "",
      course: detail.recipe.course ?? "",
      libraryPlacement: detail.recipe.libraryPlacement,
      favorite: detail.recipe.favorite,
      noteText: detail.notes
        .filter { $0.noteType == .general }
        .sorted { $0.dateCreated < $1.dateCreated }
        .map(\.text)
        .joined(separator: "\n\n"),
      tagNames: detail.tags.map(\.name).joined(separator: ", "),
      categoryNames: detail.categoryDisplayNames.joined(separator: ", "),
      selectedCategoryIDs: Set(detail.categories.map(\.id)),
      originalSnapshot: detail.recipe.originalSnapshot,
      dateCreated: detail.recipe.dateCreated,
      pendingPhotos: [],
      removesHeroPhoto: false
    )
    self.ingredientSections = Self.ingredientSectionDrafts(from: detail)
    self.instructionSections = Self.instructionSectionDrafts(from: detail)
  }

  /// Every ingredient section in persisted order, each carrying its own lines. Falls back to a single
  /// empty section so the editor always presents at least one box (matching a brand-new recipe).
  static func ingredientSectionDrafts(from detail: RecipeDetailData) -> [RecipeEditorIngredientSectionDraft] {
    let drafts = detail.ingredientSections
      .sorted { $0.sortOrder < $1.sortOrder }
      .map { section -> RecipeEditorIngredientSectionDraft in
        let lines = detail.ingredientLines
          .filter { $0.sectionID == section.id }
          .sorted { $0.sortOrder < $1.sortOrder }
        return RecipeEditorIngredientSectionDraft(
          id: section.id,
          name: section.name ?? "",
          text: lines.map(\.originalText).joined(separator: "\n"),
          lineDrafts: lines.map(RecipeIngredientLineDraft.init(line:))
        )
      }
    return drafts.isEmpty ? [RecipeEditorIngredientSectionDraft()] : drafts
  }

  /// Every instruction section in persisted order, each carrying its own steps as newline-joined text.
  static func instructionSectionDrafts(from detail: RecipeDetailData) -> [RecipeEditorInstructionSectionDraft] {
    let drafts = detail.instructionSections
      .sorted { $0.sortOrder < $1.sortOrder }
      .map { section -> RecipeEditorInstructionSectionDraft in
        let steps = detail.instructionSteps
          .filter { $0.sectionID == section.id }
          .sorted { $0.sortOrder < $1.sortOrder }
        return RecipeEditorInstructionSectionDraft(
          id: section.id,
          name: section.name ?? "",
          text: steps.map(\.text).joined(separator: "\n\n")
        )
      }
    return drafts.isEmpty ? [RecipeEditorInstructionSectionDraft()] : drafts
  }
}

/// One editable ingredient section: its identity, name, and newline-joined lines.
public struct RecipeEditorIngredientSectionDraft: Identifiable, Equatable, Sendable {
  public var id: IngredientSection.ID
  public var name: String
  public var text: String
  public var lineDrafts: [RecipeIngredientLineDraft]

  public init(
    id: IngredientSection.ID = UUID(),
    name: String = "",
    text: String = "",
    lineDrafts: [RecipeIngredientLineDraft] = []
  ) {
    self.id = id
    self.name = name
    self.text = text
    self.lineDrafts = lineDrafts
  }
}

/// One editable instruction section: its identity, name, and blank-line-joined steps.
public struct RecipeEditorInstructionSectionDraft: Identifiable, Equatable, Sendable {
  public var id: InstructionSection.ID
  public var name: String
  public var text: String

  public init(
    id: InstructionSection.ID = UUID(),
    name: String = "",
    text: String = ""
  ) {
    self.id = id
    self.name = name
    self.text = text
  }
}

public struct RecipeIngredientLineDraft: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var originalText: String
  public var sortOrder: Int

  public init(
    id: UUID,
    originalText: String,
    sortOrder: Int
  ) {
    self.id = id
    self.originalText = originalText
    self.sortOrder = sortOrder
  }

  public init(line: IngredientLine) {
    self.init(
      id: line.id,
      originalText: line.originalText,
      sortOrder: line.sortOrder
    )
  }
}

public extension RecipeEditorDraft {
  /// Reconciles a changed ingredient card's line drafts, splitting it wherever the author used the
  /// ingredient-header syntax. The draft owns section IDs, so the split happens before save while
  /// moved lines retain their IDs.
  mutating func ingredientTextChanged(
    sectionID: IngredientSection.ID,
    uuid: () -> UUID
  ) {
    transformIngredientSection(sectionID: sectionID, forcedHeaderLineIndexes: [], uuid: uuid)
  }

  /// Starts a section at a selected, colon-free ingredient line. This is the explicit companion to
  /// the colon shortcut: the selected line becomes the new card's name rather than a persisted line.
  mutating func startIngredientSection(
    sectionID: IngredientSection.ID,
    atLineIndex lineIndex: Int,
    uuid: () -> UUID
  ) {
    transformIngredientSection(sectionID: sectionID, forcedHeaderLineIndexes: [lineIndex], uuid: uuid)
  }

  /// An unnamed non-leading card has no independent storage meaning, so fold its drafts back into
  /// the preceding card while their stable line IDs remain intact.
  mutating func ingredientSectionNameChanged(sectionID: IngredientSection.ID) {
    guard
      let index = ingredientSections.firstIndex(where: { $0.id == sectionID }),
      index > ingredientSections.startIndex,
      ingredientSections[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }

    let removed = ingredientSections.remove(at: index)
    ingredientSections[index - 1].lineDrafts.append(contentsOf: removed.lineDrafts)
    ingredientSections[index - 1].lineDrafts = ingredientSections[index - 1].lineDrafts
      .enumerated()
      .map { index, line in
        var line = line
        line.sortOrder = index
        return line
      }
    ingredientSections[index - 1].text = ingredientSections[index - 1].lineDrafts
      .map(\.originalText)
      .joined(separator: "\n")
  }

  private mutating func transformIngredientSection(
    sectionID: IngredientSection.ID,
    forcedHeaderLineIndexes: Set<Int>,
    uuid: () -> UUID
  ) {
    guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else { return }

    let originalSection = ingredientSections[sectionIndex]
    var unmatchedDrafts = originalSection.lineDrafts.sorted { $0.sortOrder < $1.sortOrder }
    let sourceLines = originalSection.text.components(separatedBy: .newlines)
    var groups: [(name: String, lines: [RecipeIngredientLineDraft])] = [
      (name: originalSection.name, lines: [])
    ]

    for (lineIndex, rawLine) in sourceLines.enumerated() {
      let text = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      if forcedHeaderLineIndexes.contains(lineIndex) || IngredientSectionHeading.isColonTerminatedHeading(text) {
        // A header at the top renames the card already carrying identity. A later header creates
        // the genuinely new card promised by ADR-0014 Amd1-D2.
        if groups.count == 1, groups[0].lines.isEmpty {
          groups[0].name = text.sectionNameAfterHeaderPromotion
        } else {
          groups.append((name: text.sectionNameAfterHeaderPromotion, lines: []))
        }
        continue
      }

      let line: RecipeIngredientLineDraft
      if let matchIndex = unmatchedDrafts.firstIndex(where: { $0.originalText == text }) {
        line = unmatchedDrafts.remove(at: matchIndex)
      } else {
        line = RecipeIngredientLineDraft(id: uuid(), originalText: text, sortOrder: 0)
      }
      groups[groups.count - 1].lines.append(line)
    }

    let replacements = groups.enumerated().map { groupIndex, group in
      let lineDrafts = group.lines.enumerated().map { lineIndex, line in
        var line = line
        line.sortOrder = lineIndex
        return line
      }
      return RecipeEditorIngredientSectionDraft(
        id: groupIndex == 0 ? originalSection.id : uuid(),
        name: group.name,
        text: lineDrafts.map(\.originalText).joined(separator: "\n"),
        lineDrafts: lineDrafts
      )
    }
    ingredientSections.replaceSubrange(sectionIndex...sectionIndex, with: replacements)
  }
}

private extension String {
  var sectionNameAfterHeaderPromotion: String {
    IngredientSectionHeading.isColonTerminatedHeading(self)
      ? IngredientSectionHeading.colonTerminatedName(self)
      : self
  }
}

public struct RecipeEditorPhotoDraft: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var processedPhoto: ProcessedRecipePhoto
  public var originalSourcePath: String?
  public var kind: RecipePhotoKind
  public var caption: String?
  public var source: PhotoSource

  public init(
    id: UUID,
    processedPhoto: ProcessedRecipePhoto,
    originalSourcePath: String? = nil,
    kind: RecipePhotoKind = .hero,
    caption: String? = nil,
    source: PhotoSource = .user
  ) {
    self.id = id
    self.processedPhoto = processedPhoto
    self.originalSourcePath = originalSourcePath
    self.kind = kind
    self.caption = caption
    self.source = source
  }
}
