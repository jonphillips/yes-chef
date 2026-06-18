import Foundation
import SQLiteData

@Table("recipes")
public struct Recipe: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var subtitle: String?
  public var summary: String?
  public var servings: Double?
  public var servingsText: String?
  public var yieldText: String?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var activeTimeMinutes: Int?
  public var restTimeMinutes: Int?
  public var cuisine: String?
  public var course: String?
  public var difficulty: RecipeDifficulty?
  public var rating: Int?
  public var favorite: Bool
  public var archived: Bool
  public var libraryPlacement: RecipeLibraryPlacement
  public var dateCreated: Date
  public var dateModified: Date
  public var lastCookedAt: Date?
  public var timesCooked: Int
  public var originalImportText: String?
  public var originalSnapshot: Data?

  public init(
    id: UUID,
    title: String,
    subtitle: String? = nil,
    summary: String? = nil,
    servings: Double? = nil,
    servingsText: String? = nil,
    yieldText: String? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    activeTimeMinutes: Int? = nil,
    restTimeMinutes: Int? = nil,
    cuisine: String? = nil,
    course: String? = nil,
    difficulty: RecipeDifficulty? = nil,
    rating: Int? = nil,
    favorite: Bool = false,
    archived: Bool = false,
    libraryPlacement: RecipeLibraryPlacement = .main,
    dateCreated: Date,
    dateModified: Date,
    lastCookedAt: Date? = nil,
    timesCooked: Int = 0,
    originalImportText: String? = nil,
    originalSnapshot: Data? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.summary = summary
    self.servings = servings
    self.servingsText = servingsText
    self.yieldText = yieldText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.activeTimeMinutes = activeTimeMinutes
    self.restTimeMinutes = restTimeMinutes
    self.cuisine = cuisine
    self.course = course
    self.difficulty = difficulty
    self.rating = rating
    self.favorite = favorite
    self.archived = archived
    self.libraryPlacement = libraryPlacement
    self.dateCreated = dateCreated
    self.dateModified = dateModified
    self.lastCookedAt = lastCookedAt
    self.timesCooked = timesCooked
    self.originalImportText = originalImportText
    self.originalSnapshot = originalSnapshot
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case subtitle
    case summary
    case servings
    case servingsText
    case yieldText
    case prepTimeMinutes
    case cookTimeMinutes
    case totalTimeMinutes
    case activeTimeMinutes
    case restTimeMinutes
    case cuisine
    case course
    case difficulty
    case rating
    case favorite
    case archived
    case libraryPlacement
    case dateCreated
    case dateModified
    case lastCookedAt
    case timesCooked
    case originalImportText
    case originalSnapshot
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      title: try container.decode(String.self, forKey: .title),
      subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle),
      summary: try container.decodeIfPresent(String.self, forKey: .summary),
      servings: try container.decodeIfPresent(Double.self, forKey: .servings),
      servingsText: try container.decodeIfPresent(String.self, forKey: .servingsText),
      yieldText: try container.decodeIfPresent(String.self, forKey: .yieldText),
      prepTimeMinutes: try container.decodeIfPresent(Int.self, forKey: .prepTimeMinutes),
      cookTimeMinutes: try container.decodeIfPresent(Int.self, forKey: .cookTimeMinutes),
      totalTimeMinutes: try container.decodeIfPresent(Int.self, forKey: .totalTimeMinutes),
      activeTimeMinutes: try container.decodeIfPresent(Int.self, forKey: .activeTimeMinutes),
      restTimeMinutes: try container.decodeIfPresent(Int.self, forKey: .restTimeMinutes),
      cuisine: try container.decodeIfPresent(String.self, forKey: .cuisine),
      course: try container.decodeIfPresent(String.self, forKey: .course),
      difficulty: try container.decodeIfPresent(RecipeDifficulty.self, forKey: .difficulty),
      rating: try container.decodeIfPresent(Int.self, forKey: .rating),
      favorite: try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false,
      archived: try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false,
      libraryPlacement: try container.decodeIfPresent(RecipeLibraryPlacement.self, forKey: .libraryPlacement) ?? .main,
      dateCreated: try container.decode(Date.self, forKey: .dateCreated),
      dateModified: try container.decode(Date.self, forKey: .dateModified),
      lastCookedAt: try container.decodeIfPresent(Date.self, forKey: .lastCookedAt),
      timesCooked: try container.decodeIfPresent(Int.self, forKey: .timesCooked) ?? 0,
      originalImportText: try container.decodeIfPresent(String.self, forKey: .originalImportText),
      originalSnapshot: try container.decodeIfPresent(Data.self, forKey: .originalSnapshot)
    )
  }
}

public enum RecipeLibraryPlacement: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable {
  case main
  case reference
}

public enum RecipeDifficulty: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case easy
  case medium
  case hard
}

@Table("recipeSources")
public struct RecipeSource: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var name: String?
  public var url: String?
  public var author: String?
  public var publicationName: String?
  public var bookTitle: String?
  public var pageNumber: String?
  public var importedFrom: String?
  public var dateImported: Date?
  public var sourceNotes: String?

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    name: String? = nil,
    url: String? = nil,
    author: String? = nil,
    publicationName: String? = nil,
    bookTitle: String? = nil,
    pageNumber: String? = nil,
    importedFrom: String? = nil,
    dateImported: Date? = nil,
    sourceNotes: String? = nil
  ) {
    self.id = id
    self.recipeID = recipeID
    self.name = name
    self.url = url
    self.author = author
    self.publicationName = publicationName
    self.bookTitle = bookTitle
    self.pageNumber = pageNumber
    self.importedFrom = importedFrom
    self.dateImported = dateImported
    self.sourceNotes = sourceNotes
  }
}

@Table("ingredientSections")
public struct IngredientSection: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var name: String?
  public var sortOrder: Int

  public init(id: UUID, recipeID: Recipe.ID, name: String? = nil, sortOrder: Int) {
    self.id = id
    self.recipeID = recipeID
    self.name = name
    self.sortOrder = sortOrder
  }
}

@Table("ingredientLines")
public struct IngredientLine: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var sectionID: IngredientSection.ID
  public var originalText: String
  public var quantity: Double?
  public var quantityText: String?
  public var unit: String?
  public var item: String?
  public var preparation: String?
  public var comment: String?
  public var isOptional: Bool
  public var shoppingCategory: String?
  public var doNotShop: Bool
  public var isHeader: Bool
  public var sortOrder: Int
  public var confidence: ParseConfidence?

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    sectionID: IngredientSection.ID,
    originalText: String,
    quantity: Double? = nil,
    quantityText: String? = nil,
    unit: String? = nil,
    item: String? = nil,
    preparation: String? = nil,
    comment: String? = nil,
    isOptional: Bool = false,
    shoppingCategory: String? = nil,
    doNotShop: Bool = false,
    isHeader: Bool = false,
    sortOrder: Int,
    confidence: ParseConfidence? = nil
  ) {
    self.id = id
    self.recipeID = recipeID
    self.sectionID = sectionID
    self.originalText = originalText
    self.quantity = quantity
    self.quantityText = quantityText
    self.unit = unit
    self.item = item
    self.preparation = preparation
    self.comment = comment
    self.isOptional = isOptional
    self.shoppingCategory = shoppingCategory
    self.doNotShop = doNotShop
    self.isHeader = isHeader
    self.sortOrder = sortOrder
    self.confidence = confidence
  }
}

public enum ParseConfidence: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case low
  case medium
  case high
}

@Table("instructionSections")
public struct InstructionSection: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var name: String?
  public var sortOrder: Int

  public init(id: UUID, recipeID: Recipe.ID, name: String? = nil, sortOrder: Int) {
    self.id = id
    self.recipeID = recipeID
    self.name = name
    self.sortOrder = sortOrder
  }
}

@Table("instructionSteps")
public struct InstructionStep: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var sectionID: InstructionSection.ID
  public var text: String
  public var sortOrder: Int
  public var isOptional: Bool

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    sectionID: InstructionSection.ID,
    text: String,
    sortOrder: Int,
    isOptional: Bool = false
  ) {
    self.id = id
    self.recipeID = recipeID
    self.sectionID = sectionID
    self.text = text
    self.sortOrder = sortOrder
    self.isOptional = isOptional
  }
}

@Table("recipeNotes")
public struct RecipeNote: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var text: String
  public var noteType: RecipeNoteType
  public var dateCreated: Date
  public var dateModified: Date
  public var cookingSessionID: UUID?
  public var pinned: Bool

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    text: String,
    noteType: RecipeNoteType = .general,
    dateCreated: Date,
    dateModified: Date,
    cookingSessionID: UUID? = nil,
    pinned: Bool = false
  ) {
    self.id = id
    self.recipeID = recipeID
    self.text = text
    self.noteType = noteType
    self.dateCreated = dateCreated
    self.dateModified = dateModified
    self.cookingSessionID = cookingSessionID
    self.pinned = pinned
  }
}

public enum RecipeNoteType: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case general
  case adaptation
  case makeAhead
  case freezing
  case thawing
  case shopping
  case serving
  case equipment
  case scaling
  case substitution
  case wine
  case retrospective
  case warning
}

@Table("recipePhotos")
public struct RecipePhoto: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var imageDataReference: String
  public var displayData: Data?
  public var thumbnailData: Data?
  public var mediaType: String?
  public var pixelWidth: Int?
  public var pixelHeight: Int?
  public var originalSourcePath: String?
  public var sourceURL: String?
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
    displayData: Data? = nil,
    thumbnailData: Data? = nil,
    mediaType: String? = nil,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    originalSourcePath: String? = nil,
    sourceURL: String? = nil,
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
    self.displayData = displayData
    self.thumbnailData = thumbnailData
    self.mediaType = mediaType
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.originalSourcePath = originalSourcePath
    self.sourceURL = sourceURL
    self.checksum = checksum
    self.kind = kind
    self.caption = caption
    self.source = source
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }
}

public enum RecipePhotoKind: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case hero
  case gallery
  case referenceDocument
}

public enum PhotoSource: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case user
  case imported
  case extracted
}

@Table("tags")
public struct Tag: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var color: String?
  public var sortOrder: Int
  public var dateCreated: Date

  public init(id: UUID, name: String, color: String? = nil, sortOrder: Int, dateCreated: Date) {
    self.id = id
    self.name = name
    self.color = color
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }
}

@Table("categories")
public struct Category: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var parentCategoryID: Category.ID?
  public var sortOrder: Int
  public var dateCreated: Date

  public init(
    id: UUID,
    name: String,
    parentCategoryID: Category.ID? = nil,
    sortOrder: Int,
    dateCreated: Date
  ) {
    self.id = id
    self.name = name
    self.parentCategoryID = parentCategoryID
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }
}

@Table("equipment")
public struct Equipment: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var equipmentType: String?
  public var notes: String?

  public init(id: UUID, name: String, equipmentType: String? = nil, notes: String? = nil) {
    self.id = id
    self.name = name
    self.equipmentType = equipmentType
    self.notes = notes
  }
}

@Table("recipeTags")
public struct RecipeTag: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var tagID: Tag.ID
  public var sortOrder: Int

  public init(id: UUID, recipeID: Recipe.ID, tagID: Tag.ID, sortOrder: Int) {
    self.id = id
    self.recipeID = recipeID
    self.tagID = tagID
    self.sortOrder = sortOrder
  }
}

@Table("recipeCategories")
public struct RecipeCategory: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var categoryID: Category.ID

  public init(id: UUID, recipeID: Recipe.ID, categoryID: Category.ID) {
    self.id = id
    self.recipeID = recipeID
    self.categoryID = categoryID
  }
}

@Table("recipeEquipment")
public struct RecipeEquipment: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var equipmentID: Equipment.ID
  public var notes: String?

  public init(id: UUID, recipeID: Recipe.ID, equipmentID: Equipment.ID, notes: String? = nil) {
    self.id = id
    self.recipeID = recipeID
    self.equipmentID = equipmentID
    self.notes = notes
  }
}
