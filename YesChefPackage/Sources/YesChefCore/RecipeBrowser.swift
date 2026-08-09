import Foundation
import SQLiteData

public struct RecipeBrowserQuery: Codable, Hashable, Sendable {
  public var text: String?
  public var facetSelections: [FacetSelection]
  public var looseLabelIDs: Set<Category.ID>
  public var sort: RecipeBrowserSort

  public init(
    text: String? = nil,
    facetSelections: [FacetSelection] = [],
    looseLabelIDs: Set<Category.ID> = [],
    sort: RecipeBrowserSort = .title
  ) {
    self.text = text
    self.facetSelections = facetSelections
    self.looseLabelIDs = looseLabelIDs
    self.sort = sort
  }

  public struct FacetSelection: Codable, Hashable, Sendable {
    public var facetID: Facet.ID
    public var categoryIDs: Set<Category.ID>

    public init(facetID: Facet.ID, categoryIDs: Set<Category.ID>) {
      self.facetID = facetID
      self.categoryIDs = categoryIDs
    }
  }
}

public enum RecipeBrowserSort: String, CaseIterable, Codable, Hashable, Sendable {
  case title
  case newest
  case recentlyModified
  case cookTime
  case recentlyCooked
}

public struct RecipeBrowserResult: Equatable, Sendable {
  public var matchingRecipeIDs: [Recipe.ID]
  public var availableFacets: [FacetAvailability]

  public init(matchingRecipeIDs: [Recipe.ID], availableFacets: [FacetAvailability]) {
    self.matchingRecipeIDs = matchingRecipeIDs
    self.availableFacets = availableFacets
  }

  public struct FacetAvailability: Identifiable, Equatable, Sendable {
    public var facet: Facet
    public var values: [ValueAvailability]
    public var narrowingPotential: Int

    public var id: Facet.ID { facet.id }

    public init(facet: Facet, values: [ValueAvailability], narrowingPotential: Int) {
      self.facet = facet
      self.values = values
      self.narrowingPotential = narrowingPotential
    }
  }

  public struct ValueAvailability: Identifiable, Equatable, Sendable {
    public var category: Category
    public var matchingRecipeCount: Int
    public var isSelected: Bool

    public var id: Category.ID { category.id }

    public init(category: Category, matchingRecipeCount: Int, isSelected: Bool) {
      self.category = category
      self.matchingRecipeCount = matchingRecipeCount
      self.isSelected = isSelected
    }
  }
}

public struct RecipeBrowserRecipe: Equatable, Sendable {
  public var id: Recipe.ID
  public var title: String
  public var subtitle: String?
  public var summary: String?
  public var cuisine: String?
  public var course: String?
  public var dateCreated: Date
  public var dateModified: Date
  public var totalTimeMinutes: Int?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var activeTimeMinutes: Int?
  public var lastCookedAt: Date?
  public var archived: Bool

  public init(
    id: Recipe.ID,
    title: String,
    subtitle: String? = nil,
    summary: String? = nil,
    cuisine: String? = nil,
    course: String? = nil,
    dateCreated: Date,
    dateModified: Date,
    totalTimeMinutes: Int? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    activeTimeMinutes: Int? = nil,
    lastCookedAt: Date? = nil,
    archived: Bool = false
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.summary = summary
    self.cuisine = cuisine
    self.course = course
    self.dateCreated = dateCreated
    self.dateModified = dateModified
    self.totalTimeMinutes = totalTimeMinutes
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.activeTimeMinutes = activeTimeMinutes
    self.lastCookedAt = lastCookedAt
    self.archived = archived
  }
}

public struct RecipeBrowserSource: Equatable, Sendable {
  public var recipeID: Recipe.ID
  public var searchValues: [String]

  public init(recipeID: Recipe.ID, searchValues: [String]) {
    self.recipeID = recipeID
    self.searchValues = searchValues
  }
}

public struct RecipeBrowserVariation: Equatable, Sendable {
  public var recipeID: Recipe.ID
  public var name: String

  public init(recipeID: Recipe.ID, name: String) {
    self.recipeID = recipeID
    self.name = name
  }
}

public struct RecipeBrowserEngine: Sendable {
  private let recipesByID: [Recipe.ID: RecipeBrowserRecipe]
  private let recipeCategoryIDsByRecipeID: [Recipe.ID: Set<Category.ID>]
  private let categoriesByID: [Category.ID: Category]
  private let categoriesByFacetID: [Facet.ID: [Category]]
  private let facets: [Facet]
  private let descendantIDsByCategoryID: [Category.ID: Set<Category.ID>]
  private let ancestorIDsByCategoryID: [Category.ID: Set<Category.ID>]
  private let sourceSearchValuesByRecipeID: [Recipe.ID: [String]]
  private let variationNamesByRecipeID: [Recipe.ID: [String]]

  public init(
    recipes: [RecipeBrowserRecipe],
    recipeCategories: [RecipeCategory],
    categories: [Category],
    facets: [Facet],
    sources: [RecipeBrowserSource] = [],
    variations: [RecipeBrowserVariation] = []
  ) {
    let visibleCategories = CategoryRepository.visibleCategories(categories, facets: facets)
    let visibleCategoryIDs = Set(visibleCategories.map(\.id))
    self.recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    self.recipeCategoryIDsByRecipeID = Dictionary(grouping: recipeCategories, by: \.recipeID)
      .mapValues { Set($0.map(\.categoryID)).intersection(visibleCategoryIDs) }
    self.categoriesByID = Dictionary(uniqueKeysWithValues: visibleCategories.map { ($0.id, $0) })
    self.categoriesByFacetID = Dictionary(grouping: visibleCategories.compactMap { category in
      category.facetID.map { ($0, category) }
    }, by: \.0)
    .mapValues { pairs in
      CategoryRepository.sortedCategories(pairs.map(\.1))
    }
    self.facets = CategoryRepository.sortedFacets(facets.filter { !$0.hidden })
    self.descendantIDsByCategoryID = Dictionary(
      uniqueKeysWithValues: visibleCategories.map { category in
        (category.id, CategoryHierarchy.descendantIDs(of: category.id, in: visibleCategories))
      }
    )
    let visibleCategoriesByID = Dictionary(uniqueKeysWithValues: visibleCategories.map { ($0.id, $0) })
    self.ancestorIDsByCategoryID = Dictionary(
      uniqueKeysWithValues: visibleCategories.map { category in
        (category.id, Self.ancestorIDs(of: category, categoriesByID: visibleCategoriesByID))
      }
    )
    self.sourceSearchValuesByRecipeID = Dictionary(grouping: sources, by: \.recipeID)
      .mapValues { $0.flatMap(\.searchValues) }
    self.variationNamesByRecipeID = Dictionary(grouping: variations, by: \.recipeID)
      .mapValues { $0.map(\.name) }
  }

  public func result(for query: RecipeBrowserQuery) -> RecipeBrowserResult {
    let matchingRecipeIDs = matchingRecipeIDs(for: query)
    let availableFacets = self.availableFacets(for: query, matchingRecipeIDs: Set(matchingRecipeIDs))
    return RecipeBrowserResult(matchingRecipeIDs: matchingRecipeIDs, availableFacets: availableFacets)
  }

  public func matchingRecipeIDs(for query: RecipeBrowserQuery) -> [Recipe.ID] {
    recipesByID.values
      .filter { recipe in matches(recipe, query: query, excludingFacetID: nil) }
      .sorted { areInIncreasingOrder($0, $1, sort: query.sort) }
      .map(\.id)
  }

  private func availableFacets(
    for query: RecipeBrowserQuery,
    matchingRecipeIDs: Set<Recipe.ID>
  ) -> [RecipeBrowserResult.FacetAvailability] {
    let selectedCategoryIDsByFacetID = selectedCategoryIDsByFacetID(from: query)
    return facets.compactMap { facet in
      let selfExcludedRecipeIDs = Set(
        recipesByID.values
          .filter { matches($0, query: query, excludingFacetID: facet.id) }
          .map(\.id)
      )
      let selectedCategoryIDs = selectedCategoryIDsByFacetID[facet.id] ?? []
      let matchingRecipeIDsByCategoryID = matchingRecipeIDsByCategoryID(
        for: selfExcludedRecipeIDs,
        facetID: facet.id
      )
      let values = (categoriesByFacetID[facet.id] ?? []).map { category in
        return RecipeBrowserResult.ValueAvailability(
          category: category,
          matchingRecipeCount: matchingRecipeIDs.union(matchingRecipeIDsByCategoryID[category.id] ?? []).count,
          isSelected: selectedCategoryIDs.contains(category.id)
        )
      }
      let displayedValues = values.filter {
        $0.isSelected || ($0.matchingRecipeCount > 0 && $0.matchingRecipeCount != matchingRecipeIDs.count)
      }
      let viableValues = displayedValues.filter { $0.matchingRecipeCount > 0 }
      guard viableValues.count >= 2 else { return nil }
      guard viableValues.contains(where: { $0.matchingRecipeCount != matchingRecipeIDs.count }) else { return nil }
      let largestValueCount = viableValues.map(\.matchingRecipeCount).max() ?? 0
      return RecipeBrowserResult.FacetAvailability(
        facet: facet,
        values: displayedValues,
        narrowingPotential: selfExcludedRecipeIDs.count - largestValueCount
      )
    }
    .sorted { lhs, rhs in
      if lhs.facet.sortOrder != rhs.facet.sortOrder {
        return lhs.facet.sortOrder < rhs.facet.sortOrder
      }
      if lhs.narrowingPotential != rhs.narrowingPotential {
        return lhs.narrowingPotential > rhs.narrowingPotential
      }
      let nameComparison = lhs.facet.name.localizedStandardCompare(rhs.facet.name)
      if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private func matches(
    _ recipe: RecipeBrowserRecipe,
    query: RecipeBrowserQuery,
    excludingFacetID: Facet.ID?
  ) -> Bool {
    guard !recipe.archived else { return false }
    guard matchesText(recipe, text: query.text) else { return false }
    guard matchesLooseLabels(recipe, selectedCategoryIDs: query.looseLabelIDs) else { return false }
    return matchesFacetSelections(recipe, query: query, excludingFacetID: excludingFacetID)
  }

  private func matchesText(_ recipe: RecipeBrowserRecipe, text: String?) -> Bool {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
    let categoryNames = (recipeCategoryIDsByRecipeID[recipe.id] ?? []).compactMap { categoryID in
      categoriesByID[categoryID].map { CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID) }
    }
    return RecipeSearchMatcher.matches(
      query: text,
      in: [
        recipe.title,
        recipe.subtitle,
        recipe.summary,
        recipe.cuisine,
        recipe.course,
      ]
      .compactMap(\.self)
      + categoryNames
      + (sourceSearchValuesByRecipeID[recipe.id] ?? [])
      + (variationNamesByRecipeID[recipe.id] ?? [])
    )
  }

  private func matchesLooseLabels(
    _ recipe: RecipeBrowserRecipe,
    selectedCategoryIDs: Set<Category.ID>
  ) -> Bool {
    guard !selectedCategoryIDs.isEmpty else { return true }
    let assignedCategoryIDs = recipeCategoryIDsByRecipeID[recipe.id] ?? []
    return selectedCategoryIDs.isSubset(of: assignedCategoryIDs)
  }

  private func matchesFacetSelections(
    _ recipe: RecipeBrowserRecipe,
    query: RecipeBrowserQuery,
    excludingFacetID: Facet.ID? = nil
  ) -> Bool {
    let assignedCategoryIDs = recipeCategoryIDsByRecipeID[recipe.id] ?? []
    return selectedCategoryIDsByFacetID(from: query).allSatisfy { facetID, selectedCategoryIDs in
      guard facetID != excludingFacetID else { return true }
      let expandedCategoryIDs = selectedCategoryIDs.reduce(into: Set<Category.ID>()) { result, categoryID in
        guard categoriesByID[categoryID]?.facetID == facetID else { return }
        result.insert(categoryID)
        result.formUnion(descendantIDsByCategoryID[categoryID] ?? [])
      }
      return !expandedCategoryIDs.isEmpty && !assignedCategoryIDs.isDisjoint(with: expandedCategoryIDs)
    }
  }

  private func selectedCategoryIDsByFacetID(
    from query: RecipeBrowserQuery
  ) -> [Facet.ID: Set<Category.ID>] {
    Dictionary(grouping: query.facetSelections, by: \.facetID)
      .mapValues { selections in
        selections.reduce(into: Set<Category.ID>()) { result, selection in
          result.formUnion(selection.categoryIDs)
        }
      }
      .filter { !$0.value.isEmpty }
  }

  private func matchingRecipeIDsByCategoryID(
    for recipeIDs: Set<Recipe.ID>,
    facetID: Facet.ID
  ) -> [Category.ID: Set<Recipe.ID>] {
    var recipeIDsByCategoryID: [Category.ID: Set<Recipe.ID>] = [:]
    for recipeID in recipeIDs {
      for categoryID in recipeCategoryIDsByRecipeID[recipeID] ?? [] {
        guard categoriesByID[categoryID]?.facetID == facetID else { continue }
        for ancestorID in ancestorIDsByCategoryID[categoryID] ?? [] {
          recipeIDsByCategoryID[ancestorID, default: []].insert(recipeID)
        }
      }
    }
    return recipeIDsByCategoryID
  }

  private static func ancestorIDs(
    of category: Category,
    categoriesByID: [Category.ID: Category]
  ) -> Set<Category.ID> {
    var ids: Set<Category.ID> = [category.id]
    var current = category
    while let parentID = current.parentCategoryID,
          let parent = categoriesByID[parentID],
          !ids.contains(parent.id) {
      ids.insert(parent.id)
      current = parent
    }
    return ids
  }

  private func areInIncreasingOrder(
    _ lhs: RecipeBrowserRecipe,
    _ rhs: RecipeBrowserRecipe,
    sort: RecipeBrowserSort
  ) -> Bool {
    switch sort {
    case .title:
      titleOrder(lhs, rhs)
    case .newest:
      descendingDateOrder(lhs.dateCreated, rhs.dateCreated, lhs, rhs)
    case .recentlyModified:
      descendingDateOrder(lhs.dateModified, rhs.dateModified, lhs, rhs)
    case .cookTime:
      optionalIntOrder(lhs.cookTimeMinutes, rhs.cookTimeMinutes, lhs, rhs)
    case .recentlyCooked:
      optionalDateOrder(lhs.lastCookedAt, rhs.lastCookedAt, lhs, rhs)
    }
  }

  private func titleOrder(_ lhs: RecipeBrowserRecipe, _ rhs: RecipeBrowserRecipe) -> Bool {
    let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
    if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private func descendingDateOrder(
    _ lhsDate: Date,
    _ rhsDate: Date,
    _ lhs: RecipeBrowserRecipe,
    _ rhs: RecipeBrowserRecipe
  ) -> Bool {
    if lhsDate != rhsDate { return lhsDate > rhsDate }
    return titleOrder(lhs, rhs)
  }

  private func optionalDateOrder(
    _ lhsDate: Date?,
    _ rhsDate: Date?,
    _ lhs: RecipeBrowserRecipe,
    _ rhs: RecipeBrowserRecipe
  ) -> Bool {
    switch (lhsDate, rhsDate) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
      lhsDate > rhsDate
    case (nil, nil), (_?, _?):
      titleOrder(lhs, rhs)
    case (_?, nil):
      true
    case (nil, _?):
      false
    }
  }

  private func optionalIntOrder(
    _ lhsValue: Int?,
    _ rhsValue: Int?,
    _ lhs: RecipeBrowserRecipe,
    _ rhs: RecipeBrowserRecipe
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case let (lhsValue?, rhsValue?) where lhsValue != rhsValue:
      lhsValue < rhsValue
    case (nil, nil), (_?, _?):
      titleOrder(lhs, rhs)
    case (_?, nil):
      true
    case (nil, _?):
      false
    }
  }
}

public extension RecipeRepository {
  static func browserResult(for query: RecipeBrowserQuery, in db: Database) throws -> RecipeBrowserResult {
    let recipes = try Recipe
      .select {
        RecipeBrowserRecipeRow.Columns(
          id: $0.id,
          title: $0.title,
          subtitle: $0.subtitle,
          summary: $0.summary,
          cuisine: $0.cuisine,
          course: $0.course,
          dateCreated: $0.dateCreated,
          dateModified: $0.dateModified,
          totalTimeMinutes: $0.totalTimeMinutes,
          prepTimeMinutes: $0.prepTimeMinutes,
          cookTimeMinutes: $0.cookTimeMinutes,
          activeTimeMinutes: $0.activeTimeMinutes,
          lastCookedAt: $0.lastCookedAt,
          archived: $0.archived
        )
      }
      .fetchAll(db)
      .map(\.browserRecipe)
    let sources = try RecipeSource.fetchAll(db).map { source in
      RecipeBrowserSource(
        recipeID: source.recipeID,
        searchValues: [
          source.name,
          source.url,
          source.author,
          source.publicationName,
          source.bookTitle,
          source.pageNumber,
          source.sourceNotes,
        ]
        .compactMap { $0?.nonEmpty }
      )
    }
    let variations = try RecipeVariation
      .select {
        RecipeBrowserVariationRow.Columns(recipeID: $0.recipeID, name: $0.name)
      }
      .fetchAll(db)
      .map { RecipeBrowserVariation(recipeID: $0.recipeID, name: $0.name) }
    return RecipeBrowserEngine(
      recipes: recipes,
      recipeCategories: try RecipeCategory.fetchAll(db),
      categories: try Category.fetchAll(db),
      facets: try Facet.fetchAll(db),
      sources: sources,
      variations: variations
    )
    .result(for: query)
  }
}

@Selection
private struct RecipeBrowserRecipeRow: Equatable, Sendable {
  let id: Recipe.ID
  let title: String
  let subtitle: String?
  let summary: String?
  let cuisine: String?
  let course: String?
  let dateCreated: Date
  let dateModified: Date
  let totalTimeMinutes: Int?
  let prepTimeMinutes: Int?
  let cookTimeMinutes: Int?
  let activeTimeMinutes: Int?
  let lastCookedAt: Date?
  let archived: Bool

  var browserRecipe: RecipeBrowserRecipe {
    RecipeBrowserRecipe(
      id: id,
      title: title,
      subtitle: subtitle,
      summary: summary,
      cuisine: cuisine,
      course: course,
      dateCreated: dateCreated,
      dateModified: dateModified,
      totalTimeMinutes: totalTimeMinutes,
      prepTimeMinutes: prepTimeMinutes,
      cookTimeMinutes: cookTimeMinutes,
      activeTimeMinutes: activeTimeMinutes,
      lastCookedAt: lastCookedAt,
      archived: archived
    )
  }
}

@Selection
private struct RecipeBrowserVariationRow: Equatable, Sendable {
  let recipeID: Recipe.ID
  let name: String
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
