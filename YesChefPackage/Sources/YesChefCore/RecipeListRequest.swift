import Foundation
import SQLiteData

public struct RecipeListRowData: Identifiable, Equatable, Sendable {
  public var recipe: Recipe
  public var source: RecipeSource?
  public var thumbnailData: Data?
  public var categoryNames: [String]
  public var categoryFilterNames: [String]
  public var tagNames: [String]

  public init(
    recipe: Recipe,
    source: RecipeSource? = nil,
    thumbnailData: Data? = nil,
    categoryNames: [String] = [],
    categoryFilterNames: [String]? = nil,
    tagNames: [String] = []
  ) {
    self.recipe = recipe
    self.source = source
    self.thumbnailData = thumbnailData
    self.categoryNames = categoryNames
    self.categoryFilterNames = categoryFilterNames ?? categoryNames
    self.tagNames = tagNames
  }

  public var id: Recipe.ID { recipe.id }

  public var hasPhoto: Bool {
    thumbnailData != nil
  }
}

public struct RecipeListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [RecipeListRowData] {
    let recipes = try Recipe.fetchAll(db)
    let categoriesByID = Dictionary(
      uniqueKeysWithValues: try Category.fetchAll(db).map { ($0.id, $0) }
    )
    let tagsByID = Dictionary(
      uniqueKeysWithValues: try Tag.fetchAll(db).map { ($0.id, $0) }
    )
    let sourcesByRecipeID = Dictionary(
      grouping: try RecipeSource.fetchAll(db),
      by: \.recipeID
    )
    let categorySummariesByRecipeID = Dictionary(grouping: try RecipeCategory.fetchAll(db), by: \.recipeID)
      .mapValues { recipeCategories in
        let categories = recipeCategories
          .compactMap { categoriesByID[$0.categoryID] }
          .sorted { $0.sortOrder < $1.sortOrder }
        return RecipeListCategorySummary(
          displayNames: categories.map {
            CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID)
          },
          filterNames: distinctSortedOptions(
            categories.flatMap {
              CategoryHierarchy.filterDisplayNames(for: $0, categoriesByID: categoriesByID)
            }
          )
        )
      }
    let tagNamesByRecipeID = Dictionary(grouping: try RecipeTag.fetchAll(db), by: \.recipeID)
      .mapValues { recipeTags in
        recipeTags
          .sorted { $0.sortOrder < $1.sortOrder }
          .compactMap { tagsByID[$0.tagID]?.name }
      }
    let photoRows = try RecipePhoto
      .select {
        RecipeListPhotoRow.Columns(
          recipeID: $0.recipeID,
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
        source: sourcesByRecipeID[recipe.id]?.first,
        thumbnailData: thumbnailsByRecipeID[recipe.id]?.listImageData,
        categoryNames: categorySummariesByRecipeID[recipe.id]?.displayNames ?? [],
        categoryFilterNames: categorySummariesByRecipeID[recipe.id]?.filterNames ?? [],
        tagNames: tagNamesByRecipeID[recipe.id] ?? []
      )
    }
  }
}

private struct RecipeListCategorySummary {
  var displayNames: [String]
  var filterNames: [String]
}

@Selection
private struct RecipeListPhotoRow: Equatable, Sendable {
  let recipeID: Recipe.ID
  let thumbnailData: Data?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let kind: RecipePhotoKind
  let sortOrder: Int

  // List rows carry downscaled thumbnails only — never full-resolution `displayData`
  // (ADR-0029 S2). A photo with no generated thumbnail shows the placeholder instead.
  var listImageData: Data? {
    thumbnailData
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

private func distinctSortedOptions(_ values: [String]) -> [String] {
  Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}
