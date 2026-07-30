import Foundation
import SQLiteData

public struct CategoryListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Category] {
    CategoryRepository.sortedCategories(try Category.fetchAll(db))
  }
}

public enum CategoryRepositoryError: Error, Equatable {
  case emptyName
  case duplicateSibling(name: String)
  case categoryNotFound
  case parentNotFound
  case cannotParentCategoryUnderItself
  case cannotParentCategoryUnderDescendant
  case cannotDeleteCategoryWithChildren
  case cannotDeleteCategoryUsedByRecipes
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
    case .cannotParentCategoryUnderItself:
      "A category cannot be its own parent."
    case .cannotParentCategoryUnderDescendant:
      "A category cannot be moved under one of its own children."
    case .cannotDeleteCategoryWithChildren:
      "Delete or move this category's children before deleting it."
    case .cannotDeleteCategoryUsedByRecipes:
      "Remove this category from recipes before deleting it."
    }
  }
}

public enum CategoryRepository {
  /// Seeds the small, open-ended vocabulary that gives capture and later label suggestions a
  /// useful cold-start anchor. Stable IDs and a fixed creation date let independently seeded
  /// devices converge on the same synced rows instead of inventing duplicate namespaces.
  public static func seedStarterCategories(in db: Database) throws {
    var categories = try Category.fetchAll(db)
    var seedStates = Dictionary(
      uniqueKeysWithValues: try CategorySeedState.fetchAll(db).map { ($0.id, $0) }
    )
    let tombstonedSeedIDs = Set(try CategorySeedTombstone.fetchAll(db).map(\.id))
    var resolvedCategoryIDBySeedID: [Category.ID: Category.ID] = [:]

    for seed in starterCategories {
      let parentCategoryID: Category.ID?
      if let parentSeedID = seed.parentSeedID {
        guard let resolvedParentCategoryID = resolvedCategoryIDBySeedID[parentSeedID] else {
          continue
        }
        parentCategoryID = resolvedParentCategoryID
      } else {
        parentCategoryID = nil
      }

      if tombstonedSeedIDs.contains(seed.id) {
        try removeTombstonedSeedCategory(seed, categories: &categories, in: db)
        continue
      }

      if let state = seedStates[seed.id],
        let categoryID = state.categoryID,
        let category = categories.first(where: { $0.id == categoryID }),
        (category.parentCategoryID != parentCategoryID
          || category.name.caseInsensitiveCompare(seed.name) != .orderedSame) {
        resolvedCategoryIDBySeedID[seed.id] = category.id
        continue
      }

      let matchingCategories = categories
        .filter {
          $0.parentCategoryID == parentCategoryID
            && $0.name.caseInsensitiveCompare(seed.name) == .orderedSame
        }
        .sorted(by: areCategoriesInFoldOrder)

      if let seededCategory = categories.first(where: { $0.id == seed.id }),
         seededCategory.parentCategoryID != parentCategoryID
          || seededCategory.name.caseInsensitiveCompare(seed.name) != .orderedSame {
        // A previously seeded category is now user-authored. Its UUID remains its durable
        // identity, so do not recreate or relocate it on a later launch.
        resolvedCategoryIDBySeedID[seed.id] = seededCategory.id
        try updateSeedState(
          seedID: seed.id,
          categoryID: seededCategory.id,
          seedStates: &seedStates,
          in: db
        )
        continue
      }

      if var canonicalCategory = matchingCategories.first {
        for duplicate in matchingCategories.dropFirst() {
          canonicalCategory = try mergeCategory(duplicate, into: canonicalCategory, in: db)
        }
        categories = try Category.fetchAll(db)
        resolvedCategoryIDBySeedID[seed.id] = canonicalCategory.id
        try updateSeedState(
          seedID: seed.id,
          categoryID: canonicalCategory.id,
          seedStates: &seedStates,
          in: db
        )
        continue
      }

      let category = Category(
        id: seed.id,
        name: seed.name,
        parentCategoryID: parentCategoryID,
        sortOrder: seed.sortOrder,
        dateCreated: starterCategoryDate
      )
      try Category.insert { category }.execute(db)
      categories.append(category)
      resolvedCategoryIDBySeedID[seed.id] = category.id
      try updateSeedState(
        seedID: seed.id,
        categoryID: category.id,
        seedStates: &seedStates,
        in: db
      )
    }
  }

  /// Moves the still-synced, now-dormant tag graph into the category tree. This deliberately
  /// runs outside `DatabaseMigrator`, after CloudSync has installed its triggers, so every
  /// resulting category and recipe-category write participates in normal sync.
  public static func foldDormantTagsIntoCategories(in db: Database) throws {
    let tags = try Tag.fetchAll(db).sorted(by: areTagsInFoldOrder)
    var categories = try Category.fetchAll(db)
    var categoryIDByTagID: [Tag.ID: Category.ID] = [:]

    for tag in tags {
      let matchingRoots = categories
        .filter {
          $0.parentCategoryID == nil
            && $0.name.caseInsensitiveCompare(tag.name) == .orderedSame
        }
        .sorted(by: areCategoriesInFoldOrder)

      if var canonicalCategory = matchingRoots.first {
        for duplicate in matchingRoots.dropFirst() {
          canonicalCategory = try mergeCategory(duplicate, into: canonicalCategory, in: db)
        }
        if canonicalCategory.color == nil, let color = tag.color {
          canonicalCategory.color = color
          try Category.find(canonicalCategory.id).update {
            $0.color = #bind(color)
          }
          .execute(db)
        }
        categories = try Category.fetchAll(db)
        categoryIDByTagID[tag.id] = canonicalCategory.id
        continue
      }

      if let priorFold = categories.first(where: { $0.id == tag.id }) {
        // A user may have renamed or re-parented a category after an earlier fold. Its UUID is
        // still the durable bridge to this dormant tag, so preserve that user-authored shape.
        categoryIDByTagID[tag.id] = priorFold.id
        continue
      }

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

    var recipeCategories = try RecipeCategory.fetchAll(db)
    for recipeTag in try RecipeTag.fetchAll(db).sorted(by: areRecipeTagsInFoldOrder) {
      guard let categoryID = categoryIDByTagID[recipeTag.tagID] else { continue }
      guard !recipeCategories.contains(where: {
        $0.recipeID == recipeTag.recipeID && $0.categoryID == categoryID
      }) else { continue }
      guard !recipeCategories.contains(where: { $0.id == recipeTag.id }) else { continue }

      let recipeCategory = RecipeCategory(
        id: recipeTag.id,
        recipeID: recipeTag.recipeID,
        categoryID: categoryID
      )
      try RecipeCategory.insert { recipeCategory }.execute(db)
      recipeCategories.append(recipeCategory)
    }

    try deduplicateRecipeCategoryPairs(in: db)
  }

  public static func sortedCategories(_ categories: [Category]) -> [Category] {
    CategoryHierarchy.displayRows(from: categories).map(\.category)
  }

  public static func createCategory(
    name: String,
    parentCategoryID: Category.ID?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    let categories = try Category.fetchAll(db)
    let name = try normalizedName(name)
    try validateParent(parentCategoryID, categories: categories)
    try validateUniqueSiblingName(
      name,
      parentCategoryID: parentCategoryID,
      excluding: nil,
      categories: categories
    )

    let category = Category(
      id: uuid(),
      name: name,
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
    try validateMove(categoryID: categoryID, parentCategoryID: parentCategoryID, categories: categories)
    try validateUniqueSiblingName(
      name,
      parentCategoryID: parentCategoryID,
      excluding: categoryID,
      categories: categories
    )

    try Category.find(category.id).update {
      $0.name = name
      $0.parentCategoryID = parentCategoryID
    }
    .execute(db)
  }

  public static func deleteCategory(categoryID: Category.ID, in db: Database, now: Date) throws {
    let categories = try Category.fetchAll(db)
    _ = try category(categoryID, in: categories)
    guard !categories.contains(where: { $0.parentCategoryID == categoryID }) else {
      throw CategoryRepositoryError.cannotDeleteCategoryWithChildren
    }
    let recipeCategoryCount = try RecipeCategory
      .where { $0.categoryID.eq(categoryID) }
      .fetchAll(db)
      .count
    guard recipeCategoryCount == 0 else {
      throw CategoryRepositoryError.cannotDeleteCategoryUsedByRecipes
    }

    let seedIDs = Set(
      starterCategories
        .filter { $0.id == categoryID }
        .map(\.id)
        + (try CategorySeedState.fetchAll(db))
        .filter { $0.categoryID == categoryID }
        .map(\.id)
    )
    let existingTombstoneIDs = Set(try CategorySeedTombstone.fetchAll(db).map(\.id))
    for seedID in seedIDs where !existingTombstoneIDs.contains(seedID) {
      let tombstone = CategorySeedTombstone(id: seedID, dateDeleted: now)
      try CategorySeedTombstone.insert { tombstone }.execute(db)
    }
    try #sql("DELETE FROM \"categories\" WHERE \"id\" = \(bind: categoryID)").execute(db)
  }

  private static func updateSeedState(
    seedID: Category.ID,
    categoryID: Category.ID,
    seedStates: inout [Category.ID: CategorySeedState],
    in db: Database
  ) throws {
    guard var state = seedStates[seedID] else {
      let state = CategorySeedState(
        id: seedID,
        categoryID: categoryID,
        dateModified: starterCategoryDate
      )
      try CategorySeedState.insert { state }.execute(db)
      seedStates[seedID] = state
      return
    }
    guard state.categoryID != categoryID else { return }
    state.categoryID = categoryID
    try CategorySeedState.upsert { state }.execute(db)
    seedStates[seedID] = state
  }

  private static func removeTombstonedSeedCategory(
    _ seed: StarterCategory,
    categories: inout [Category],
    in db: Database
  ) throws {
    guard let category = categories.first(where: { $0.id == seed.id }) else { return }
    guard !categories.contains(where: { $0.parentCategoryID == category.id }) else { return }
    guard (try RecipeCategory.where { $0.categoryID.eq(category.id) }.fetchAll(db)).isEmpty else { return }
    try Category.find(category.id).delete().execute(db)
    categories.removeAll { $0.id == category.id }
  }

  private static func category(_ categoryID: Category.ID, in categories: [Category]) throws -> Category {
    guard let category = categories.first(where: { $0.id == categoryID }) else {
      throw CategoryRepositoryError.categoryNotFound
    }
    return category
  }

  private static func normalizedName(_ name: String) throws -> String {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw CategoryRepositoryError.emptyName }
    return name
  }

  private static func validateParent(_ parentCategoryID: Category.ID?, categories: [Category]) throws {
    guard let parentCategoryID else { return }
    guard categories.contains(where: { $0.id == parentCategoryID }) else {
      throw CategoryRepositoryError.parentNotFound
    }
  }

  private static func validateMove(
    categoryID: Category.ID,
    parentCategoryID: Category.ID?,
    categories: [Category]
  ) throws {
    try validateParent(parentCategoryID, categories: categories)
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
    let duplicate = categories.contains {
      $0.id != categoryID
        && $0.parentCategoryID == parentCategoryID
        && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }
    guard !duplicate else {
      throw CategoryRepositoryError.duplicateSibling(name: name)
    }
  }

  private static func nextSortOrder(parentCategoryID: Category.ID?, categories: [Category]) -> Int {
    (categories
      .filter { $0.parentCategoryID == parentCategoryID }
      .map(\.sortOrder)
      .max() ?? -1) + 1
  }

  private static func mergeCategory(
    _ duplicate: Category,
    into canonical: Category,
    in db: Database
  ) throws -> Category {
    guard duplicate.id != canonical.id else { return canonical }

    var canonical = canonical
    if canonical.color == nil, let color = duplicate.color {
      canonical.color = color
      try Category.find(canonical.id).update {
        $0.color = #bind(color)
      }
      .execute(db)
    }

    for var child in try Category.fetchAll(db) where child.parentCategoryID == duplicate.id {
      child.parentCategoryID = canonical.id
      try Category.upsert { child }.execute(db)
    }
    for var recipeCategory in try RecipeCategory.fetchAll(db) where recipeCategory.categoryID == duplicate.id {
      recipeCategory.categoryID = canonical.id
      try RecipeCategory.upsert { recipeCategory }.execute(db)
    }
    for var seedState in try CategorySeedState.fetchAll(db) where seedState.categoryID == duplicate.id {
      seedState.categoryID = canonical.id
      try CategorySeedState.upsert { seedState }.execute(db)
    }
    try deduplicateRecipeCategoryPairs(in: db)
    try Category.find(duplicate.id).delete().execute(db)
    return canonical
  }

  private static func deduplicateRecipeCategoryPairs(in db: Database) throws {
    let groups = Dictionary(grouping: try RecipeCategory.fetchAll(db)) {
      RecipeCategoryPair(recipeID: $0.recipeID, categoryID: $0.categoryID)
    }
    for rows in groups.values where rows.count > 1 {
      for duplicate in rows.sorted(by: areRecipeCategoriesInFoldOrder).dropFirst() {
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

  private static func areRecipeCategoriesInFoldOrder(
    _ lhs: RecipeCategory,
    _ rhs: RecipeCategory
  ) -> Bool {
    lhs.id.uuidString < rhs.id.uuidString
  }
}

private struct RecipeCategoryPair: Hashable {
  var recipeID: Recipe.ID
  var categoryID: Category.ID
}

private struct StarterCategory {
  var id: Category.ID
  var name: String
  var parentSeedID: Category.ID?
  var sortOrder: Int
}

private let starterCategoryDate = Date(timeIntervalSinceReferenceDate: 0)

private let starterCategories: [StarterCategory] = [
  .init(id: starterCategoryID(1), name: "Cuisine", parentSeedID: nil, sortOrder: 0),
  .init(id: starterCategoryID(2), name: "Course", parentSeedID: nil, sortOrder: 1),
  .init(id: starterCategoryID(3), name: "American", parentSeedID: starterCategoryID(1), sortOrder: 0),
  .init(id: starterCategoryID(4), name: "Chinese", parentSeedID: starterCategoryID(1), sortOrder: 1),
  .init(id: starterCategoryID(5), name: "French", parentSeedID: starterCategoryID(1), sortOrder: 2),
  .init(id: starterCategoryID(6), name: "Indian", parentSeedID: starterCategoryID(1), sortOrder: 3),
  .init(id: starterCategoryID(7), name: "Italian", parentSeedID: starterCategoryID(1), sortOrder: 4),
  .init(id: starterCategoryID(8), name: "Japanese", parentSeedID: starterCategoryID(1), sortOrder: 5),
  .init(id: starterCategoryID(9), name: "Korean", parentSeedID: starterCategoryID(1), sortOrder: 6),
  .init(id: starterCategoryID(10), name: "Mexican", parentSeedID: starterCategoryID(1), sortOrder: 7),
  .init(id: starterCategoryID(11), name: "Thai", parentSeedID: starterCategoryID(1), sortOrder: 8),
  .init(id: starterCategoryID(12), name: "Vietnamese", parentSeedID: starterCategoryID(1), sortOrder: 9),
  .init(id: starterCategoryID(13), name: "Breakfast", parentSeedID: starterCategoryID(2), sortOrder: 0),
  .init(id: starterCategoryID(14), name: "Lunch", parentSeedID: starterCategoryID(2), sortOrder: 1),
  .init(id: starterCategoryID(15), name: "Dinner", parentSeedID: starterCategoryID(2), sortOrder: 2),
  .init(id: starterCategoryID(16), name: "Appetizer", parentSeedID: starterCategoryID(2), sortOrder: 3),
  .init(id: starterCategoryID(17), name: "Side Dish", parentSeedID: starterCategoryID(2), sortOrder: 4),
  .init(id: starterCategoryID(18), name: "Dessert", parentSeedID: starterCategoryID(2), sortOrder: 5),
  .init(id: starterCategoryID(19), name: "Snack", parentSeedID: starterCategoryID(2), sortOrder: 6),
  .init(id: starterCategoryID(20), name: "Drink", parentSeedID: starterCategoryID(2), sortOrder: 7),
]

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
    let existingRecipeCategories = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    let validCategoryIDs = Set(try Category.fetchAll(db).map(\.id))
    var keptRecipeCategoryIDs: Set<RecipeCategory.ID> = []
    var seenCategoryIDs: Set<Category.ID> = []

    for categoryID in categoryIDs where validCategoryIDs.contains(categoryID) && !seenCategoryIDs.contains(categoryID) {
      seenCategoryIDs.insert(categoryID)
      let recipeCategory = RecipeCategory(
        id: existingRecipeCategories.first { $0.categoryID == categoryID }?.id ?? uuid(),
        recipeID: recipeID,
        categoryID: categoryID
      )
      keptRecipeCategoryIDs.insert(recipeCategory.id)
      try RecipeCategory.upsert { recipeCategory }.execute(db)
    }

    try deleteMissingRecipeCategories(existingRecipeCategories, keeping: keptRecipeCategoryIDs, in: db)
  }

  static func reconcileCategories(
    _ names: [String],
    looseNames: [String] = [],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    var existingCategories = try Category.fetchAll(db)
    try reconcileDuplicateCategories(in: db, categories: &existingCategories)
    let existingRecipeCategories = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    var recipeCategoryIDByCategoryID: [Category.ID: RecipeCategory.ID] = [:]
    for recipeCategory in existingRecipeCategories.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      recipeCategoryIDByCategoryID[recipeCategory.categoryID] = recipeCategoryIDByCategoryID[
        recipeCategory.categoryID
      ] ?? recipeCategory.id
    }
    var keptRecipeCategoryIDs: Set<RecipeCategory.ID> = []

    for path in CategoryHierarchy.paths(from: names) {
      let category = try findOrCreateCategory(
        path: path,
        existingCategories: &existingCategories,
        in: db,
        now: now,
        uuid: uuid
      )
      let recipeCategory = RecipeCategory(
        id: recipeCategoryIDByCategoryID[category.id] ?? uuid(),
        recipeID: recipeID,
        categoryID: category.id
      )
      recipeCategoryIDByCategoryID[category.id] = recipeCategory.id
      keptRecipeCategoryIDs.insert(recipeCategory.id)
      try RecipeCategory.upsert { recipeCategory }.execute(db)
    }

    for name in normalizedLooseCategoryNames(looseNames) {
      let category = try findOrCreateCategory(
        path: CategoryHierarchy.Path(components: [name]),
        existingCategories: &existingCategories,
        in: db,
        now: now,
        uuid: uuid
      )
      let recipeCategory = RecipeCategory(
        id: recipeCategoryIDByCategoryID[category.id] ?? uuid(),
        recipeID: recipeID,
        categoryID: category.id
      )
      recipeCategoryIDByCategoryID[category.id] = recipeCategory.id
      keptRecipeCategoryIDs.insert(recipeCategory.id)
      try RecipeCategory.upsert { recipeCategory }.execute(db)
    }

    try deleteMissingRecipeCategories(existingRecipeCategories, keeping: keptRecipeCategoryIDs, in: db)
  }

  private static func normalizedLooseCategoryNames(_ names: [String]) -> [String] {
    var seenNormalizedNames: Set<String> = []
    return names.compactMap { name in
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedName.isEmpty else { return nil }
      let normalizedName = trimmedName.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: .current
      )
      guard seenNormalizedNames.insert(normalizedName).inserted else { return nil }
      return trimmedName
    }
  }

  private static func findOrCreateCategory(
    path: CategoryHierarchy.Path,
    existingCategories: inout [Category],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    var parentCategoryID: Category.ID?
    var currentCategory: Category?

    for component in path.components {
      let category = existingCategories.first {
        $0.parentCategoryID == parentCategoryID
          && $0.name.caseInsensitiveCompare(component) == .orderedSame
      }
      ?? Category(
        id: uuid(),
        name: component,
        parentCategoryID: parentCategoryID,
        sortOrder: existingCategories.count,
        dateCreated: now
      )

      if !existingCategories.contains(where: { $0.id == category.id }) {
        try Category.insert { category }.execute(db)
        existingCategories.append(category)
      }

      currentCategory = category
      parentCategoryID = category.id
    }

    guard let currentCategory else { throw CategoryHierarchyError.emptyPath }
    return currentCategory
  }

  private static func deleteMissingRecipeCategories(
    _ rows: [RecipeCategory],
    keeping keptIDs: Set<RecipeCategory.ID>,
    in db: Database
  ) throws {
    for row in rows where !keptIDs.contains(row.id) {
      try #sql("DELETE FROM \"recipeCategories\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }

  private static func reconcileDuplicateCategories(
    in db: Database,
    categories: inout [Category]
  ) throws {
    var didMerge = true
    while didMerge {
      didMerge = false
      let groups = Dictionary(grouping: categories, by: CategoryLogicalKey.init)
      for group in groups.values where group.count > 1 {
        let sortedGroup = group.sorted(by: areCategoriesInCanonicalOrder)
        guard let canonicalCategory = sortedGroup.first else { continue }
        let duplicateCategories = sortedGroup.dropFirst()
        let duplicateCategoryIDs = Set(duplicateCategories.map(\.id))

        for var child in categories where child.parentCategoryID.map(duplicateCategoryIDs.contains) == true {
          child.parentCategoryID = canonicalCategory.id
          try Category.upsert { child }.execute(db)
        }

        for var recipeCategory in try RecipeCategory.fetchAll(db) where duplicateCategoryIDs.contains(recipeCategory.categoryID) {
          let hasCanonicalRecipeCategory = try RecipeCategory.fetchAll(db).contains {
            $0.recipeID == recipeCategory.recipeID && $0.categoryID == canonicalCategory.id
          }
          if hasCanonicalRecipeCategory {
            try RecipeCategory.find(recipeCategory.id).delete().execute(db)
          } else {
            recipeCategory.categoryID = canonicalCategory.id
            try RecipeCategory.upsert { recipeCategory }.execute(db)
          }
        }

        for category in duplicateCategories {
          try Category.find(category.id).delete().execute(db)
        }

        categories = try Category.fetchAll(db)
        didMerge = true
        break
      }
    }
  }

  private static func areCategoriesInCanonicalOrder(_ lhs: Category, _ rhs: Category) -> Bool {
    if lhs.dateCreated != rhs.dateCreated {
      return lhs.dateCreated < rhs.dateCreated
    }
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

private struct CategoryLogicalKey: Hashable {
  var parentCategoryID: Category.ID?
  var normalizedName: String

  init(category: Category) {
    self.parentCategoryID = category.parentCategoryID
    self.normalizedName = category.name
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
