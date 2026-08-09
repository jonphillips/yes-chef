import Foundation
import Observation
import SQLiteData
import YesChefCore

@Observable
@MainActor
final class PowerBrowserModel {
  private struct CachedEngine {
    var data: RecipeBrowserData
    var engine: RecipeBrowserEngine
  }

  private struct CachedResult {
    var query: RecipeBrowserQuery
    var result: RecipeBrowserResult
  }

  struct FacetSelection: Identifiable, Equatable {
    var facet: Facet
    var category: YesChefCore.Category

    var id: YesChefCore.Category.ID { category.id }
  }

  @ObservationIgnored
  @Fetch(RecipeBrowserDataRequest(), animation: .default) var browserData = RecipeBrowserData(
    recipes: [], recipeCategories: [], categories: [], facets: []
  )
  @ObservationIgnored
  @Fetch(RecipeListRequest(), animation: .default) var recipeRows: [RecipeListRowData] = []
  @ObservationIgnored private var cachedEngine: CachedEngine?
  @ObservationIgnored private var cachedResult: CachedResult?
  @ObservationIgnored private var hasSeededFacetExpansion = false

  var query = RecipeBrowserQuery()
  var expandedFacetIDs: Set<Facet.ID> = []

  var searchText: String {
    get { query.text ?? "" }
    set {
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      query.text = trimmed.isEmpty ? nil : newValue
    }
  }

  var result: RecipeBrowserResult {
    let engine = browserEngine()
    if let cachedResult, cachedResult.query == query {
      return cachedResult.result
    }
    let result = engine.result(for: query)
    cachedResult = CachedResult(query: query, result: result)
    return result
  }

  var hasActiveSelections: Bool {
    query.text != nil || !query.facetSelections.isEmpty || !query.looseLabelIDs.isEmpty
  }

  var activeFacetSelections: [FacetSelection] {
    let facetsByID = Dictionary(uniqueKeysWithValues: browserData.facets.map { ($0.id, $0) })
    let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
    return query.facetSelections
      .flatMap { selection in
        selection.categoryIDs.compactMap { categoryID in
          guard let facet = facetsByID[selection.facetID], let category = categoriesByID[categoryID] else {
            return nil
          }
          return FacetSelection(facet: facet, category: category)
        }
      }
      .sorted { lhs, rhs in
        if lhs.facet.sortOrder != rhs.facet.sortOrder {
          return lhs.facet.sortOrder < rhs.facet.sortOrder
        }
        return lhs.category.name.localizedStandardCompare(rhs.category.name) == .orderedAscending
      }
  }

  func recipeRows(for result: RecipeBrowserResult) -> [RecipeListRowData] {
    let rowsByID = Dictionary(uniqueKeysWithValues: recipeRows.map { ($0.recipe.id, $0) })
    return result.matchingRecipeIDs.compactMap { rowsByID[$0] }
  }

  func selectionTitle(for categoryID: YesChefCore.Category.ID, in facet: Facet) -> String {
    guard let category = browserData.categories.first(where: { $0.id == categoryID }) else {
      return facet.name
    }
    let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
    return "\(facet.name): \(CategoryHierarchy.displayName(for: category, categoriesByID: categoriesByID))"
  }

  func availableFacetsAppeared(_ facetIDs: [Facet.ID]) {
    guard !hasSeededFacetExpansion, let facetID = facetIDs.first else { return }
    expandedFacetIDs.insert(facetID)
    hasSeededFacetExpansion = true
  }

  func facetValueButtonTapped(_ category: YesChefCore.Category, in facet: Facet) {
    guard category.facetID == facet.id else { return }

    if let index = query.facetSelections.firstIndex(where: { $0.facetID == facet.id }) {
      if query.facetSelections[index].categoryIDs.contains(category.id) {
        query.facetSelections[index].categoryIDs.remove(category.id)
        if query.facetSelections[index].categoryIDs.isEmpty {
          query.facetSelections.remove(at: index)
        }
      } else {
        query.facetSelections[index].categoryIDs.insert(category.id)
      }
    } else {
      query.facetSelections.append(.init(facetID: facet.id, categoryIDs: [category.id]))
    }
  }

  func removeSelectionButtonTapped(categoryID: YesChefCore.Category.ID, in facetID: Facet.ID) {
    guard let index = query.facetSelections.firstIndex(where: { $0.facetID == facetID }) else { return }
    query.facetSelections[index].categoryIDs.remove(categoryID)
    if query.facetSelections[index].categoryIDs.isEmpty {
      query.facetSelections.remove(at: index)
    }
  }

  func clearButtonTapped() {
    query = RecipeBrowserQuery()
  }

  private func browserEngine() -> RecipeBrowserEngine {
    if let cachedEngine, cachedEngine.data == browserData {
      return cachedEngine.engine
    }
    let engine = RecipeBrowserEngine(
      recipes: browserData.recipes,
      recipeCategories: browserData.recipeCategories,
      categories: browserData.categories,
      facets: browserData.facets,
      sources: browserData.sources,
      variations: browserData.variations
    )
    cachedEngine = CachedEngine(data: browserData, engine: engine)
    cachedResult = nil
    return engine
  }
}
