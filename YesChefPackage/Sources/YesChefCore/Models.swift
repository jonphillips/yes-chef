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
  public var makeAhead: String?
  public var chefItUp: String?
  public var serveWith: Data?
  public var viewScale: Double
  public var coverPhotoID: RecipePhoto.ID?

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
    originalSnapshot: Data? = nil,
    makeAhead: String? = nil,
    chefItUp: String? = nil,
    serveWith: Data? = nil,
    viewScale: Double = 1.0,
    coverPhotoID: RecipePhoto.ID? = nil
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
    self.makeAhead = makeAhead
    self.chefItUp = chefItUp
    self.serveWith = serveWith
    self.viewScale = viewScale
    self.coverPhotoID = coverPhotoID
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
    case makeAhead
    case chefItUp
    case serveWith
    case viewScale
    case coverPhotoID
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
      originalSnapshot: try container.decodeIfPresent(Data.self, forKey: .originalSnapshot),
      makeAhead: try container.decodeIfPresent(String.self, forKey: .makeAhead),
      chefItUp: try container.decodeIfPresent(String.self, forKey: .chefItUp),
      serveWith: try container.decodeIfPresent(Data.self, forKey: .serveWith),
      viewScale: try container.decodeIfPresent(Double.self, forKey: .viewScale) ?? 1.0,
      coverPhotoID: try container.decodeIfPresent(RecipePhoto.ID.self, forKey: .coverPhotoID)
    )
  }
}

public struct ServeWithItem: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var note: String?

  public init(id: UUID, title: String, note: String? = nil) {
    self.id = id
    self.title = title
    self.note = note
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

@Table("mealPlanItems")
public struct MealPlanItem: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var kind: MealPlanItemKind
  public var recipeID: Recipe.ID?
  public var title: String
  public var scheduledDate: Date
  public var mealSlot: MealPlanItemSlot
  public var notes: String?
  public var startTime: Date?
  public var endTime: Date?
  public var sortOrder: Int
  public var dateCreated: Date
  public var dateModified: Date
  public var scale: Double

  public init(
    id: UUID,
    kind: MealPlanItemKind,
    recipeID: Recipe.ID? = nil,
    title: String,
    scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    notes: String? = nil,
    startTime: Date? = nil,
    endTime: Date? = nil,
    sortOrder: Int,
    dateCreated: Date,
    dateModified: Date,
    scale: Double = 1.0
  ) {
    self.id = id
    self.kind = kind
    self.recipeID = recipeID
    self.title = title
    self.scheduledDate = scheduledDate
    self.mealSlot = mealSlot
    self.notes = notes
    self.startTime = startTime
    self.endTime = endTime
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
    self.dateModified = dateModified
    self.scale = scale
  }
}

public enum MealPlanItemKind: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable {
  case recipe
  case note
  case reservation

  public var title: String {
    switch self {
    case .recipe: "Recipe"
    case .note: "Note"
    case .reservation: "Reservation"
    }
  }

  public var systemImage: String {
    switch self {
    case .recipe: "book.closed"
    case .note: "note.text"
    case .reservation: "fork.knife.circle"
    }
  }
}

public enum MealPlanItemSlot: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable {
  case breakfast
  case lunch
  case dinner
  case snack

  public var title: String {
    switch self {
    case .breakfast: "Breakfast"
    case .lunch: "Lunch"
    case .dinner: "Dinner"
    case .snack: "Snack"
    }
  }

  public var systemImage: String {
    switch self {
    case .breakfast: "sunrise"
    case .lunch: "takeoutbag.and.cup.and.straw"
    case .dinner: "fork.knife"
    case .snack: "carrot"
    }
  }

  public var sortOrder: Int {
    switch self {
    case .breakfast: 0
    case .lunch: 1
    case .dinner: 2
    case .snack: 3
    }
  }
}

@Table("menus")
public struct Menu: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var notes: String?
  public var dayCount: Int
  public var prepPlan: Data?
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    title: String,
    notes: String? = nil,
    dayCount: Int,
    prepPlan: Data? = nil,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.dayCount = dayCount
    self.prepPlan = prepPlan
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

@Table("menuItems")
public struct MenuItem: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var menuID: Menu.ID
  public var kind: MealPlanItemKind
  public var recipeID: Recipe.ID?
  public var title: String
  public var dayOffset: Int
  public var mealSlot: MealPlanItemSlot
  public var notes: String?
  public var sortOrder: Int
  public var dateCreated: Date
  public var dateModified: Date
  public var scale: Double

  public init(
    id: UUID,
    menuID: Menu.ID,
    kind: MealPlanItemKind,
    recipeID: Recipe.ID? = nil,
    title: String,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    notes: String? = nil,
    sortOrder: Int,
    dateCreated: Date,
    dateModified: Date,
    scale: Double = 1.0
  ) {
    self.id = id
    self.menuID = menuID
    self.kind = kind
    self.recipeID = recipeID
    self.title = title
    self.dayOffset = dayOffset
    self.mealSlot = mealSlot
    self.notes = notes
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
    self.dateModified = dateModified
    self.scale = scale
  }
}

@Table("menuPlacements")
public struct MenuPlacement: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var menuID: Menu.ID
  public var startDate: Date
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    menuID: Menu.ID,
    startDate: Date,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.menuID = menuID
    self.startDate = startDate
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

@Table("groceryLists")
public struct GroceryList: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var sortOrder: Int
  public var isDefault: Bool
  public var remindersListName: String?
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    title: String,
    sortOrder: Int,
    isDefault: Bool = false,
    remindersListName: String? = nil,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.title = title
    self.sortOrder = sortOrder
    self.isDefault = isDefault
    self.remindersListName = remindersListName
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

@Table("groceryItems")
public struct GroceryItem: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var groceryListID: GroceryList.ID
  public var title: String
  public var canonicalName: String?
  public var quantity: Double?
  public var quantityText: String?
  public var unit: String?
  public var aisle: String?
  public var notes: String?
  public var isPurchased: Bool
  public var purchasedAt: Date?
  public var sortOrder: Int
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    groceryListID: GroceryList.ID,
    title: String,
    canonicalName: String? = nil,
    quantity: Double? = nil,
    quantityText: String? = nil,
    unit: String? = nil,
    aisle: String? = nil,
    notes: String? = nil,
    isPurchased: Bool = false,
    purchasedAt: Date? = nil,
    sortOrder: Int,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.groceryListID = groceryListID
    self.title = title
    self.canonicalName = canonicalName
    self.quantity = quantity
    self.quantityText = quantityText
    self.unit = unit
    self.aisle = aisle
    self.notes = notes
    self.isPurchased = isPurchased
    self.purchasedAt = purchasedAt
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

@Table("groceryItemSources")
public struct GroceryItemSource: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var groceryItemID: GroceryItem.ID
  public var origin: GroceryItemOrigin
  public var recipeID: Recipe.ID?
  public var ingredientLineID: IngredientLine.ID?
  public var mealPlanItemID: MealPlanItem.ID?
  public var menuID: Menu.ID?
  public var menuItemID: MenuItem.ID?
  public var menuPlacementID: MenuPlacement.ID?
  public var scheduledDate: Date?
  public var mealSlot: MealPlanItemSlot?
  public var sourceTitle: String?
  public var sourceSubtitle: String?
  public var ingredientText: String?
  public var dateCreated: Date

  public init(
    id: UUID,
    groceryItemID: GroceryItem.ID,
    origin: GroceryItemOrigin,
    recipeID: Recipe.ID? = nil,
    ingredientLineID: IngredientLine.ID? = nil,
    mealPlanItemID: MealPlanItem.ID? = nil,
    menuID: Menu.ID? = nil,
    menuItemID: MenuItem.ID? = nil,
    menuPlacementID: MenuPlacement.ID? = nil,
    scheduledDate: Date? = nil,
    mealSlot: MealPlanItemSlot? = nil,
    sourceTitle: String? = nil,
    sourceSubtitle: String? = nil,
    ingredientText: String? = nil,
    dateCreated: Date
  ) {
    self.id = id
    self.groceryItemID = groceryItemID
    self.origin = origin
    self.recipeID = recipeID
    self.ingredientLineID = ingredientLineID
    self.mealPlanItemID = mealPlanItemID
    self.menuID = menuID
    self.menuItemID = menuItemID
    self.menuPlacementID = menuPlacementID
    self.scheduledDate = scheduledDate
    self.mealSlot = mealSlot
    self.sourceTitle = sourceTitle
    self.sourceSubtitle = sourceSubtitle
    self.ingredientText = ingredientText
    self.dateCreated = dateCreated
  }
}

public enum GroceryItemOrigin: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable {
  case custom
  case recipe
  case menu
  case calendarItem
  case menuPlacement

  public var title: String {
    switch self {
    case .custom: "Custom"
    case .recipe: "Recipe"
    case .menu: "Menu"
    case .calendarItem: "Meal Calendar"
    case .menuPlacement: "Placed Menu"
    }
  }

  public var systemImage: String {
    switch self {
    case .custom: "plus.circle"
    case .recipe: "book.closed"
    case .menu: "menucard"
    case .calendarItem: "calendar"
    case .menuPlacement: "calendar.badge.checkmark"
    }
  }
}

@Table("pantryItems")
public struct PantryItem: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var notes: String?
  public var isUnlimited: Bool
  public var thresholdQuantity: Double?
  public var thresholdUnit: String?
  public var sortOrder: Int
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    title: String,
    notes: String? = nil,
    isUnlimited: Bool = true,
    thresholdQuantity: Double? = nil,
    thresholdUnit: String? = nil,
    sortOrder: Int,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.isUnlimited = isUnlimited
    self.thresholdQuantity = thresholdQuantity
    self.thresholdUnit = thresholdUnit
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }

  public var policy: PantryPolicy {
    PantryPolicy.normalized(
      isUnlimited: isUnlimited,
      thresholdQuantity: thresholdQuantity,
      thresholdUnit: thresholdUnit
    )
  }
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

@Table("recipeImportRef")
public struct RecipeImportRef: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var normalizedSourceURL: String?
  public var normalizedTitle: String
  public var dateCreated: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    normalizedSourceURL: String? = nil,
    normalizedTitle: String,
    dateCreated: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.normalizedSourceURL = normalizedSourceURL
    self.normalizedTitle = normalizedTitle
    self.dateCreated = dateCreated
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
  public var canonicalName: String?
  public var preparation: String?
  public var comment: String?
  public var isOptional: Bool
  public var shoppingCategory: String?
  public var doNotShop: Bool
  public var isHeader: Bool
  public var substitution: String?
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
    canonicalName: String? = nil,
    preparation: String? = nil,
    comment: String? = nil,
    isOptional: Bool = false,
    shoppingCategory: String? = nil,
    doNotShop: Bool = false,
    isHeader: Bool = false,
    substitution: String? = nil,
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
    self.canonicalName = canonicalName
    self.preparation = preparation
    self.comment = comment
    self.isOptional = isOptional
    self.shoppingCategory = shoppingCategory
    self.doNotShop = doNotShop
    self.isHeader = isHeader
    self.substitution = substitution
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
