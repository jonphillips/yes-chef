import Foundation

public enum RecipeBundleCoding {
  public static let currentVersion = 2

  public struct LabelPath: Codable, Equatable, Sendable {
    public var facet: String?
    public var path: [String]

    public init(facet: String?, path: [String]) {
      self.facet = facet
      self.path = path
    }
  }

  public struct LinkTarget: Codable, Equatable, Sendable {
    public var recipeID: Recipe.ID
    public var title: String
    public var sourceURL: String?

    public init(recipeID: Recipe.ID, title: String, sourceURL: String?) {
      self.recipeID = recipeID
      self.title = title
      self.sourceURL = sourceURL
    }
  }

  public enum PayloadError: Error, Equatable {
    case newerVersion(Int)
  }

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
    public var labels: [LabelPath]
    public var serveWith: [RecipeServeWith]
    public var relatedRecipes: [RecipeRelatedRecipe]
    public var variations: [RecipeVariation]
    public var linkTargets: [LinkTarget]

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
      labels: [LabelPath] = [],
      serveWith: [RecipeServeWith] = [],
      relatedRecipes: [RecipeRelatedRecipe] = [],
      variations: [RecipeVariation] = [],
      linkTargets: [LinkTarget] = []
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
      self.labels = labels
      self.serveWith = serveWith
      self.relatedRecipes = relatedRecipes
      self.variations = variations
      self.linkTargets = linkTargets
    }

    private enum CodingKeys: String, CodingKey {
      case version, recipe, source, ingredientSections, ingredientLines, instructionSections, instructionSteps, recipeNotes, photos, tagNames, categoryNames, labels, serveWith, relatedRecipes, variations, linkTargets
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      version = try container.decode(Int.self, forKey: .version)
      recipe = try container.decode(Recipe.self, forKey: .recipe)
      source = try container.decodeIfPresent(RecipeSource.self, forKey: .source)
      ingredientSections = try container.decode([IngredientSection].self, forKey: .ingredientSections)
      ingredientLines = try container.decode([IngredientLine].self, forKey: .ingredientLines)
      instructionSections = try container.decode([InstructionSection].self, forKey: .instructionSections)
      instructionSteps = try container.decode([InstructionStep].self, forKey: .instructionSteps)
      recipeNotes = try container.decode([RecipeNote].self, forKey: .recipeNotes)
      photos = try container.decode([RecipePhoto].self, forKey: .photos)
      tagNames = try container.decode([String].self, forKey: .tagNames)
      categoryNames = try container.decode([String].self, forKey: .categoryNames)
      labels = try container.decodeIfPresent([LabelPath].self, forKey: .labels) ?? []
      serveWith = try container.decodeIfPresent([RecipeServeWith].self, forKey: .serveWith) ?? []
      relatedRecipes = try container.decodeIfPresent([RecipeRelatedRecipe].self, forKey: .relatedRecipes) ?? []
      variations = try container.decodeIfPresent([RecipeVariation].self, forKey: .variations) ?? []
      linkTargets = try container.decodeIfPresent([LinkTarget].self, forKey: .linkTargets) ?? []
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(version, forKey: .version)
      try container.encode(recipe, forKey: .recipe)
      try container.encodeIfPresent(source, forKey: .source)
      try container.encode(ingredientSections, forKey: .ingredientSections)
      try container.encode(ingredientLines, forKey: .ingredientLines)
      try container.encode(instructionSections, forKey: .instructionSections)
      try container.encode(instructionSteps, forKey: .instructionSteps)
      try container.encode(recipeNotes, forKey: .recipeNotes)
      try container.encode(photos, forKey: .photos)
      try container.encode(tagNames, forKey: .tagNames)
      try container.encode(categoryNames, forKey: .categoryNames)
      if version >= 2 { try container.encode(labels, forKey: .labels) }
      if version >= 2 { try container.encode(serveWith, forKey: .serveWith) }
      if version >= 2 { try container.encode(relatedRecipes, forKey: .relatedRecipes) }
      if version >= 2 { try container.encode(variations, forKey: .variations) }
      if version >= 2 { try container.encode(linkTargets, forKey: .linkTargets) }
    }

    public var ingredients: [String] {
      ingredientLines.sorted { $0.sortOrder < $1.sortOrder }.map(\.originalText)
    }

    public var instructions: [String] {
      InstructionStepGroup.groups(sections: instructionSections, steps: instructionSteps)
        .flatMap(\.steps)
        .map(\.text)
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
    photos: [RecipePhoto] = []
  ) throws -> Data {
    let snapshot = RecipeBundle(
      recipe: recipe,
      source: source,
      ingredientSections: ingredientSections,
      ingredientLines: ingredientLines.sorted { $0.sortOrder < $1.sortOrder },
      instructionSections: instructionSections,
      instructionSteps: InstructionStepGroup.groups(sections: instructionSections, steps: instructionSteps)
        .flatMap(\.steps),
      recipeNotes: notes.sorted { $0.dateCreated < $1.dateCreated },
      photos: leanSnapshotPhotos(photos),
      tagNames: tagNames,
      categoryNames: categoryNames
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(snapshot)
  }

  public static func decodeSnapshot(_ data: Data) throws -> RecipeBundle {
    try JSONDecoder().decode(RecipeBundle.self, from: data)
  }

  public static func decodePayload(_ data: Data) throws -> RecipeBundle {
    struct Header: Decodable { var version: Int }
    let version = try JSONDecoder().decode(Header.self, from: data).version
    guard version <= currentVersion else { throw PayloadError.newerVersion(version) }
    return try JSONDecoder().decode(RecipeBundle.self, from: data)
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
