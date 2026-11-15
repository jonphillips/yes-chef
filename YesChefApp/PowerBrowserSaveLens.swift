import Dependencies
import SQLiteData
import YesChefCore

extension PowerBrowserModel {
  func saveAsLensButtonTapped() {
    destination = .saveLens
  }

  @discardableResult
  func saveLensButtonTapped(name: String) -> RecipeLens.ID? {
    guard scope == .mine else { return nil }
    do {
      return try database.write { db in
        try RecipeLensRepository.create(
          name: name, baseQuery: query, sortOrder: lensLibrary.lenses.count,
          in: db, now: now, uuid: { uuid() }
        ).id
      }
    } catch {
      lensError = error.localizedDescription
      return nil
    }
  }

  func selectionLabels(for query: RecipeBrowserQuery) -> [String] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: browserData.categories.map { ($0.id, $0) })
    let facetsByID = Dictionary(uniqueKeysWithValues: browserData.facets.map { ($0.id, $0) })
    var labels = query.facetSelections.flatMap { selection -> [String] in
      guard let facet = facetsByID[selection.facetID] else { return ["Unresolved facet"] }
      return selection.categoryIDs.compactMap { id in
        guard let category = categoriesByID[id] else { return "Unresolved value" }
        return "\(facet.name): \(CategoryHierarchy.displayName(for: category, categoriesByID: categoriesByID))"
      }
    }
    labels += query.looseLabelIDs.compactMap { categoriesByID[$0].map { "Label: \($0.name)" } ?? "Unresolved label" }
    labels += query.attributeFilters.map(\.lensTitle)
    labels += query.sourceFilters.flatMap { filter -> [String] in
      guard case let .values(field, values) = filter else { return [] }
      return values.sorted().map { "\(field.title): \($0)" }
    }
    if let text = query.text { labels.append("Search: \(text)") }
    return labels
  }
}

private extension RecipeBrowserAttributeFilter {
  var lensTitle: String {
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
