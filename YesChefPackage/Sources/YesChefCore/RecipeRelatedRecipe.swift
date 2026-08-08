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
      try RecipeRelatedRecipe.fetchAll(db).compactMap { $0.otherRecipeID(connectedTo: recipeID) }
    )
    return try Recipe.fetchAll(db)
      .filter { relatedRecipeIDs.contains($0.id) && !$0.archived }
      .sorted(by: relatedRecipeDisplayOrder)
  }
}

private func relatedRecipeDisplayOrder(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
  let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
  if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
  return lhs.id.uuidString < rhs.id.uuidString
}
