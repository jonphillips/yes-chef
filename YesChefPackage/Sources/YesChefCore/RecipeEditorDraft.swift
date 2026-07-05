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
  public var cuisine: String
  public var course: String
  public var libraryPlacement: RecipeLibraryPlacement
  public var favorite: Bool
  public var ingredientSectionName: String
  public var ingredientText: String
  public var ingredientLineDrafts: [RecipeIngredientLineDraft]
  public var instructionText: String
  public var noteText: String
  public var tagNames: String
  public var categoryNames: String
  public var selectedCategoryIDs: Set<Category.ID>?
  public var originalSnapshot: Data?
  public var dateCreated: Date?
  public var pendingPhotos: [RecipeEditorPhotoDraft]

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
    pendingPhotos: [RecipeEditorPhotoDraft] = []
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
    self.ingredientSectionName = ingredientSectionName
    self.ingredientText = ingredientText
    self.ingredientLineDrafts = ingredientLineDrafts
    self.instructionText = instructionText
    self.noteText = noteText
    self.tagNames = tagNames
    self.categoryNames = categoryNames
    self.selectedCategoryIDs = selectedCategoryIDs
    self.originalSnapshot = originalSnapshot
    self.dateCreated = dateCreated
    self.pendingPhotos = pendingPhotos
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
      ingredientSectionName: firstIngredientSectionID
        .flatMap { sectionID in detail.ingredientSections.first { $0.id == sectionID }?.name } ?? "",
      ingredientText: editableIngredientLines
        .sorted { $0.sortOrder < $1.sortOrder }
        .map(\.originalText)
        .joined(separator: "\n"),
      ingredientLineDrafts: editableIngredientLines
        .sorted { $0.sortOrder < $1.sortOrder }
        .map(RecipeIngredientLineDraft.init(line:)),
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
      dateCreated: detail.recipe.dateCreated,
      pendingPhotos: []
    )
  }
}

public struct RecipeIngredientLineDraft: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var originalText: String
  public var isHeader: Bool
  public var sortOrder: Int

  public init(
    id: UUID,
    originalText: String,
    isHeader: Bool = false,
    sortOrder: Int
  ) {
    self.id = id
    self.originalText = originalText
    self.isHeader = isHeader
    self.sortOrder = sortOrder
  }

  public init(line: IngredientLine) {
    self.init(
      id: line.id,
      originalText: line.originalText,
      isHeader: line.isHeader,
      sortOrder: line.sortOrder
    )
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
