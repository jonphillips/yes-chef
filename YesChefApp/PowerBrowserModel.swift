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

  struct SourceFilterOption: Identifiable, Equatable {
    var value: String
    var matchingRecipeCount: Int
    var isSelected: Bool

    var id: String { value }
  }

  struct LooseCategoryOption: Identifiable, Equatable {
    var category: YesChefCore.Category
    var matchingRecipeCount: Int
    var isSelected: Bool

    var id: YesChefCore.Category.ID { category.id }
  }

  struct ActiveSelection: Identifiable, Equatable {
    enum Kind: Hashable {
      case facet(categoryID: YesChefCore.Category.ID, facetID: Facet.ID)
      case looseCategory(categoryID: YesChefCore.Category.ID)
      case attribute(RecipeBrowserAttributeFilter)
      case source(field: RecipeBrowserSourceField, value: String)
    }

    var kind: Kind
    var title: String

    var id: String { title }
  }

  /// ADR-0050 D7 names this exact threshold ("cooked > 5×"); it is a product term,
  /// not a guessed engagement metric.
  static let frequentCookedThreshold = 5

  private enum AttributeKind {
    case totalTime
    case servings
    case rating
    case makeAhead
    case addedAfter
    case neverCooked
    case frequentCooking
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
  var totalTimeAtMostText = ""
  var servingsAtLeastText = ""
  var addedAfterDate = Date()

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
    query.text != nil
      || !query.facetSelections.isEmpty
      || !query.attributeFilters.isEmpty
      || !query.sourceFilters.isEmpty
      || !query.looseLabelIDs.isEmpty
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

  var activeSelections: [ActiveSelection] {
    let facetSelections = activeFacetSelections.map {
      ActiveSelection(
        kind: .facet(categoryID: $0.category.id, facetID: $0.facet.id),
        title: selectionTitle(for: $0.category.id, in: $0.facet)
      )
    }
    let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
    let looseCategorySelections: [ActiveSelection] = Array(query.looseLabelIDs).compactMap {
      (categoryID: YesChefCore.Category.ID) -> ActiveSelection? in
      guard let category = categoriesByID[categoryID], category.facetID == nil else { return nil }
      return ActiveSelection(
        kind: .looseCategory(categoryID: category.id),
        title: "Label: \(category.name)"
      )
    }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    let attributeSelections = query.attributeFilters.map {
      ActiveSelection(kind: .attribute($0), title: $0.title)
    }
    let sourceSelections = query.sourceFilters.flatMap { filter -> [ActiveSelection] in
      guard case let .values(field, values) = filter else { return [] }
      return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map {
        ActiveSelection(kind: .source(field: field, value: $0), title: "\(field.title): \($0)")
      }
    }
    return facetSelections + looseCategorySelections + attributeSelections + sourceSelections
  }

  var totalTimeAtMost: Int? {
    query.attributeFilters.lazy.compactMap { filter in
      guard case let .totalTimeAtMost(minutes) = filter else { return nil }
      return minutes
    }.first
  }

  var servingsAtLeast: Double? {
    query.attributeFilters.lazy.compactMap { filter in
      guard case let .servingsAtLeast(servings) = filter else { return nil }
      return servings
    }.first
  }

  var minimumRating: Int? {
    query.attributeFilters.lazy.compactMap { filter in
      guard case let .ratingAtLeast(rating) = filter else { return nil }
      return rating
    }.first
  }

  var requiresMakeAhead: Bool {
    attributeEnabled(.hasMakeAhead)
  }

  var requiresNeverCooked: Bool {
    attributeEnabled(.neverCooked)
  }

  var requiresFrequentCooking: Bool {
    attributeEnabled(.cookedMoreThan(Self.frequentCookedThreshold))
  }

  var filtersByAddedDate: Bool {
    query.attributeFilters.contains { filter in
      if case .addedAfter = filter { return true }
      return false
    }
  }

  func sourceFilterOptions(
    for result: RecipeBrowserResult
  ) -> [RecipeBrowserSourceField: [SourceFilterOption]] {
    let matchingRecipeIDs = Set(result.matchingRecipeIDs)
    let sourcesByRecipeID = Dictionary(grouping: browserData.sources, by: \.recipeID)

    return RecipeBrowserSourceField.allCases.reduce(into: [:]) { optionsByField, field in
      let selectedValues = selectedSourceValues(for: field)
      let currentValues = browserData.sources
        .filter { matchingRecipeIDs.contains($0.recipeID) }
        .compactMap { $0.value(for: field)?.trimmedNonEmpty }
      let values = Set(currentValues).union(selectedValues)

      optionsByField[field] = values
        .map { value in
          let normalizedValue = Self.normalizedSourceValue(value)
          let matchingRecipeCount = matchingRecipeIDs.reduce(into: 0) { count, recipeID in
            if (sourcesByRecipeID[recipeID] ?? []).contains(where: { source in
              guard let sourceValue = source.value(for: field)?.trimmedNonEmpty else { return false }
              return Self.normalizedSourceValue(sourceValue) == normalizedValue
            }) {
              count += 1
            }
          }
          return SourceFilterOption(
            value: value,
            matchingRecipeCount: matchingRecipeCount,
            isSelected: selectedValues.contains(value)
          )
        }
        .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }
  }

  func looseCategoryOptions(for result: RecipeBrowserResult) -> [LooseCategoryOption] {
    let matchingRecipeIDs = Set(result.matchingRecipeIDs)
    let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
    let categoryIDsByRecipeID = Dictionary(grouping: browserData.recipeCategories, by: \.recipeID)
      .mapValues { Set($0.map(\.categoryID)) }
    let currentCategoryIDs = matchingRecipeIDs.reduce(into: Set<YesChefCore.Category.ID>()) { categoryIDs, recipeID in
      categoryIDs.formUnion(categoryIDsByRecipeID[recipeID] ?? [])
    }
    let optionIDs = currentCategoryIDs.union(query.looseLabelIDs)

    return optionIDs.compactMap { categoryID in
      guard let category = categoriesByID[categoryID], category.facetID == nil else { return nil }
      let matchingRecipeCount = matchingRecipeIDs.reduce(into: 0) { count, recipeID in
        if categoryIDsByRecipeID[recipeID]?.contains(categoryID) == true {
          count += 1
        }
      }
      return LooseCategoryOption(
        category: category,
        matchingRecipeCount: matchingRecipeCount,
        isSelected: query.looseLabelIDs.contains(categoryID)
      )
    }
    .sorted {
      let nameComparison = $0.category.name.localizedStandardCompare($1.category.name)
      if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
      return $0.category.id.uuidString < $1.category.id.uuidString
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
    totalTimeAtMostText = ""
    servingsAtLeastText = ""
  }

  func totalTimeTextChanged() {
    let value = Int(totalTimeAtMostText.trimmingCharacters(in: .whitespacesAndNewlines))
    setAttribute(value.map(RecipeBrowserAttributeFilter.totalTimeAtMost), kind: .totalTime)
  }

  func servingsTextChanged() {
    let value = Double(servingsAtLeastText.trimmingCharacters(in: .whitespacesAndNewlines))
    setAttribute(value.map(RecipeBrowserAttributeFilter.servingsAtLeast), kind: .servings)
  }

  func minimumRatingChanged(_ rating: Int?) {
    setAttribute(rating.map(RecipeBrowserAttributeFilter.ratingAtLeast), kind: .rating)
  }

  func requiresMakeAheadChanged(_ isEnabled: Bool) {
    setAttribute(isEnabled ? .hasMakeAhead : nil, kind: .makeAhead)
  }

  func requiresNeverCookedChanged(_ isEnabled: Bool) {
    setAttribute(isEnabled ? .neverCooked : nil, kind: .neverCooked)
  }

  func requiresFrequentCookingChanged(_ isEnabled: Bool) {
    setAttribute(
      isEnabled ? .cookedMoreThan(Self.frequentCookedThreshold) : nil,
      kind: .frequentCooking
    )
  }

  func addedAfterChanged(_ isEnabled: Bool) {
    setAttribute(isEnabled ? .addedAfter(addedAfterDate) : nil, kind: .addedAfter)
  }

  func addedAfterDateChanged() {
    guard filtersByAddedDate else { return }
    setAttribute(.addedAfter(addedAfterDate), kind: .addedAfter)
  }

  func sourceValueButtonTapped(_ value: String, field: RecipeBrowserSourceField) {
    let existingValues = selectedSourceValues(for: field)
    var values = existingValues
    if values.contains(value) {
      values.remove(value)
    } else {
      values.insert(value)
    }
    setSourceValues(values, field: field)
  }

  func looseCategoryButtonTapped(_ category: YesChefCore.Category) {
    guard category.facetID == nil else { return }
    if query.looseLabelIDs.contains(category.id) {
      query.looseLabelIDs.remove(category.id)
    } else {
      query.looseLabelIDs.insert(category.id)
    }
  }

  func selectedSourceValues(for field: RecipeBrowserSourceField) -> Set<String> {
    query.sourceFilters.reduce(into: Set<String>()) { result, filter in
      guard case let .values(filterField, values) = filter, filterField == field else { return }
      result.formUnion(values)
    }
  }

  func removeSelectionButtonTapped(_ selection: ActiveSelection) {
    switch selection.kind {
    case let .facet(categoryID, facetID):
      removeSelectionButtonTapped(categoryID: categoryID, in: facetID)
    case let .looseCategory(categoryID):
      query.looseLabelIDs.remove(categoryID)
    case let .attribute(filter):
      query.attributeFilters.removeAll { $0 == filter }
      switch filter {
      case .totalTimeAtMost:
        totalTimeAtMostText = ""
      case .servingsAtLeast:
        servingsAtLeastText = ""
      default:
        break
      }
    case let .source(field, value):
      var values = selectedSourceValues(for: field)
      values.remove(value)
      setSourceValues(values, field: field)
    }
  }

  private func setAttribute(_ filter: RecipeBrowserAttributeFilter?, kind: AttributeKind) {
    query.attributeFilters.removeAll { attributeKind(of: $0) == kind }
    if let filter { query.attributeFilters.append(filter) }
  }

  private func attributeEnabled(_ filter: RecipeBrowserAttributeFilter) -> Bool {
    query.attributeFilters.contains(filter)
  }

  private func setSourceValues(_ values: Set<String>, field: RecipeBrowserSourceField) {
    query.sourceFilters.removeAll { filter in
      guard case let .values(existingField, _) = filter else { return false }
      return existingField == field
    }
    guard !values.isEmpty else { return }
    query.sourceFilters.append(.values(field: field, values: values))
  }

  private func attributeKind(of filter: RecipeBrowserAttributeFilter) -> AttributeKind? {
    switch filter {
    case .totalTimeAtMost: .totalTime
    case .servingsAtLeast: .servings
    case .ratingAtLeast: .rating
    case .hasMakeAhead: .makeAhead
    case .addedAfter: .addedAfter
    case .neverCooked: .neverCooked
    case .cookedMoreThan: .frequentCooking
    case .libraryPlacement, .favoritesOnly, .hasPhoto:
      nil
    }
  }

  private static func normalizedSourceValue(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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

private extension String {
  var trimmedNonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension RecipeBrowserAttributeFilter {
  var title: String {
    switch self {
    case let .libraryPlacement(placement): "Library: \(placement.title)"
    case .favoritesOnly: "Favorites"
    case .hasPhoto: "With photos"
    case let .totalTimeAtMost(minutes): "Up to \(minutes) min"
    case let .servingsAtLeast(servings): "At least \(servings.formatted()) servings"
    case let .ratingAtLeast(rating): "Rating \(rating)+"
    case .hasMakeAhead: "Make-ahead"
    case let .addedAfter(date): "Added after \(date.formatted(date: .abbreviated, time: .omitted))"
    case .neverCooked: "Never cooked"
    case let .cookedMoreThan(count): "Cooked more than \(count) times"
    }
  }
}

extension RecipeBrowserSourceField {
  var title: String {
    switch self {
    case .name: "Source"
    case .author: "Author"
    case .cookbook: "Cookbook"
    case .publication: "Publication"
    case .website: "Website"
    }
  }
}
