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
      selectedTagNames: selectedTagNames.sortedForPresetState(),
      selectedCuisine: selectedCuisine,
      selectedCourse: selectedCourse,
      selectedSourceNames: selectedSourceNames.sortedForPresetState(),
      selectedAuthorNames: selectedAuthorNames.sortedForPresetState()
    )
  }

  var visibleRecipeRows: [RecipeListRowData] {
    unarchivedRecipeRows
      .filter { row in
        matchesSearch(row)
          && matchesFilters(row)
      }
      .sorted(by: areInIncreasingOrder)
  }

  var filteredRecipeCount: Int {
    unarchivedRecipeRows
      .filter { row in
        matchesSearch(row)
          && matchesFilters(row)
      }
      .count
  }

  var hasActiveFilters: Bool {
    showsFavoritesOnly
      || showsPhotosOnly
      || libraryScope != .main
      || !selectedCategoryNames.isEmpty
      || !selectedTagNames.isEmpty
      || selectedCuisine != nil
      || selectedCourse != nil
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
    if !selectedTagNames.isEmpty {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .tags,
          detail: selectedFilterDetail(selectedTagNames),
          selectionCount: selectedTagNames.count
        )
      )
    }
    if let selectedCuisine {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .cuisine,
          detail: selectedCuisine,
          selectionCount: 1
        )
      )
    }
    if let selectedCourse {
      facets.append(
        RecipeActiveFilterFacet(
          kind: .course,
          detail: selectedCourse,
          selectionCount: 1
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
    let categoryNameSet = Set(categoryNames)
    var matchingRecipeCounts = Dictionary(uniqueKeysWithValues: categoryNames.map { ($0, 0) })

    for row in unarchivedRecipeRows where matchesSearch(row) && matchesFilters(row, categoryNames: []) {
      let rowCategoryNames = Set(row.categoryFilterNames)
      guard selectedCategoryNames.isSubset(of: rowCategoryNames) else { continue }

      for categoryName in rowCategoryNames where categoryNameSet.contains(categoryName) {
        matchingRecipeCounts[categoryName, default: 0] += 1
      }
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

  var tagFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.flatMap(\.tagNames))
  }

  var cuisineFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap(\.recipe.cuisine))
  }

  var courseFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap(\.recipe.course))
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
    recipeRows.first { $0.recipe.id == selectedRecipeID }?.recipe
  }

  func filterButtonTapped() {
    destination = .filterRecipes
  }

  func clearFiltersButtonTapped() {
    showsFavoritesOnly = false
    showsPhotosOnly = false
    libraryScope = .main
    selectedCategoryNames = []
    selectedTagNames = []
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
    case .tags:
      selectedTagNames = []
    case .cuisine:
      selectedCuisine = nil
    case .course:
      selectedCourse = nil
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
    unarchivedRecipeRows
      .filter { row in
        matchesSearch(row, searchText: state.searchText)
          && matchesFilters(row, state: state)
      }
      .count
  }

  func tagFilterButtonTapped(_ tagName: String) {
    if selectedTagNames.contains(tagName) {
      selectedTagNames.remove(tagName)
    } else {
      selectedTagNames.insert(tagName)
    }
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
    selectedCategoryNames = Set(state.selectedCategoryNames)
    selectedTagNames = Set(state.selectedTagNames)
    selectedCuisine = state.selectedCuisine
    selectedCourse = state.selectedCourse
    selectedSourceNames = Set(state.selectedSourceNames)
    selectedAuthorNames = Set(state.selectedAuthorNames)
  }

  private func matchesSearch(_ row: RecipeListRowData) -> Bool {
    matchesSearch(row, searchText: searchText)
  }

  private func matchesSearch(_ row: RecipeListRowData, searchText: String) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    let recipe = row.recipe
    return recipe.title.localizedCaseInsensitiveContains(query)
      || (recipe.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
      || (recipe.summary?.localizedCaseInsensitiveContains(query) ?? false)
      || (recipe.cuisine?.localizedCaseInsensitiveContains(query) ?? false)
      || (recipe.course?.localizedCaseInsensitiveContains(query) ?? false)
      || row.sourceSearchValues.contains { $0.localizedCaseInsensitiveContains(query) }
      || row.categoryNames.contains { $0.localizedCaseInsensitiveContains(query) }
      || row.tagNames.contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func matchesFilters(_ row: RecipeListRowData) -> Bool {
    matchesFilters(row, categoryNames: selectedCategoryNames)
  }

  private func matchesFilters(_ row: RecipeListRowData, categoryNames: Set<String>) -> Bool {
    matchesFilters(
      row,
      libraryScope: libraryScope,
      showsFavoritesOnly: showsFavoritesOnly,
      showsPhotosOnly: showsPhotosOnly,
      categoryNames: categoryNames,
      tagNames: selectedTagNames,
      selectedCuisine: selectedCuisine,
      selectedCourse: selectedCourse,
      sourceNames: selectedSourceNames,
      authorNames: selectedAuthorNames
    )
  }

  private func matchesFilters(_ row: RecipeListRowData, state: RecipeListPresetState) -> Bool {
    matchesFilters(
      row,
      libraryScope: state.libraryScope,
      showsFavoritesOnly: state.showsFavoritesOnly,
      showsPhotosOnly: state.showsPhotosOnly,
      categoryNames: Set(state.selectedCategoryNames),
      tagNames: Set(state.selectedTagNames),
      selectedCuisine: state.selectedCuisine,
      selectedCourse: state.selectedCourse,
      sourceNames: Set(state.selectedSourceNames),
      authorNames: Set(state.selectedAuthorNames)
    )
  }

  private func matchesFilters(
    _ row: RecipeListRowData,
    libraryScope: RecipeLibraryScope,
    showsFavoritesOnly: Bool,
    showsPhotosOnly: Bool,
    categoryNames: Set<String>,
    tagNames: Set<String>,
    selectedCuisine: String?,
    selectedCourse: String?,
    sourceNames: Set<String>,
    authorNames: Set<String>
  ) -> Bool {
    let recipe = row.recipe
    switch libraryScope {
    case .main where recipe.libraryPlacement != .main:
      return false
    case .reference where recipe.libraryPlacement != .reference:
      return false
    case .all, .main, .reference:
      break
    }
    if showsFavoritesOnly && !recipe.favorite { return false }
    if showsPhotosOnly && !row.hasPhoto { return false }
    if !categoryNames.isEmpty,
       !categoryNames.isSubset(of: Set(row.categoryFilterNames)) {
      return false
    }
    if !tagNames.isEmpty, !tagNames.isSubset(of: Set(row.tagNames)) {
      return false
    }
    if let selectedCuisine, recipe.cuisine != selectedCuisine {
      return false
    }
    if let selectedCourse, recipe.course != selectedCourse {
      return false
    }
    if !sourceNames.isEmpty,
       !sourceNames.contains(row.filterSourceName ?? "") {
      return false
    }
    if !authorNames.isEmpty,
       !authorNames.contains(row.source?.author.nonEmpty ?? "") {
      return false
    }
    return true
  }

  private func areInIncreasingOrder(_ lhs: RecipeListRowData, _ rhs: RecipeListRowData) -> Bool {
    switch sortOrder {
    case .title:
      titleSort(lhs.recipe, rhs.recipe)
    case .newest:
      descendingDateSort(lhs.recipe.dateCreated, rhs.recipe.dateCreated, lhs.recipe, rhs.recipe)
    case .recentlyModified:
      descendingDateSort(lhs.recipe.dateModified, rhs.recipe.dateModified, lhs.recipe, rhs.recipe)
    case .cookTime:
      optionalIntSort(lhs.recipe.listCookTimeMinutes, rhs.recipe.listCookTimeMinutes, lhs.recipe, rhs.recipe)
    case .recentlyCooked:
      optionalDateSort(lhs.recipe.lastCookedAt, rhs.recipe.lastCookedAt, lhs.recipe, rhs.recipe)
    }
  }

  private func titleSort(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
    lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }

  private func descendingDateSort(_ lhsDate: Date, _ rhsDate: Date, _ lhs: Recipe, _ rhs: Recipe) -> Bool {
    if lhsDate != rhsDate {
      return lhsDate > rhsDate
    }
    return titleSort(lhs, rhs)
  }

  private func optionalDateSort(
    _ lhsDate: Date?,
    _ rhsDate: Date?,
    _ lhs: Recipe,
    _ rhs: Recipe
  ) -> Bool {
    switch (lhsDate, rhsDate) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
      lhsDate > rhsDate
    case (nil, nil), (_?, _?):
      titleSort(lhs, rhs)
    case (_?, nil):
      true
    case (nil, _?):
      false
    }
  }

  private func optionalIntSort(
    _ lhsValue: Int?,
    _ rhsValue: Int?,
    _ lhs: Recipe,
    _ rhs: Recipe
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case let (lhsValue?, rhsValue?) where lhsValue != rhsValue:
      lhsValue < rhsValue
    case (nil, nil), (_?, _?):
      titleSort(lhs, rhs)
    case (_?, nil):
      true
    case (nil, _?):
      false
    }
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

private extension Recipe {
  var listCookTimeMinutes: Int? {
    if let totalTimeMinutes {
      return totalTimeMinutes
    }
    let parts = [prepTimeMinutes, cookTimeMinutes, activeTimeMinutes].compactMap { $0 }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0, +)
  }
}

private extension RecipeListRowData {
  var filterSourceName: String? {
    source?.name.nonEmpty
      ?? source?.publicationName.nonEmpty
      ?? source?.bookTitle.nonEmpty
  }

  var sourceSearchValues: [String] {
    [
      source?.name,
      source?.url,
      source?.author,
      source?.publicationName,
      source?.bookTitle,
      source?.pageNumber,
      source?.sourceNotes,
    ]
    .compactMap { $0?.nonEmpty }
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
