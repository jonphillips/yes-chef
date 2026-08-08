import Foundation
import SQLiteData

/// A symmetric, synced relationship between two recipes. Both recipe identifiers remain loose
/// columns: an edge has no owning recipe, and two SQL foreign keys would violate CloudKit's
/// single-FK sharing rule.
@Table("recipeRelatedRecipes")
public struct RecipeRelatedRecipe: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var relatedRecipeID: Recipe.ID
  public var dateCreated: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    relatedRecipeID: Recipe.ID,
    dateCreated: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.relatedRecipeID = relatedRecipeID
    self.dateCreated = dateCreated
  }
}

public enum RecipeRelatedRecipeError: Error, Equatable, LocalizedError {
  case missingRecipe(Recipe.ID)
  case selfLink

  public var errorDescription: String? {
    switch self {
    case .missingRecipe:
      "That recipe is no longer available."
    case .selfLink:
      "A recipe cannot be related to itself."
    }
  }
}

/// The lightweight recipe metadata needed to choose a related recipe. This intentionally omits
/// sources and photos so opening the picker does not materialize library thumbnails on a writer.
public struct RecipeRelatedRecipePickerRow: Identifiable, Equatable, Sendable {
  public let id: Recipe.ID
  public var title: String
  public var subtitle: String?
  public var summary: String?
  public var categoryNames: [String]

  public init(
    id: Recipe.ID,
    title: String,
    subtitle: String?,
    summary: String?,
    categoryNames: [String]
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.summary = summary
    self.categoryNames = categoryNames
  }
}

extension RecipeRelatedRecipe {
  /// A stable canonical form gives every writer the same representation of an undirected edge.
  static func canonicalPair(
    _ firstRecipeID: Recipe.ID,
    _ secondRecipeID: Recipe.ID
  ) -> (recipeID: Recipe.ID, relatedRecipeID: Recipe.ID) {
    firstRecipeID.uuidString < secondRecipeID.uuidString
      ? (firstRecipeID, secondRecipeID)
      : (secondRecipeID, firstRecipeID)
  }

  func connects(_ firstRecipeID: Recipe.ID, _ secondRecipeID: Recipe.ID) -> Bool {
    let requestedPair = Self.canonicalPair(firstRecipeID, secondRecipeID)
    let storedPair = Self.canonicalPair(recipeID, relatedRecipeID)
    return storedPair.recipeID == requestedPair.recipeID
      && storedPair.relatedRecipeID == requestedPair.relatedRecipeID
  }

  func otherRecipeID(connectedTo recipeID: Recipe.ID) -> Recipe.ID? {
    if self.recipeID == recipeID { relatedRecipeID }
    else if relatedRecipeID == recipeID { self.recipeID }
    else { nil }
  }
}

extension RecipeRepository {
  /// Loads link-picker candidates with a scoped read instead of observing the full library.
  /// In particular, this query never touches `recipePhotos`, whose thumbnail BLOBs are only for
  /// the browsing list.
  public static func relatedRecipePickerRows(in db: Database) throws -> [RecipeRelatedRecipePickerRow] {
    let recipes = try Recipe
      .where { !$0.archived }
      .select {
        RelatedRecipePickerRecipeRow.Columns(
          id: $0.id,
          title: $0.title,
          subtitle: $0.subtitle,
          summary: $0.summary
        )
      }
      .fetchAll(db)
    let facets = try Facet.fetchAll(db)
    let categoriesByID = Dictionary(
      uniqueKeysWithValues: CategoryRepository.visibleCategories(
        try Category.fetchAll(db),
        facets: facets
      )
      .map { ($0.id, $0) }
    )
    let categoryNamesByRecipeID = Dictionary(grouping: try RecipeCategory.fetchAll(db), by: \.recipeID)
      .mapValues { recipeCategories in
        let categories = recipeCategories
          .compactMap { categoriesByID[$0.categoryID] }
          .sorted { $0.sortOrder < $1.sortOrder }
        return categories.map {
          CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID)
        }
      }

    return recipes
      .map {
        RecipeRelatedRecipePickerRow(
          id: $0.id,
          title: $0.title,
          subtitle: $0.subtitle,
          summary: $0.summary,
          categoryNames: categoryNamesByRecipeID[$0.id] ?? []
        )
      }
      .sorted(by: relatedRecipePickerOrder)
  }

  /// Creates the relationship once, and converges any offline duplicates on the stable lowest UUID.
  /// This is the only writer for the logically unique unordered recipe pair.
  public static func linkRelatedRecipes(
    _ firstRecipeID: Recipe.ID,
    _ secondRecipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard firstRecipeID != secondRecipeID else { throw RecipeRelatedRecipeError.selfLink }
    for recipeID in [firstRecipeID, secondRecipeID] {
      guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
        throw RecipeRelatedRecipeError.missingRecipe(recipeID)
      }
    }

    let matchingEdges = try RecipeRelatedRecipe.fetchAll(db)
      .filter { $0.connects(firstRecipeID, secondRecipeID) }
      .sorted { $0.id.uuidString < $1.id.uuidString }
    guard !matchingEdges.isEmpty else {
      let pair = RecipeRelatedRecipe.canonicalPair(firstRecipeID, secondRecipeID)
      try RecipeRelatedRecipe.insert {
        RecipeRelatedRecipe(
          id: uuid(),
          recipeID: pair.recipeID,
          relatedRecipeID: pair.relatedRecipeID,
          dateCreated: now
        )
      }
      .execute(db)
      return
    }

    // No child table refers to an edge, so deleting converged duplicates needs no repointing.
    for duplicate in matchingEdges.dropFirst() {
      try RecipeRelatedRecipe.find(duplicate.id).delete().execute(db)
    }
  }

  /// Removes every representation of the symmetric edge, including any offline duplicate.
  public static func unlinkRelatedRecipes(
    _ firstRecipeID: Recipe.ID,
    _ secondRecipeID: Recipe.ID,
    in db: Database
  ) throws {
    for edge in try RecipeRelatedRecipe.fetchAll(db) where edge.connects(firstRecipeID, secondRecipeID) {
      try RecipeRelatedRecipe.find(edge.id).delete().execute(db)
    }
  }

  static func relatedRecipes(for recipeID: Recipe.ID, in db: Database) throws -> [Recipe] {
    let relatedRecipeIDs = Set(
      try RecipeRelatedRecipe
        .where { $0.recipeID.eq(recipeID) || $0.relatedRecipeID.eq(recipeID) }
        .fetchAll(db)
        .compactMap { $0.otherRecipeID(connectedTo: recipeID) }
    )
    guard !relatedRecipeIDs.isEmpty else { return [] }
    return try Recipe
      .where { $0.id.in(relatedRecipeIDs) && !$0.archived }
      .fetchAll(db)
      .sorted(by: relatedRecipeDisplayOrder)
  }
}

@Selection
private struct RelatedRecipePickerRecipeRow: Equatable, Sendable {
  let id: Recipe.ID
  let title: String
  let subtitle: String?
  let summary: String?
}

private func relatedRecipeDisplayOrder(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
  let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
  if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func relatedRecipePickerOrder(
  _ lhs: RecipeRelatedRecipePickerRow,
  _ rhs: RecipeRelatedRecipePickerRow
) -> Bool {
  let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
  if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
  return lhs.id.uuidString < rhs.id.uuidString
}
