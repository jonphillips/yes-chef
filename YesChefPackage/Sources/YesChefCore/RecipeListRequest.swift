import Foundation
import SQLiteData

public struct RecipeListRowData: Identifiable, Equatable, Sendable {
  public var recipe: Recipe
  public var thumbnailData: Data?

  public init(recipe: Recipe, thumbnailData: Data? = nil) {
    self.recipe = recipe
    self.thumbnailData = thumbnailData
  }

  public var id: Recipe.ID { recipe.id }
}

public struct RecipeListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [RecipeListRowData] {
    let recipes = try Recipe.fetchAll(db)
    let photoRows = try RecipePhoto
      .select {
        RecipeListPhotoRow.Columns(
          recipeID: $0.recipeID,
          displayData: $0.displayData,
          thumbnailData: $0.thumbnailData,
          pixelWidth: $0.pixelWidth,
          pixelHeight: $0.pixelHeight,
          kind: $0.kind,
          sortOrder: $0.sortOrder
        )
      }
      .fetchAll(db)

    var thumbnailsByRecipeID: [Recipe.ID: RecipeListPhotoRow] = [:]
    for row in photoRows where row.kind != .referenceDocument && row.listImageData != nil {
      guard let existingRow = thumbnailsByRecipeID[row.recipeID] else {
        thumbnailsByRecipeID[row.recipeID] = row
        continue
      }
      if row.listSortKey < existingRow.listSortKey {
        thumbnailsByRecipeID[row.recipeID] = row
      }
    }

    return recipes.map { recipe in
      RecipeListRowData(
        recipe: recipe,
        thumbnailData: thumbnailsByRecipeID[recipe.id]?.listImageData
      )
    }
  }
}

@Selection
private struct RecipeListPhotoRow: Equatable, Sendable {
  let recipeID: Recipe.ID
  let displayData: Data?
  let thumbnailData: Data?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let kind: RecipePhotoKind
  let sortOrder: Int

  var listImageData: Data? {
    thumbnailData ?? displayData
  }

  var listSortKey: PhotoSortKey {
    PhotoSortKey(
      isLowResolution: Swift.max(pixelWidth ?? 0, pixelHeight ?? 0) < 700,
      kindRank: kind == .hero ? 0 : 1,
      sortOrder: sortOrder
    )
  }
}

private struct PhotoSortKey: Comparable {
  var isLowResolution: Bool
  var kindRank: Int
  var sortOrder: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.isLowResolution != rhs.isLowResolution {
      return !lhs.isLowResolution
    }
    if lhs.kindRank != rhs.kindRank {
      return lhs.kindRank < rhs.kindRank
    }
    return lhs.sortOrder < rhs.sortOrder
  }
}
