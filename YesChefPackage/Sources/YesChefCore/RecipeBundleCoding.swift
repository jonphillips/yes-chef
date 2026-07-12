import Foundation

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
