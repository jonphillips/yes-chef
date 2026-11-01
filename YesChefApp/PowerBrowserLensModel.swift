import Dependencies
import Foundation
import SQLiteData
import YesChefCore

extension PowerBrowserModel {
  func lensSelectionChanged(_ id: RecipeLens.ID?, using lensOverride: RecipeLens? = nil) {
    if id != nil, id == pendingRestoredLensID {
      pendingRestoredLensID = nil
      selectedLensID = id
      queryEditTarget = nil
      return
    }
    selectedLensID = id
    if id == nil, queryEditTarget != nil { return }
    if id != nil { queryEditTarget = nil }
    guard let id, let lens = lensOverride ?? lensLibrary.lenses.first(where: { $0.id == id }) else {
      query = RecipeBrowserQuery()
      return
    }
    guard let baseQuery = try? RecipeLensQueryCodec.decode(lens.baseQuery) else {
      lensError = "This Lens has a damaged base query and needs repair."
      return
    }
    query = baseQuery
  }

  func saveAsLensButtonTapped() {
    destination = .saveLens
  }

  var isEditingSavedQuery: Bool { queryEditTarget != nil }

  func editLensBaseQueryButtonTapped(_ lens: RecipeLens) {
    query = (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()
    selectedLensID = nil
    queryEditTarget = .lensBase(lens.id)
    destination = nil
  }

  func editShelfQueryButtonTapped(_ shelf: RecipeLensShelf) {
    guard let query = try? RecipeLensQueryCodec.decode(shelf.query) else {
      lensError = "This shelf query could not be decoded. Choose a new query to replace it."
      queryEditTarget = .shelf(shelf.id, lensID: shelf.lensID)
      selectedLensID = nil
      destination = nil
      return
    }
    self.query = query
    selectedLensID = nil
    queryEditTarget = .shelf(shelf.id, lensID: shelf.lensID)
    destination = nil
  }

  func saveQueryEditsButtonTapped() {
    guard let queryEditTarget else { return }
    do {
      let restoredLensID: RecipeLens.ID = switch queryEditTarget {
      case let .lensBase(id): id
      case let .shelf(_, lensID): lensID
      }
      try database.write { db in
        switch queryEditTarget {
        case let .lensBase(id):
          try RecipeLensRepository.setBaseQuery(lensID: id, to: query, in: db, now: now)
        case let .shelf(id, _):
          try RecipeLensRepository.setShelfQuery(shelfID: id, to: query, in: db)
        }
      }
      self.queryEditTarget = nil
      pendingRestoredLensID = restoredLensID
      selectedLensID = restoredLensID
    } catch { lensError = error.localizedDescription }
  }

  func deleteLensButtonTapped(_ lens: RecipeLens) {
    do {
      try database.write { db in try RecipeLensRepository.delete(lens, in: db) }
      if selectedLensID == lens.id { selectedLensID = nil }
      destination = nil
    } catch { lensError = error.localizedDescription }
  }

  func editLensButtonTapped() {
    guard let selectedLensID else { return }
    destination = .editLens(selectedLensID)
  }

  func presentShelf(_ shelf: RecipeLensShelf) {
    guard case let .ready(ids) = lensEvaluation?.shelves.first(where: { $0.shelf.id == shelf.id })?.state else { return }
    destination = .seeAll(title: shelf.title, recipeIDs: ids)
  }

  func presentRemainder() {
    guard let evaluation = lensEvaluation else { return }
    destination = .seeAll(title: "Everything else", recipeIDs: evaluation.remainderRecipeIDs)
  }

  func saveLensButtonTapped(name: String) {
    do {
      try database.write { db in
        _ = try RecipeLensRepository.create(
          name: name, baseQuery: query, sortOrder: lensLibrary.lenses.count,
          in: db, now: now, uuid: { uuid() }
        )
      }
      destination = nil
    } catch {
      lensError = error.localizedDescription
    }
  }

  @discardableResult
  func addShelfButtonTapped(lensID: RecipeLens.ID, title: String, query: RecipeBrowserQuery) -> RecipeLensShelf? {
    do {
      return try database.write { db in
        try RecipeLensRepository.addShelf(
          lensID: lensID, title: title, query: query, in: db, uuid: { uuid() }
        )
      }
    } catch {
      lensError = error.localizedDescription
      return nil
    }
  }

  func newShelfButtonTapped(lensID: RecipeLens.ID) {
    guard let shelf = addShelfButtonTapped(
      lensID: lensID, title: "New shelf", query: RecipeBrowserQuery()
    ) else { return }
    editShelfQueryButtonTapped(shelf)
  }

  func renameLensButtonTapped(_ lens: RecipeLens, name: String) {
    do {
      try database.write { db in try RecipeLensRepository.rename(lens, to: name, in: db, now: now) }
    } catch { lensError = error.localizedDescription }
  }

  func deleteShelfButtonTapped(_ shelf: RecipeLensShelf) {
    do { try database.write { db in try RecipeLensRepository.removeShelf(shelf, in: db) } }
    catch { lensError = error.localizedDescription }
  }

  func renameShelfButtonTapped(_ shelf: RecipeLensShelf, title: String) {
    do { try database.write { db in try RecipeLensRepository.renameShelf(shelf, to: title, in: db) } }
    catch { lensError = error.localizedDescription }
  }

  func reorderShelvesButtonTapped(_ ids: [RecipeLensShelf.ID], lensID: RecipeLens.ID) {
    do { try database.write { db in try RecipeLensRepository.reorderShelves(lensID: lensID, orderedIDs: ids, in: db) } }
    catch { lensError = error.localizedDescription }
  }

  func showsRemainderChanged(_ value: Bool, lens: RecipeLens) {
    do { try database.write { db in try RecipeLensRepository.setShowsRemainder(lens, to: value, in: db, now: now) } }
    catch { lensError = error.localizedDescription }
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
