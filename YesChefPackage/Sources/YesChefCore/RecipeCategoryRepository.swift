import Foundation
import SQLiteData

public struct CategoryListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Category] {
    let facets = try Facet.fetchAll(db)
    return CategoryRepository.sortedCategories(
      CategoryRepository.visibleCategories(try Category.fetchAll(db), facets: facets)
    )
  }
}

public struct CategoryManagementListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Category] {
    CategoryRepository.sortedCategories(try Category.fetchAll(db))
  }
}

public struct FacetListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Facet] {
    CategoryRepository.sortedFacets(try Facet.fetchAll(db).filter { !$0.hidden })
  }
}

public struct FacetManagementListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Facet] {
    CategoryRepository.sortedFacets(try Facet.fetchAll(db))
  }
}

public enum CategoryRepositoryError: Error, Equatable {
  case emptyName
  case duplicateSibling(name: String)
  case categoryNotFound
  case parentNotFound
  case facetNotFound
  case duplicateFacetName(name: String)
  case parentFacetMismatch
  case looseLabelsCannotHaveChildren
  case cannotParentCategoryUnderItself
  case cannotParentCategoryUnderDescendant
  case cannotDeleteCategoryWithChildren
  case cannotDeleteCategoryUsedByRecipes
  case cannotDeleteStarterCategory
  case cannotDeleteFacetWithCategories
  case cannotDeleteStarterFacet
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
    case let .duplicateFacetName(name):
      "A category group named \(name) already exists."
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
      "Starter categories cannot be deleted."
    case .cannotDeleteFacetWithCategories:
      "Delete or move this category group's categories before deleting it."
    case .cannotDeleteStarterFacet:
      "Starter category groups cannot be deleted."
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

  public struct ParentChange: Equatable, Sendable {
    public var categoryID: Category.ID
    public var fromParentCategoryID: Category.ID?
    public var toParentCategoryID: Category.ID?

    public init(categoryID: Category.ID, fromParentCategoryID: Category.ID?, toParentCategoryID: Category.ID?) {
      self.categoryID = categoryID
      self.fromParentCategoryID = fromParentCategoryID
      self.toParentCategoryID = toParentCategoryID
    }
  }

  public struct CategoryMerge: Equatable, Sendable {
    public var duplicateCategoryID: Category.ID
    public var canonicalCategoryID: Category.ID

    public init(duplicateCategoryID: Category.ID, canonicalCategoryID: Category.ID) {
      self.duplicateCategoryID = duplicateCategoryID
      self.canonicalCategoryID = canonicalCategoryID
    }
  }

  public var seededFacetIDs: [Facet.ID] = []
  public var seededCategoryIDs: [Category.ID] = []
  public var promotedRoots: [PromotedRoot] = []
  public var fallbackMatchedRootCategoryIDs: [Category.ID] = []
  public var looseRoots: [LooseRoot] = []
  public var unresolvedRoots: [Category.ID] = []
  public var remappedRootAssignments: [RootAssignmentRemap] = []
  public var parentChanges: [ParentChange] = []
  public var categoryMerges: [CategoryMerge] = []
  public var deletedCategoryIDs: [Category.ID] = []

  public init() {}

  public var requiresReview: Bool {
    !promotedRoots.isEmpty
      || !fallbackMatchedRootCategoryIDs.isEmpty
      || !unresolvedRoots.isEmpty
      || !remappedRootAssignments.isEmpty
      || !parentChanges.isEmpty
      || !categoryMerges.isEmpty
      || !deletedCategoryIDs.isEmpty
  }

  public var logSummary: String {
    let promoted = promotedRoots.map {
      "id=\($0.category.id.uuidString),name=\($0.category.name),facetID=\($0.facetID.uuidString),children=\($0.childCount)"
    }
    let remaps = remappedRootAssignments.map {
      "\($0.rootCategoryID.uuidString)->\($0.destinationCategoryID.uuidString):recipes=\($0.recipeCount)"
    }
    let parentChanges = parentChanges.map {
      let fromParentID = $0.fromParentCategoryID?.uuidString ?? "nil"
      let toParentID = $0.toParentCategoryID?.uuidString ?? "nil"
      return "\($0.categoryID.uuidString):\(fromParentID)->\(toParentID)"
    }
    let merges = categoryMerges.map {
      "\($0.duplicateCategoryID.uuidString)->\($0.canonicalCategoryID.uuidString)"
    }
    let unresolved = unresolvedRoots.compactMap { unresolvedRootID in
      looseRoots.first(where: { $0.category.id == unresolvedRootID }).map {
        "id=\($0.category.id.uuidString),name=\($0.category.name),children=\($0.childCount)"
      }
    }
    let fields = [
      "promotedRoots=[\(promoted.joined(separator: ","))]",
      "fallbackRoots=[\(fallbackMatchedRootCategoryIDs.map(\.uuidString).joined(separator: ","))]",
      "remaps=[\(remaps.joined(separator: ","))]",
      "unresolvedRoots=[\(unresolved.joined(separator: ","))]",
      "parentChanges=[\(parentChanges.joined(separator: ","))]",
      "merges=[\(merges.joined(separator: ","))]",
      "deletedCategories=[\(deletedCategoryIDs.map(\.uuidString).joined(separator: ","))]",
    ]
    return (["facet-migration-audit"] + fields).joined(separator: " ")
  }
}

public enum CategoryRepository {
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
    try deduplicateFacetSiblings(in: db, audit: &audit)
    return audit
  }

  /// Converts the two legacy namespace rows without inferring that any other root with children
  /// is a facet. The returned audit is the hand-review artifact before a second device syncs.
  public static func promoteNamespaceRootsToFacets(in db: Database) throws -> FacetMigrationAudit {
    var audit = FacetMigrationAudit()
    var categories = try Category.fetchAll(db)
    var facets = try Facet.fetchAll(db)

    for seed in starterFacets {
      guard let match = legacyNamespaceRoot(for: seed, in: categories) else { continue }
      let root = match.category
      if match.usedNameFallback {
        audit.fallbackMatchedRootCategoryIDs.append(root.id)
      }

      if !facets.contains(where: { $0.id == seed.facet.id }) {
        try Facet.insert { seed.facet }.execute(db)
        facets.append(seed.facet)
        audit.seededFacetIDs.append(seed.facet.id)
      }

      let children = categories.filter { $0.parentCategoryID == root.id }
      let descendantIDs = CategoryHierarchy.descendantIDs(of: root.id, in: categories)
      for var descendant in categories where descendantIDs.contains(descendant.id) {
        descendant.facetID = seed.facet.id
        if descendant.parentCategoryID == root.id {
          audit.parentChanges.append(
            .init(categoryID: descendant.id, fromParentCategoryID: root.id, toParentCategoryID: nil)
          )
          descendant.parentCategoryID = nil
        }
        try Category.upsert { descendant }.execute(db)
      }

      let assignments = try RecipeCategory.where { $0.categoryID.eq(root.id) }.fetchAll(db)
      if !assignments.isEmpty {
        let destination = try looseNamespaceAssignment(for: seed, in: db)
        for var assignment in assignments {
          assignment.categoryID = destination.id
          try RecipeCategory.upsert { assignment }.execute(db)
        }
        audit.remappedRootAssignments.append(
          .init(rootCategoryID: root.id, destinationCategoryID: destination.id, recipeCount: assignments.count)
        )
      }

      try Category.find(root.id).delete().execute(db)
      audit.deletedCategoryIDs.append(root.id)
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
    if !audit.remappedRootAssignments.isEmpty {
      try deduplicateRecipeCategoryPairs(in: db)
    }
    return audit
  }

  /// Moves the still-synced, dormant tag graph into loose categories. The legacy tables remain
  /// registered for CloudKit but are never mutated here.
  public static func foldDormantTagsIntoCategories(in db: Database) throws {
    let tags = try Tag.fetchAll(db).sorted(by: areTagsInFoldOrder)
    var categories = try Category.fetchAll(db)
    var categoryIDByTagID: [Tag.ID: Category.ID] = [:]
    var mergedCategories = false

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
          mergedCategories = true
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

    let pendingRecipeTags = try RecipeTag.fetchAll(db)
      .sorted(by: areRecipeTagsInFoldOrder)
      .filter { try RecipeCategory.find($0.id).fetchOne(db) == nil }
    guard !pendingRecipeTags.isEmpty else {
      if mergedCategories {
        try deduplicateRecipeCategoryPairs(in: db)
      }
      return
    }

    var recipeCategories = try RecipeCategory.fetchAll(db)
    var insertedRecipeCategories = false
    for tag in pendingRecipeTags {
      guard let categoryID = categoryIDByTagID[tag.tagID] else { continue }
      guard !recipeCategories.contains(where: { $0.recipeID == tag.recipeID && $0.categoryID == categoryID }) else {
        continue
      }
      guard !recipeCategories.contains(where: { $0.id == tag.id }) else { continue }
      let category = RecipeCategory(id: tag.id, recipeID: tag.recipeID, categoryID: categoryID)
      try RecipeCategory.insert { category }.execute(db)
      recipeCategories.append(category)
      insertedRecipeCategories = true
    }
    if mergedCategories || insertedRecipeCategories {
      try deduplicateRecipeCategoryPairs(in: db)
    }
  }

  public static func sortedCategories(_ categories: [Category]) -> [Category] {
    CategoryHierarchy.displayRows(from: categories).map(\.category)
  }

  /// The effective category set exposed by recipe-facing and catalog reads. Hidden assignments
  /// remain stored in `RecipeCategory` so restoring visibility restores the assignment.
  public static func visibleCategories(_ categories: [Category], facets: [Facet]) -> [Category] {
    let visibleFacetIDs = Set(facets.filter { !$0.hidden }.map(\.id))
    return categories.filter { category in
      !category.hidden && (category.facetID.map { visibleFacetIDs.contains($0) } ?? true)
    }
  }

  public static func sortedFacets(_ facets: [Facet]) -> [Facet] {
    facets.sorted {
      if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
      let nameComparison = $0.name.localizedStandardCompare($1.name)
      if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  public static func isStarterFacet(_ facetID: Facet.ID) -> Bool {
    starterFacets.contains { $0.facet.id == facetID }
  }

  public static func isStarterCategory(_ categoryID: Category.ID) -> Bool {
    starterFacetValues.contains { $0.id == categoryID }
  }

  public static func createFacet(
    name: String,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Facet {
    let facets = try Facet.fetchAll(db)
    let name = try normalizedName(name)
    try validateUniqueFacetName(name, excluding: nil, facets: facets)
    let facet = Facet(
      id: uuid(),
      name: name,
      sortOrder: (facets.map(\.sortOrder).max() ?? -1) + 1,
      dateCreated: now
    )
    try Facet.insert { facet }.execute(db)
    return facet
  }

  public static func renameFacet(facetID: Facet.ID, name: String, in db: Database) throws {
    let facets = try Facet.fetchAll(db)
    guard facets.contains(where: { $0.id == facetID }) else {
      throw CategoryRepositoryError.facetNotFound
    }
    let name = try normalizedName(name)
    try validateUniqueFacetName(name, excluding: facetID, facets: facets)
    try Facet.find(facetID).update { $0.name = name }.execute(db)
  }

  public static func setFacetHidden(facetID: Facet.ID, hidden: Bool, in db: Database) throws {
    guard try Facet.find(facetID).fetchOne(db) != nil else {
      throw CategoryRepositoryError.facetNotFound
    }
    try Facet.find(facetID).update { $0.hidden = hidden }.execute(db)
  }

  public static func setCategoryHidden(categoryID: Category.ID, hidden: Bool, in db: Database) throws {
    guard try Category.find(categoryID).fetchOne(db) != nil else {
      throw CategoryRepositoryError.categoryNotFound
    }
    try Category.find(categoryID).update { $0.hidden = hidden }.execute(db)
  }

  public static func deleteFacet(facetID: Facet.ID, in db: Database) throws {
    guard try Facet.find(facetID).fetchOne(db) != nil else {
      throw CategoryRepositoryError.facetNotFound
    }
    guard !isStarterFacet(facetID) else {
      throw CategoryRepositoryError.cannotDeleteStarterFacet
    }
    guard !(try Category.fetchAll(db)).contains(where: { $0.facetID == facetID }) else {
      throw CategoryRepositoryError.cannotDeleteFacetWithCategories
    }
    try Facet.find(facetID).delete().execute(db)
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
    try validateUniqueSiblingName(
      name,
      facetID: resolvedFacetID,
      parentCategoryID: parentCategoryID,
      excluding: nil,
      categories: categories
    )
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
    facetID: Facet.ID?,
    parentCategoryID: Category.ID?,
    in db: Database
  ) throws {
    let categories = try Category.fetchAll(db)
    let category = try category(categoryID, in: categories)
    let name = try normalizedName(name)
    let facets = try Facet.fetchAll(db)
    let resolvedFacetID = try resolvedFacetID(
      facetID: facetID,
      parentCategoryID: parentCategoryID,
      categories: categories,
      facets: facets
    )
    guard parentCategoryID == nil || facetID == resolvedFacetID else {
      throw CategoryRepositoryError.parentFacetMismatch
    }
    try validateMove(categoryID: categoryID, parentCategoryID: parentCategoryID, categories: categories)
    let descendantIDs = CategoryHierarchy.descendantIDs(of: categoryID, in: categories)
    guard resolvedFacetID != nil || descendantIDs.isEmpty else {
      throw CategoryRepositoryError.looseLabelsCannotHaveChildren
    }
    let membershipChanged = category.facetID != resolvedFacetID || category.parentCategoryID != parentCategoryID
    if category.facetID != resolvedFacetID {
      for descendant in categories where descendantIDs.contains(descendant.id) {
        try Category.find(descendant.id).update { $0.facetID = resolvedFacetID }.execute(db)
      }
    }
    let existingSibling = categories.first {
      $0.id != categoryID
        && $0.facetID == resolvedFacetID
        && $0.parentCategoryID == parentCategoryID
        && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }

    if let existingSibling {
      guard membershipChanged else {
        throw CategoryRepositoryError.duplicateSibling(name: name)
      }
      _ = try mergeCategory(category, into: existingSibling, in: db)
      return
    }

    try Category.find(category.id).update {
      $0.name = name
      $0.facetID = resolvedFacetID
      $0.parentCategoryID = parentCategoryID
    }
    .execute(db)
  }

  public static func deleteCategory(categoryID: Category.ID, in db: Database) throws {
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
      name: "Legacy \(seed.facet.name)",
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

  private static func validateUniqueFacetName(
    _ name: String,
    excluding facetID: Facet.ID?,
    facets: [Facet]
  ) throws {
    guard !facets.contains(where: {
      $0.id != facetID && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) else {
      throw CategoryRepositoryError.duplicateFacetName(name: name)
    }
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
    categories: [Category]
  ) throws {
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
    facetID: Facet.ID?,
    parentCategoryID: Category.ID?,
    excluding categoryID: Category.ID?,
    categories: [Category]
  ) throws {
    guard !categories.contains(where: {
      $0.id != categoryID
        && $0.facetID == facetID
        && $0.parentCategoryID == parentCategoryID
        && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) else {
      throw CategoryRepositoryError.duplicateSibling(name: name)
    }
  }

  private static func nextSortOrder(parentCategoryID: Category.ID?, categories: [Category]) -> Int {
    (categories.filter { $0.parentCategoryID == parentCategoryID }.map(\.sortOrder).max() ?? -1) + 1
  }

  fileprivate static func mergeCategory(_ duplicate: Category, into canonical: Category, in db: Database) throws -> Category {
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

  private static func deduplicateFacetSiblings(in db: Database, audit: inout FacetMigrationAudit) throws {
    var mergedCategories = false
    while true {
      let categories = try Category.fetchAll(db)
      let grouped = Dictionary(grouping: categories.filter { $0.facetID != nil }) {
        FacetSiblingKey(
          facetID: $0.facetID!,
          parentCategoryID: $0.parentCategoryID,
          normalizedName: normalizedNameKey($0.name)
        )
      }
      guard let duplicates = grouped.values.first(where: { $0.count > 1 }) else { break }
      let canonical = canonicalFacetCategory(from: duplicates)
      for duplicate in duplicates where duplicate.id != canonical.id {
        _ = try mergeCategory(duplicate, into: canonical, in: db)
        audit.categoryMerges.append(.init(duplicateCategoryID: duplicate.id, canonicalCategoryID: canonical.id))
        audit.deletedCategoryIDs.append(duplicate.id)
        mergedCategories = true
      }
    }
    if mergedCategories {
      try deduplicateRecipeCategoryPairs(in: db)
    }
  }

  private static func canonicalFacetCategory(from categories: [Category]) -> Category {
    let starterIDs = Set(starterFacetValues.map(\.id))
    return categories.sorted {
      let lhsIsStarter = starterIDs.contains($0.id)
      let rhsIsStarter = starterIDs.contains($1.id)
      if lhsIsStarter != rhsIsStarter { return lhsIsStarter }
      return areCategoriesInFoldOrder($0, $1)
    }.first!
  }

  private static func legacyNamespaceRoot(for seed: StarterFacet, in categories: [Category]) -> LegacyNamespaceRoot? {
    if let category = categories.first(where: {
      $0.id == seed.legacyRootCategoryID && $0.parentCategoryID == nil && $0.facetID == nil
    }) {
      return .init(category: category, usedNameFallback: false)
    }
    let recognizedValueIDs = Set(starterFacetValues
      .filter { $0.category.facetID == seed.facet.id }
      .map(\.id))
    let fallbackMatches = categories
      .filter { root in
        root.parentCategoryID == nil
          && root.facetID == nil
          && root.name.caseInsensitiveCompare(seed.facet.name) == .orderedSame
          && categories.contains { child in
            child.parentCategoryID == root.id && recognizedValueIDs.contains(child.id)
          }
      }
      .sorted(by: areCategoriesInFoldOrder)
    guard let category = fallbackMatches.first else { return nil }
    return .init(category: category, usedNameFallback: true)
  }

  private static func normalizedNameKey(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
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

private struct FacetSiblingKey: Hashable {
  var facetID: Facet.ID
  var parentCategoryID: Category.ID?
  var normalizedName: String
}

private struct LegacyNamespaceRoot {
  var category: Category
  var usedNameFallback: Bool
}

private struct StarterFacet {
  var facet: Facet
  var legacyRootCategoryID: Category.ID
  var looseAssignmentCategoryID: Category.ID
}

private struct StarterFacetValue {
  var category: Category
  var id: Category.ID { category.id }
}

private let starterCategoryDate = Date(timeIntervalSinceReferenceDate: 0)

private let starterFacets: [StarterFacet] = [
  .init(
    facet: Facet(id: starterCategoryID(1), name: "Cuisine", sortOrder: 0, dateCreated: starterCategoryDate),
    legacyRootCategoryID: starterCategoryID(1),
    looseAssignmentCategoryID: starterCategoryID(101)
  ),
  .init(
    facet: Facet(id: starterCategoryID(2), name: "Course", sortOrder: 1, dateCreated: starterCategoryDate),
    legacyRootCategoryID: starterCategoryID(2),
    looseAssignmentCategoryID: starterCategoryID(102)
  ),
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
  /// Applies model suggestions after the ordinary import labels have been reconciled. Suggestions
  /// carry stored ids where a destination already exists, so a model path is never the writer's
  /// interface. Reusing a hidden row deliberately makes it visible again: acceptance is an
  /// explicit re-assignment, not a background import resurrecting vocabulary.
  static func reconcileSuggestedLabels(
    _ suggestions: [SuggestedLabel],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard !suggestions.isEmpty else { return }
    let existingIDs = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db).map(\.categoryID)
    var categoryIDs = existingIDs
    for suggestion in suggestions {
      let category = try category(for: suggestion, in: db, now: now, uuid: uuid)
      categoryIDs.append(category.id)
    }
    try reconcileCategoryIDs(categoryIDs, recipeID: recipeID, in: db, uuid: uuid)
  }

  private static func category(
    for suggestion: SuggestedLabel,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    switch suggestion {
    case let .existingCategory(category):
      guard var stored = try Category.find(category.id).fetchOne(db) else {
        throw CategoryRepositoryError.categoryNotFound
      }
      if let facetID = stored.facetID, var facet = try Facet.find(facetID).fetchOne(db), facet.hidden {
        facet.hidden = false
        try Facet.upsert { facet }.execute(db)
      }
      if stored.hidden {
        stored.hidden = false
        try Category.upsert { stored }.execute(db)
      }
      return stored

    case let .newChild(child):
      guard var facet = try Facet.find(child.facet.id).fetchOne(db) else {
        throw CategoryRepositoryError.facetNotFound
      }
      if facet.hidden {
        facet.hidden = false
        try Facet.upsert { facet }.execute(db)
      }
      if let parent = child.parentCategory {
        guard let storedParent = try Category.find(parent.id).fetchOne(db) else {
          throw CategoryRepositoryError.parentNotFound
        }
        guard storedParent.facetID == facet.id else {
          throw CategoryRepositoryError.parentFacetMismatch
        }
      }
      if var existing = try Category.fetchAll(db).first(where: {
        $0.facetID == facet.id
          && $0.parentCategoryID == child.parentCategory?.id
          && $0.name.caseInsensitiveCompare(child.name) == .orderedSame
      }) {
        if existing.hidden {
          existing.hidden = false
          try Category.upsert { existing }.execute(db)
        }
        return existing
      }
      return try CategoryRepository.createCategory(
        name: child.name,
        facetID: facet.id,
        parentCategoryID: child.parentCategory?.id,
        in: db,
        now: now,
        uuid: uuid
      )

    case let .loose(name):
      if var existing = try Category.fetchAll(db).first(where: {
        $0.facetID == nil
          && $0.parentCategoryID == nil
          && $0.name.caseInsensitiveCompare(name) == .orderedSame
      }) {
        if existing.hidden {
          existing.hidden = false
          try Category.upsert { existing }.execute(db)
        }
        return existing
      }
      return try CategoryRepository.createCategory(
        name: name,
        parentCategoryID: nil,
        in: db,
        now: now,
        uuid: uuid
      )

    case let .namespace(namespace):
      var facet = try Facet.fetchAll(db).first {
        $0.name.caseInsensitiveCompare(namespace.facetName) == .orderedSame
      }
      if facet == nil {
        facet = try CategoryRepository.createFacet(
          name: namespace.facetName,
          in: db,
          now: now,
          uuid: uuid
        )
      } else if var existingFacet = facet, existingFacet.hidden {
        existingFacet.hidden = false
        try Facet.upsert { existingFacet }.execute(db)
        facet = existingFacet
      }
      guard let facet else { throw CategoryRepositoryError.facetNotFound }
      let child = SuggestedLabel.NewChild(facet: facet, parentCategory: nil, name: namespace.firstValueName)
      return try category(for: .newChild(child), in: db, now: now, uuid: uuid)
    }
  }

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
    if path.components.count == 1, let name = path.components.first {
      return try findOrCreateLooseCategory(name: name, categories: &categories, in: db, now: now, uuid: uuid)
    }
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
    let matches = categories.filter {
      $0.facetID == nil && $0.parentCategoryID == nil && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }.sorted {
      if $0.dateCreated != $1.dateCreated { return $0.dateCreated < $1.dateCreated }
      if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
      return $0.id.uuidString < $1.id.uuidString
    }
    if var canonical = matches.first {
      for duplicate in matches.dropFirst() {
        canonical = try CategoryRepository.mergeCategory(duplicate, into: canonical, in: db)
      }
      categories = try Category.fetchAll(db)
      return canonical
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
