import Foundation
import SQLiteData

public struct CategoryListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Category] {
    CategoryRepository.sortedCategories(try Category.fetchAll(db).filter { !$0.hidden })
  }
}

/// Category visibility is now a simple per-row concern. The type remains the shared reader
/// projection while the old seed-tombstone convergence machinery is retired.
public struct EffectiveCategorySet: Sendable {
  public let categories: [Category]
  public let unavailableCategoryIDs: Set<Category.ID>
}

public enum CategoryRepositoryError: Error, Equatable {
  case emptyName
  case duplicateSibling(name: String)
  case categoryNotFound
  case parentNotFound
  case facetNotFound
  case parentFacetMismatch
  case looseLabelsCannotHaveChildren
  case cannotParentCategoryUnderItself
  case cannotParentCategoryUnderDescendant
  case cannotDeleteCategoryWithChildren
  case cannotDeleteCategoryUsedByRecipes
  case cannotDeleteStarterCategory
}

extension CategoryRepositoryError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyName:
      "Category name cannot be empty."
    case let .duplicateSibling(name):
      "A category named \(name) already exists at that level."
    case .categoryNotFound:
      "Category not found."
    case .parentNotFound:
      "Parent category not found."
    case .facetNotFound:
      "Category group not found."
    case .parentFacetMismatch:
      "A category can only be nested inside the same category group."
    case .looseLabelsCannotHaveChildren:
      "A loose label cannot contain child categories."
    case .cannotParentCategoryUnderItself:
      "A category cannot be its own parent."
    case .cannotParentCategoryUnderDescendant:
      "A category cannot be moved under one of its own children."
    case .cannotDeleteCategoryWithChildren:
      "Delete or move this category's children before deleting it."
    case .cannotDeleteCategoryUsedByRecipes:
      "Remove this category from recipes before deleting it."
    case .cannotDeleteStarterCategory:
      "Starter categories can be hidden or renamed, but not deleted."
    }
  }
}

public struct FacetMigrationAudit: Equatable, Sendable {
  public struct PromotedRoot: Equatable, Sendable {
    public var category: Category
    public var facetID: Facet.ID
    public var childCount: Int
  }

  public struct LooseRoot: Equatable, Sendable {
    public var category: Category
    public var childCount: Int
  }

  public struct RootAssignmentRemap: Equatable, Sendable {
    public var rootCategoryID: Category.ID
    public var destinationCategoryID: Category.ID
    public var recipeCount: Int
  }

  public var seededFacetIDs: [Facet.ID] = []
  public var seededCategoryIDs: [Category.ID] = []
  public var promotedRoots: [PromotedRoot] = []
  public var looseRoots: [LooseRoot] = []
  public var unresolvedRoots: [Category.ID] = []
  public var remappedRootAssignments: [RootAssignmentRemap] = []

  public init() {}
}

public enum CategoryRepository {
  public static func effectiveCategorySet(in db: Database) throws -> EffectiveCategorySet {
    EffectiveCategorySet(categories: try Category.fetchAll(db), unavailableCategoryIDs: [])
  }

  /// This post-engine pass is deliberately both deterministic and idempotent. It is safe to run
  /// on every main-app bootstrap because all created rows use fixed identities.
  public static func seedStarterFacets(in db: Database) throws -> FacetMigrationAudit {
    var audit = try promoteNamespaceRootsToFacets(in: db)
    var facets = try Facet.fetchAll(db)
    for seed in starterFacets where !facets.contains(where: { $0.id == seed.facet.id }) {
      try Facet.insert { seed.facet }.execute(db)
      facets.append(seed.facet)
      audit.seededFacetIDs.append(seed.facet.id)
    }
    var categories = try Category.fetchAll(db)
    for seed in starterFacetValues where !categories.contains(where: { $0.id == seed.id }) {
      try Category.insert { seed.category }.execute(db)
      categories.append(seed.category)
      audit.seededCategoryIDs.append(seed.id)
    }
    return audit
  }

  /// Converts the two legacy namespace rows without inferring that any other root with children
  /// is a facet. The returned audit is the hand-review artifact before a second device syncs.
  public static func promoteNamespaceRootsToFacets(in db: Database) throws -> FacetMigrationAudit {
    var audit = FacetMigrationAudit()
    var categories = try Category.fetchAll(db)
    var facets = try Facet.fetchAll(db)

    for seed in starterFacets {
      let roots = categories
        .filter {
          $0.parentCategoryID == nil
            && $0.facetID == nil
            && $0.name.caseInsensitiveCompare(seed.facet.name) == .orderedSame
        }
        .sorted(by: areCategoriesInFoldOrder)
      guard let root = roots.first else { continue }

      if !facets.contains(where: { $0.id == seed.facet.id }) {
        try Facet.insert { seed.facet }.execute(db)
        facets.append(seed.facet)
        audit.seededFacetIDs.append(seed.facet.id)
      }

      let children = categories.filter { $0.parentCategoryID == root.id }
      for var child in children {
        child.facetID = seed.facet.id
        child.parentCategoryID = nil
        try Category.upsert { child }.execute(db)
      }

      let assignments = try RecipeCategory.where { $0.categoryID.eq(root.id) }.fetchAll(db)
      if !assignments.isEmpty {
        let destination: Category
        if children.count == 1, let child = children.first {
          destination = child
        } else {
          destination = try looseNamespaceAssignment(for: seed, in: db)
        }
        for var assignment in assignments {
          assignment.categoryID = destination.id
          try RecipeCategory.upsert { assignment }.execute(db)
        }
        audit.remappedRootAssignments.append(
          .init(rootCategoryID: root.id, destinationCategoryID: destination.id, recipeCount: assignments.count)
        )
      }

      try Category.find(root.id).delete().execute(db)
      audit.promotedRoots.append(.init(category: root, facetID: seed.facet.id, childCount: children.count))
      categories = try Category.fetchAll(db)
    }

    for category in categories where category.parentCategoryID == nil && category.facetID == nil {
      let childCount = categories.count { $0.parentCategoryID == category.id }
      audit.looseRoots.append(.init(category: category, childCount: childCount))
      if childCount > 0 {
        audit.unresolvedRoots.append(category.id)
      }
    }
    try deduplicateRecipeCategoryPairs(in: db)
    return audit
  }

  /// Moves the still-synced, dormant tag graph into loose categories. The legacy tables remain
  /// registered for CloudKit but are never mutated here.
  public static func foldDormantTagsIntoCategories(in db: Database) throws {
    let tags = try Tag.fetchAll(db).sorted(by: areTagsInFoldOrder)
    var categories = try Category.fetchAll(db)
    var categoryIDByTagID: [Tag.ID: Category.ID] = [:]

    for tag in tags {
      let matchingRoots = categories
        .filter {
          $0.parentCategoryID == nil
            && $0.facetID == nil
            && $0.name.caseInsensitiveCompare(tag.name) == .orderedSame
        }
        .sorted(by: areCategoriesInFoldOrder)

      if var canonical = matchingRoots.first {
        for duplicate in matchingRoots.dropFirst() {
          canonical = try mergeCategory(duplicate, into: canonical, in: db)
        }
        if canonical.color == nil, let color = tag.color {
          canonical.color = color
          try Category.find(canonical.id).update { $0.color = #bind(color) }.execute(db)
        }
        categories = try Category.fetchAll(db)
        categoryIDByTagID[tag.id] = canonical.id
      } else if let priorFold = categories.first(where: { $0.id == tag.id }) {
        categoryIDByTagID[tag.id] = priorFold.id
      } else {
        let category = Category(
          id: tag.id,
          name: tag.name,
          color: tag.color,
          sortOrder: tag.sortOrder,
          dateCreated: tag.dateCreated
        )
        try Category.insert { category }.execute(db)
        categories.append(category)
        categoryIDByTagID[tag.id] = category.id
      }
    }

    var recipeCategories = try RecipeCategory.fetchAll(db)
    for tag in try RecipeTag.fetchAll(db).sorted(by: areRecipeTagsInFoldOrder) {
      guard let categoryID = categoryIDByTagID[tag.tagID] else { continue }
      guard !recipeCategories.contains(where: { $0.recipeID == tag.recipeID && $0.categoryID == categoryID }) else {
        continue
      }
      guard !recipeCategories.contains(where: { $0.id == tag.id }) else { continue }
      let category = RecipeCategory(id: tag.id, recipeID: tag.recipeID, categoryID: categoryID)
      try RecipeCategory.insert { category }.execute(db)
      recipeCategories.append(category)
    }
    try deduplicateRecipeCategoryPairs(in: db)
  }

  public static func sortedCategories(_ categories: [Category]) -> [Category] {
    CategoryHierarchy.displayRows(from: categories).map(\.category)
  }

  public static func createCategory(
    name: String,
    facetID: Facet.ID? = nil,
    parentCategoryID: Category.ID?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    let categories = try Category.fetchAll(db)
    let name = try normalizedName(name)
    let resolvedFacetID = try resolvedFacetID(
      facetID: facetID,
      parentCategoryID: parentCategoryID,
      categories: categories,
      facets: try Facet.fetchAll(db)
    )
    try validateUniqueSiblingName(name, parentCategoryID: parentCategoryID, excluding: nil, categories: categories)
    let category = Category(
      id: uuid(),
      name: name,
      facetID: resolvedFacetID,
      parentCategoryID: parentCategoryID,
      sortOrder: nextSortOrder(parentCategoryID: parentCategoryID, categories: categories),
      dateCreated: now
    )
    try Category.insert { category }.execute(db)
    return category
  }

  public static func updateCategory(
    categoryID: Category.ID,
    name: String,
    parentCategoryID: Category.ID?,
    in db: Database
  ) throws {
    let categories = try Category.fetchAll(db)
    let category = try category(categoryID, in: categories)
    let name = try normalizedName(name)
    try validateMove(
      categoryID: categoryID,
      parentCategoryID: parentCategoryID,
      facetID: category.facetID,
      categories: categories
    )
    try validateUniqueSiblingName(name, parentCategoryID: parentCategoryID, excluding: categoryID, categories: categories)
    try Category.find(category.id).update {
      $0.name = name
      $0.parentCategoryID = parentCategoryID
    }
    .execute(db)
  }

  public static func deleteCategory(categoryID: Category.ID, in db: Database, now _: Date) throws {
    let categories = try Category.fetchAll(db)
    _ = try category(categoryID, in: categories)
    guard !starterFacetValues.contains(where: { $0.id == categoryID }) else {
      throw CategoryRepositoryError.cannotDeleteStarterCategory
    }
    guard !categories.contains(where: { $0.parentCategoryID == categoryID }) else {
      throw CategoryRepositoryError.cannotDeleteCategoryWithChildren
    }
    guard try RecipeCategory.where({ $0.categoryID.eq(categoryID) }).fetchAll(db).isEmpty else {
      throw CategoryRepositoryError.cannotDeleteCategoryUsedByRecipes
    }
    try Category.find(categoryID).delete().execute(db)
  }

  private static func looseNamespaceAssignment(for seed: StarterFacet, in db: Database) throws -> Category {
    if let category = try Category.find(seed.looseAssignmentCategoryID).fetchOne(db) {
      return category
    }
    let category = Category(
      id: seed.looseAssignmentCategoryID,
      name: seed.facet.name,
      sortOrder: seed.facet.sortOrder,
      dateCreated: starterCategoryDate
    )
    try Category.insert { category }.execute(db)
    return category
  }

  private static func category(_ id: Category.ID, in categories: [Category]) throws -> Category {
    guard let category = categories.first(where: { $0.id == id }) else {
      throw CategoryRepositoryError.categoryNotFound
    }
    return category
  }

  private static func normalizedName(_ name: String) throws -> String {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw CategoryRepositoryError.emptyName }
    return name
  }

  private static func resolvedFacetID(
    facetID: Facet.ID?,
    parentCategoryID: Category.ID?,
    categories: [Category],
    facets: [Facet]
  ) throws -> Facet.ID? {
    if let parentCategoryID {
      guard let parent = categories.first(where: { $0.id == parentCategoryID }) else {
        throw CategoryRepositoryError.parentNotFound
      }
      guard let parentFacetID = parent.facetID else {
        throw CategoryRepositoryError.looseLabelsCannotHaveChildren
      }
      guard facetID == nil || facetID == parentFacetID else {
        throw CategoryRepositoryError.parentFacetMismatch
      }
      return parentFacetID
    }
    if let facetID, !facets.contains(where: { $0.id == facetID }) {
      throw CategoryRepositoryError.facetNotFound
    }
    return facetID
  }

  private static func validateMove(
    categoryID: Category.ID,
    parentCategoryID: Category.ID?,
    facetID: Facet.ID?,
    categories: [Category]
  ) throws {
    _ = try resolvedFacetID(facetID: facetID, parentCategoryID: parentCategoryID, categories: categories, facets: [])
    guard parentCategoryID != categoryID else {
      throw CategoryRepositoryError.cannotParentCategoryUnderItself
    }
    let descendantIDs = CategoryHierarchy.descendantIDs(of: categoryID, in: categories)
    guard parentCategoryID.map({ !descendantIDs.contains($0) }) ?? true else {
      throw CategoryRepositoryError.cannotParentCategoryUnderDescendant
    }
  }

  private static func validateUniqueSiblingName(
    _ name: String,
    parentCategoryID: Category.ID?,
    excluding categoryID: Category.ID?,
    categories: [Category]
  ) throws {
    guard !categories.contains(where: {
      $0.id != categoryID
        && $0.parentCategoryID == parentCategoryID
        && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) else {
      throw CategoryRepositoryError.duplicateSibling(name: name)
    }
  }

  private static func nextSortOrder(parentCategoryID: Category.ID?, categories: [Category]) -> Int {
    (categories.filter { $0.parentCategoryID == parentCategoryID }.map(\.sortOrder).max() ?? -1) + 1
  }

  private static func mergeCategory(_ duplicate: Category, into canonical: Category, in db: Database) throws -> Category {
    guard duplicate.id != canonical.id else { return canonical }
    var canonical = canonical
    if canonical.color == nil, let color = duplicate.color {
      canonical.color = color
      try Category.find(canonical.id).update { $0.color = #bind(color) }.execute(db)
    }
    for var child in try Category.fetchAll(db) where child.parentCategoryID == duplicate.id {
      child.parentCategoryID = canonical.id
      try Category.upsert { child }.execute(db)
    }
    for var assignment in try RecipeCategory.fetchAll(db) where assignment.categoryID == duplicate.id {
      assignment.categoryID = canonical.id
      try RecipeCategory.upsert { assignment }.execute(db)
    }
    try deduplicateRecipeCategoryPairs(in: db)
    try Category.find(duplicate.id).delete().execute(db)
    return canonical
  }

  private static func deduplicateRecipeCategoryPairs(in db: Database) throws {
    let grouped = Dictionary(grouping: try RecipeCategory.fetchAll(db)) {
      RecipeCategoryPair(recipeID: $0.recipeID, categoryID: $0.categoryID)
    }
    for rows in grouped.values where rows.count > 1 {
      for duplicate in rows.sorted(by: { $0.id.uuidString < $1.id.uuidString }).dropFirst() {
        try RecipeCategory.find(duplicate.id).delete().execute(db)
      }
    }
  }

  private static func areCategoriesInFoldOrder(_ lhs: Category, _ rhs: Category) -> Bool {
    if lhs.dateCreated != rhs.dateCreated { return lhs.dateCreated < rhs.dateCreated }
    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func areTagsInFoldOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
    if lhs.dateCreated != rhs.dateCreated { return lhs.dateCreated < rhs.dateCreated }
    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func areRecipeTagsInFoldOrder(_ lhs: RecipeTag, _ rhs: RecipeTag) -> Bool {
    if lhs.recipeID != rhs.recipeID { return lhs.recipeID.uuidString < rhs.recipeID.uuidString }
    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

private struct RecipeCategoryPair: Hashable {
  var recipeID: Recipe.ID
  var categoryID: Category.ID
}

private struct StarterFacet {
  var facet: Facet
  var looseAssignmentCategoryID: Category.ID
}

private struct StarterFacetValue {
  var category: Category
  var id: Category.ID { category.id }
}

private let starterCategoryDate = Date(timeIntervalSinceReferenceDate: 0)

private let starterFacets: [StarterFacet] = [
  .init(facet: Facet(id: starterCategoryID(1), name: "Cuisine", sortOrder: 0, dateCreated: starterCategoryDate), looseAssignmentCategoryID: starterCategoryID(101)),
  .init(facet: Facet(id: starterCategoryID(2), name: "Course", sortOrder: 1, dateCreated: starterCategoryDate), looseAssignmentCategoryID: starterCategoryID(102)),
]

private let starterFacetValues: [StarterFacetValue] = [
  (3, "American", 1, 0), (4, "Chinese", 1, 1), (5, "French", 1, 2), (6, "Indian", 1, 3),
  (7, "Italian", 1, 4), (8, "Japanese", 1, 5), (9, "Korean", 1, 6), (10, "Mexican", 1, 7),
  (11, "Thai", 1, 8), (12, "Vietnamese", 1, 9), (13, "Breakfast", 2, 0), (14, "Lunch", 2, 1),
  (15, "Dinner", 2, 2), (16, "Appetizer", 2, 3), (17, "Side Dish", 2, 4), (18, "Dessert", 2, 5),
  (19, "Snack", 2, 6), (20, "Drink", 2, 7),
].map { ordinal, name, facetOrdinal, sortOrder in
  StarterFacetValue(
    category: Category(
      id: starterCategoryID(ordinal),
      name: name,
      facetID: starterCategoryID(facetOrdinal),
      sortOrder: sortOrder,
      dateCreated: starterCategoryDate
    )
  )
}

private func starterCategoryID(_ ordinal: UInt8) -> UUID {
  UUID(uuid: (0xA4, 0xD9, 0x00, 0x02, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, ordinal))
}

extension RecipeRepository {
  static func reconcileCategoryIDs(
    _ categoryIDs: [Category.ID],
    recipeID: Recipe.ID,
    in db: Database,
    uuid: () -> UUID
  ) throws {
    let existing = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    let validCategoryIDs = Set(try Category.fetchAll(db).map(\.id))
    var kept: Set<RecipeCategory.ID> = []
    var seen: Set<Category.ID> = []
    for categoryID in categoryIDs where validCategoryIDs.contains(categoryID) && seen.insert(categoryID).inserted {
      let row = RecipeCategory(
        id: existing.first(where: { $0.categoryID == categoryID })?.id ?? uuid(),
        recipeID: recipeID,
        categoryID: categoryID
      )
      kept.insert(row.id)
      try RecipeCategory.upsert { row }.execute(db)
    }
    try deleteMissingRecipeCategories(existing, keeping: kept, in: db)
  }

  static func reconcileCategories(
    _ names: [String],
    looseNames: [String] = [],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    var categories = try Category.fetchAll(db)
    let facets = try Facet.fetchAll(db)
    let existing = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    var kept: Set<RecipeCategory.ID> = []
    var recipeCategoryIDByCategoryID = Dictionary(uniqueKeysWithValues: existing.map { ($0.categoryID, $0.id) })

    for path in CategoryHierarchy.paths(from: names) {
      let category = try findOrCreateImportedCategory(
        path: path,
        categories: &categories,
        facets: facets,
        in: db,
        now: now,
        uuid: uuid
      )
      let row = RecipeCategory(
        id: recipeCategoryIDByCategoryID[category.id] ?? uuid(), recipeID: recipeID, categoryID: category.id
      )
      recipeCategoryIDByCategoryID[category.id] = row.id
      kept.insert(row.id)
      try RecipeCategory.upsert { row }.execute(db)
    }
    for name in normalizedLooseCategoryNames(looseNames) {
      let category = try findOrCreateLooseCategory(name: name, categories: &categories, in: db, now: now, uuid: uuid)
      let row = RecipeCategory(
        id: recipeCategoryIDByCategoryID[category.id] ?? uuid(), recipeID: recipeID, categoryID: category.id
      )
      recipeCategoryIDByCategoryID[category.id] = row.id
      kept.insert(row.id)
      try RecipeCategory.upsert { row }.execute(db)
    }
    try deleteMissingRecipeCategories(existing, keeping: kept, in: db)
  }

  private static func findOrCreateImportedCategory(
    path: CategoryHierarchy.Path,
    categories: inout [Category],
    facets: [Facet],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    var legacyParentID: Category.ID?
    var legacyCurrent: Category?
    for component in path.components {
      guard let category = categories.first(where: {
        $0.parentCategoryID == legacyParentID && $0.name.caseInsensitiveCompare(component) == .orderedSame
      }) else {
        legacyCurrent = nil
        break
      }
      legacyCurrent = category
      legacyParentID = category.id
    }
    if let legacyCurrent {
      return legacyCurrent
    }
    guard let first = path.components.first,
          path.components.count > 1,
          let facet = facets.first(where: { $0.name.caseInsensitiveCompare(first) == .orderedSame })
    else {
      return try findOrCreateLooseCategory(name: path.components.joined(separator: " > "), categories: &categories, in: db, now: now, uuid: uuid)
    }
    var parentID: Category.ID?
    var current: Category?
    for component in path.components.dropFirst() {
      if let existing = categories.first(where: {
        $0.facetID == facet.id && $0.parentCategoryID == parentID && $0.name.caseInsensitiveCompare(component) == .orderedSame
      }) {
        current = existing
      } else {
        let category = Category(
          id: uuid(), name: component, facetID: facet.id, parentCategoryID: parentID,
          sortOrder: categories.filter { $0.facetID == facet.id && $0.parentCategoryID == parentID }.count,
          dateCreated: now
        )
        try Category.insert { category }.execute(db)
        categories.append(category)
        current = category
      }
      parentID = current?.id
    }
    guard let current else { throw CategoryHierarchyError.emptyPath }
    return current
  }

  private static func findOrCreateLooseCategory(
    name: String, categories: inout [Category], in db: Database, now: Date, uuid: () -> UUID
  ) throws -> Category {
    if let category = categories.first(where: {
      $0.facetID == nil && $0.parentCategoryID == nil && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) {
      return category
    }
    let category = Category(id: uuid(), name: name, sortOrder: categories.filter { $0.facetID == nil && $0.parentCategoryID == nil }.count, dateCreated: now)
    try Category.insert { category }.execute(db)
    categories.append(category)
    return category
  }

  private static func normalizedLooseCategoryNames(_ names: [String]) -> [String] {
    var seen: Set<String> = []
    return names.compactMap {
      let name = $0.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      return seen.insert(key).inserted ? name : nil
    }
  }

  private static func deleteMissingRecipeCategories(
    _ rows: [RecipeCategory], keeping kept: Set<RecipeCategory.ID>, in db: Database
  ) throws {
    for row in rows where !kept.contains(row.id) {
      try #sql("DELETE FROM \"recipeCategories\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }
}
