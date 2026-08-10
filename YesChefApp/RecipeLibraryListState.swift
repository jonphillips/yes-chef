import Foundation
import YesChefCore

extension RecipeLibraryModel {
  var currentListPresetState: RecipeListPresetState {
    RecipeListPresetState(
      searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
      sortOrder: sortOrder,
      libraryScope: libraryScope,
      showsFavoritesOnly: showsFavoritesOnly,
      showsPhotosOnly: showsPhotosOnly,
      selectedCategoryNames: selectedCategoryNames.sortedForPresetState(),
      selectedCuisine: selectedCuisine,
      selectedCourse: selectedCourse,
      selectedSourceNames: selectedSourceNames.sortedForPresetState(),
      selectedAuthorNames: selectedAuthorNames.sortedForPresetState()
    )
  }

  var visibleRecipeRows: [RecipeListRowData] {
    let rowsByID = Dictionary(uniqueKeysWithValues: recipeRows.map { ($0.recipe.id, $0) })
    return RecipeBrowserEngine(
      recipes: browserData.recipes,
      recipeCategories: browserData.recipeCategories,
      categories: browserData.categories,
      facets: browserData.facets,
      sources: browserData.sources,
      variations: browserData.variations,
      recipeIDsWithPhotos: browserData.recipeIDsWithPhotos
    )
    .matchingRecipeIDs(for: browserQuery)
    .compactMap { rowsByID[$0] }
  }

  var filteredRecipeCount: Int {
    visibleRecipeRows.count
  }

  var hasActiveFilters: Bool {
    showsFavoritesOnly
      || showsPhotosOnly
      || libraryScope != .main
      || !selectedCategoryNames.isEmpty
      || !selectedSourceNames.isEmpty
      || !selectedAuthorNames.isEmpty
  }

  var activeFilterFacets: [RecipeActiveFilterFacet] {
    var facets: [RecipeActiveFilterFacet] = []
    if libraryScope != .main {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .library,
          detail: libraryScope.title,
          selectionCount: 1
        )
      )
    }
    if showsFavoritesOnly {
      facets.append(RecipeActiveFilterFacet(kind: .favorites, selectionCount: 1))
    }
    if showsPhotosOnly {
      facets.append(RecipeActiveFilterFacet(kind: .photos, selectionCount: 1))
    }
    if !selectedCategoryNames.isEmpty {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .categories,
          detail: selectedFilterDetail(selectedCategoryNames),
          selectionCount: selectedCategoryNames.count
        )
      )
    }
    if !selectedSourceNames.isEmpty {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .sources,
          detail: selectedFilterDetail(selectedSourceNames),
          selectionCount: selectedSourceNames.count
        )
      )
    }
    if !selectedAuthorNames.isEmpty {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .authors,
          detail: selectedFilterDetail(selectedAuthorNames),
          selectionCount: selectedAuthorNames.count
        )
      )
    }
    return facets
  }

  var filteredRecipeCountSummary: String {
    "\(filteredRecipeCount) of \(unarchivedRecipeRows.count) \(unarchivedRecipeRows.count == 1 ? "recipe" : "recipes")"
  }

  var sortStatusTitle: String {
    "Sorted by \(sortOrder.title)"
  }

  var categoryFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.flatMap(\.categoryFilterNames))
  }

  var categoryFilterAvailabilityByName: [String: RecipeCategoryFilterAvailability] {
    let categoryNames = distinctOptions(categoryFilterOptions + Array(selectedCategoryNames))
    var matchingRecipeCounts = Dictionary(uniqueKeysWithValues: categoryNames.map { ($0, 0) })

    for categoryName in categoryNames {
      var prospectiveSelections = selectedCategoryNames
      prospectiveSelections.insert(categoryName)
      let count = matchingRecipeCount(categoryNames: prospectiveSelections)
      matchingRecipeCounts[categoryName] = count
    }

    return Dictionary(
      uniqueKeysWithValues: categoryNames.map { categoryName in
        (
          categoryName,
          RecipeCategoryFilterAvailability(
            categoryName: categoryName,
            matchingRecipeCount: matchingRecipeCounts[categoryName, default: 0],
            isSelected: selectedCategoryNames.contains(categoryName)
          )
        )
      }
    )
  }

  var sourceFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap(\.filterSourceName))
  }

  var sourceFilterCountsByName: [String: Int] {
    optionCounts(unarchivedRecipeRows.compactMap(\.filterSourceName))
  }

  var popularSourceFilterOptions: [String] {
    popularOptions(unarchivedRecipeRows.compactMap(\.filterSourceName), limit: 10)
  }

  var remainingSourceFilterOptions: [String] {
    remainingOptions(all: sourceFilterOptions, popular: popularSourceFilterOptions)
  }

  var authorFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap { $0.source?.author.nonEmpty })
  }

  var authorFilterCountsByName: [String: Int] {
    optionCounts(unarchivedRecipeRows.compactMap { $0.source?.author.nonEmpty })
  }

  var popularAuthorFilterOptions: [String] {
    popularOptions(unarchivedRecipeRows.compactMap { $0.source?.author.nonEmpty }, limit: 10)
  }

  var remainingAuthorFilterOptions: [String] {
    remainingOptions(all: authorFilterOptions, popular: popularAuthorFilterOptions)
  }

  var selectedCategoryFilterSummary: String {
    guard !selectedCategoryNames.isEmpty else { return "All categories" }
    return selectedCategoryNames
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      .joined(separator: ", ")
  }

  var selectedSourceFilterSummary: String {
    selectedFilterSummary(selectedSourceNames, emptyTitle: "All sources")
  }

  var selectedAuthorFilterSummary: String {
    selectedFilterSummary(selectedAuthorNames, emptyTitle: "All authors")
  }

  var selectedRecipe: Recipe? {
    recipeRows.first { $0.recipe.id == selectedRecipeID && !$0.recipe.archived }?.recipe
  }

  func filterButtonTapped() {
    destination = .filterRecipes
  }

  func clearFiltersButtonTapped() {
    showsFavoritesOnly = false
    showsPhotosOnly = false
    libraryScope = .main
    selectedCategoryNames = []
    selectedCuisine = nil
    selectedCourse = nil
    selectedSourceNames = []
    selectedAuthorNames = []
  }

  func clearFilterFacetButtonTapped(_ kind: RecipeFilterFacetKind) {
    switch kind {
    case .library:
      libraryScope = .main
    case .favorites:
      showsFavoritesOnly = false
    case .photos:
      showsPhotosOnly = false
    case .categories:
      selectedCategoryNames = []
    case .sources:
      selectedSourceNames = []
    case .authors:
      selectedAuthorNames = []
    }
  }

  func doneFilteringButtonTapped() {
    destination = nil
  }

  func applyListPreset(_ preset: RecipeListPreset) {
    applyListPresetState(preset.state)
  }

  func recipeCount(for preset: RecipeListPreset) -> Int {
    recipeCount(for: preset.state)
  }

  func recipeCount(for state: RecipeListPresetState) -> Int {
    RecipeBrowserEngine(
      recipes: browserData.recipes,
      recipeCategories: browserData.recipeCategories,
      categories: browserData.categories,
      facets: browserData.facets,
      sources: browserData.sources,
      variations: browserData.variations,
      recipeIDsWithPhotos: browserData.recipeIDsWithPhotos
    )
    .matchingRecipeIDs(for: browserQuery(from: state)).count
  }

  func categoryFilterButtonTapped(_ categoryName: String) {
    if selectedCategoryNames.contains(categoryName) {
      selectedCategoryNames.remove(categoryName)
    } else {
      selectedCategoryNames.insert(categoryName)
    }
  }

  func sourceFilterButtonTapped(_ sourceName: String) {
    if selectedSourceNames.contains(sourceName) {
      selectedSourceNames.remove(sourceName)
    } else {
      selectedSourceNames.insert(sourceName)
    }
  }

  func authorFilterButtonTapped(_ authorName: String) {
    if selectedAuthorNames.contains(authorName) {
      selectedAuthorNames.remove(authorName)
    } else {
      selectedAuthorNames.insert(authorName)
    }
  }

  private var unarchivedRecipeRows: [RecipeListRowData] {
    recipeRows.filter { !$0.recipe.archived }
  }

  private func applyListPresetState(_ state: RecipeListPresetState) {
    searchText = state.searchText
    sortOrder = state.sortOrder
    libraryScope = state.libraryScope
    showsFavoritesOnly = state.showsFavoritesOnly
    showsPhotosOnly = state.showsPhotosOnly
    var categoryNames = canonicalCategoryNames(for: state.selectedCategoryNames)
    // Older saved list views stored Cuisine/Course as free text. Resolve those values once
    // against the corresponding facet, then leave the retired fields empty.
    for (value, facetName) in [(state.selectedCuisine, "Cuisine"), (state.selectedCourse, "Course")] {
      guard let category = legacyFacetValue(value, facetNamed: facetName) else { continue }
      let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
      categoryNames.insert(CategoryHierarchy.displayName(for: category, categoriesByID: categoriesByID))
    }
    selectedCategoryNames = categoryNames
    selectedCuisine = nil
    selectedCourse = nil
    selectedSourceNames = Set(state.selectedSourceNames)
    selectedAuthorNames = Set(state.selectedAuthorNames)
  }

  private var browserQuery: RecipeBrowserQuery {
    browserQuery(
      searchText: searchText,
      sortOrder: sortOrder,
      libraryScope: libraryScope,
      showsFavoritesOnly: showsFavoritesOnly,
      showsPhotosOnly: showsPhotosOnly,
      categoryNames: selectedCategoryNames,
      selectedCuisine: selectedCuisine,
      selectedCourse: selectedCourse,
      sourceNames: selectedSourceNames,
      authorNames: selectedAuthorNames
    )
  }

  private func browserQuery(from state: RecipeListPresetState) -> RecipeBrowserQuery {
    browserQuery(
      searchText: state.searchText,
      sortOrder: state.sortOrder,
      libraryScope: state.libraryScope,
      showsFavoritesOnly: state.showsFavoritesOnly,
      showsPhotosOnly: state.showsPhotosOnly,
      categoryNames: Set(state.selectedCategoryNames),
      selectedCuisine: state.selectedCuisine,
      selectedCourse: state.selectedCourse,
      sourceNames: Set(state.selectedSourceNames),
      authorNames: Set(state.selectedAuthorNames)
    )
  }

  private func browserQuery(
    searchText: String,
    sortOrder: RecipeListSort,
    libraryScope: RecipeLibraryScope,
    showsFavoritesOnly: Bool,
    showsPhotosOnly: Bool,
    categoryNames: Set<String>,
    selectedCuisine: String?,
    selectedCourse: String?,
    sourceNames: Set<String>,
    authorNames: Set<String>
  ) -> RecipeBrowserQuery {
    let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
    var selectedCategories = browserData.categories.filter { category in
      let displayNames = CategoryHierarchy.filterDisplayNames(for: category, categoriesByID: categoriesByID)
      return categoryNames.contains { selected in
        displayNames.contains { $0.caseInsensitiveCompare(selected) == .orderedSame }
      }
    }
    selectedCategories += [
      legacyFacetValue(selectedCuisine, facetNamed: "Cuisine"),
      legacyFacetValue(selectedCourse, facetNamed: "Course"),
    ]
    .compactMap(\.self)
    let facetSelections = Dictionary(grouping: selectedCategories.compactMap { category in
      category.facetID.map { ($0, category.id) }
    }, by: \.0)
    .map { RecipeBrowserQuery.FacetSelection(facetID: $0.key, categoryIDs: Set($0.value.map(\.1))) }
    let looseLabelIDs = Set(selectedCategories.filter { $0.facetID == nil }.map(\.id))

    var attributeFilters: [RecipeBrowserAttributeFilter] = []
    switch libraryScope {
    case .main:
      attributeFilters.append(.libraryPlacement(.main))
    case .reference:
      attributeFilters.append(.libraryPlacement(.reference))
    case .all:
      break
    }
    if showsFavoritesOnly { attributeFilters.append(.favoritesOnly) }
    if showsPhotosOnly { attributeFilters.append(.hasPhoto) }

    var sourceFilters: [RecipeBrowserSourceFilter] = []
    if !sourceNames.isEmpty { sourceFilters.append(.values(field: .name, values: sourceNames)) }
    if !authorNames.isEmpty { sourceFilters.append(.values(field: .author, values: authorNames)) }

    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return RecipeBrowserQuery(
      text: trimmedSearchText.isEmpty ? nil : trimmedSearchText,
      facetSelections: facetSelections,
      attributeFilters: attributeFilters,
      sourceFilters: sourceFilters,
      looseLabelIDs: looseLabelIDs,
      sort: sortOrder.browserSort
    )
  }

  private func matchingRecipeCount(categoryNames: Set<String>) -> Int {
    let query = browserQuery(
      searchText: searchText,
      sortOrder: sortOrder,
      libraryScope: libraryScope,
      showsFavoritesOnly: showsFavoritesOnly,
      showsPhotosOnly: showsPhotosOnly,
      categoryNames: categoryNames,
      selectedCuisine: selectedCuisine,
      selectedCourse: selectedCourse,
      sourceNames: selectedSourceNames,
      authorNames: selectedAuthorNames
    )
    return RecipeBrowserEngine(
      recipes: browserData.recipes,
      recipeCategories: browserData.recipeCategories,
      categories: browserData.categories,
      facets: browserData.facets,
      sources: browserData.sources,
      variations: browserData.variations,
      recipeIDsWithPhotos: browserData.recipeIDsWithPhotos
    )
    .matchingRecipeIDs(for: query).count
  }

  private func legacyFacetValue(_ value: String?, facetNamed facetName: String) -> YesChefCore.Category? {
    guard
      let value,
      let facetID = browserData.facets.first(where: {
        $0.name.caseInsensitiveCompare(facetName) == .orderedSame
      })?.id
    else { return nil }
    return browserData.categories.first {
      $0.facetID == facetID && $0.name.caseInsensitiveCompare(value) == .orderedSame
    }
  }

  private func canonicalCategoryNames(for names: [String]) -> Set<String> {
    Set(
      names.map { selectedName in
        categoryFilterOptions.first {
          $0.caseInsensitiveCompare(selectedName) == .orderedSame
        } ?? selectedName
      }
    )
  }

  private func distinctOptions(_ values: [String]) -> [String] {
    Array(Set(normalizedOptions(values)))
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private func popularOptions(_ values: [String], limit: Int) -> [String] {
    let counts = optionCounts(values)

    return counts
      .sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
      }
      .prefix(limit)
      .map(\.key)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private func optionCounts(_ values: [String]) -> [String: Int] {
    Dictionary(grouping: normalizedOptions(values), by: { $0 })
      .mapValues { $0.count }
  }

  private func normalizedOptions(_ values: [String]) -> [String] {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func remainingOptions(all options: [String], popular: [String]) -> [String] {
    let popularSet = Set(popular)
    return options.filter { !popularSet.contains($0) }
  }

  private func selectedFilterSummary(_ values: Set<String>, emptyTitle: String) -> String {
    guard !values.isEmpty else { return emptyTitle }
    return values
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      .joined(separator: ", ")
  }

  private func selectedFilterDetail(_ values: Set<String>) -> String {
    let sortedValues = values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    let visibleValues = sortedValues.prefix(2)
    let remainingCount = sortedValues.count - visibleValues.count
    let visibleSummary = visibleValues.joined(separator: ", ")
    guard remainingCount > 0 else { return visibleSummary }
    return "\(visibleSummary) + \(remainingCount) more"
  }
}

enum RecipeListSort: String, CaseIterable, Codable, Identifiable, Sendable {
  case title
  case newest
  case recentlyModified
  case cookTime
  case recentlyCooked

  var id: Self { self }

  var title: String {
    switch self {
    case .title: "Title"
    case .newest: "Newest"
    case .recentlyModified: "Recently Modified"
    case .cookTime: "Cook Time"
    case .recentlyCooked: "Last Cooked"
    }
  }
}

private extension RecipeListSort {
  var browserSort: RecipeBrowserSort {
    switch self {
    case .title: .title
    case .newest: .newest
    case .recentlyModified: .recentlyModified
    case .cookTime: .cookTime
    case .recentlyCooked: .recentlyCooked
    }
  }
}

enum RecipeLibraryScope: String, CaseIterable, Codable, Identifiable, Sendable {
  case main
  case reference
  case all

  var id: Self { self }

  var title: String {
    switch self {
    case .main: "Main"
    case .reference: "Reference"
    case .all: "All"
    }
  }
}

extension RecipeLibraryPlacement {
  var title: String {
    switch self {
    case .main: "Main Library"
    case .reference: "Reference"
    }
  }

  var badgeTitle: String {
    switch self {
    case .main: "Main"
    case .reference: "Reference"
    }
  }
}

private extension RecipeListRowData {
  var filterSourceName: String? {
    source?.name.nonEmpty
      ?? source?.publicationName.nonEmpty
      ?? source?.bookTitle.nonEmpty
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension Set where Element == String {
  func sortedForPresetState() -> [String] {
    sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}

private extension Optional where Wrapped == String {
  var nonEmpty: String? {
    flatMap(\.nonEmpty)
  }
}
