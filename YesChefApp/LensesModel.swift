import Dependencies
import Observation
import SQLiteData
import YesChefCore

@Observable
@MainActor
final class LensesModel {
  private struct CachedEvaluation {
    var lens: RecipeLens
    var shelves: [RecipeLensShelf]
    var data: RecipeBrowserData
    var evaluation: RecipeLensEvaluation
  }

  enum Destination: Identifiable {
    case newLens
    case query(QueryContext)

    enum QueryContext: Equatable {
      case newBase
      case editBase(RecipeLens.ID)
      case addShelf(RecipeLens.ID)
      case editShelf(RecipeLensShelf.ID, lensID: RecipeLens.ID)
    }

    var id: String {
      switch self {
      case .newLens: "newLens"
      case let .query(context): String(describing: context)
      }
    }
  }

  let scope: LibraryScope
  let browser: PowerBrowserModel
  @ObservationIgnored
  @Fetch(RecipeLensLibraryRequest(), animation: .default) var lensLibrary = RecipeLensLibrary(lenses: [], shelves: [])
  var openLensID: RecipeLens.ID?
  private(set) var activeLens: RecipeLens?
  var isEditing = false
  var destination: Destination?
  var errorMessage: String?
  var pendingDelete: RecipeLens?
  var lensBeingRenamed: RecipeLens?
  var lensRenameDraft = ""

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored private var cachedEvaluation: CachedEvaluation?

  init(scope: LibraryScope = .mine) {
    self.scope = scope
    self.browser = PowerBrowserModel(scope: scope)
  }

  var openLens: RecipeLens? { lensLibrary.lenses.first { $0.id == openLensID } ?? activeLens }
  var shelves: [RecipeLensShelf] {
    guard let openLensID else { return [] }
    return lensLibrary.shelves.filter { $0.lensID == openLensID }.sorted { $0.sortOrder < $1.sortOrder }
  }
  var evaluation: RecipeLensEvaluation? {
    guard let openLens else { return nil }
    let currentShelves = self.shelves
    let data = browser.browserData
    if let cachedEvaluation, cachedEvaluation.lens == openLens,
      cachedEvaluation.shelves == currentShelves, cachedEvaluation.data == data {
      return cachedEvaluation.evaluation
    }
    let engine = RecipeBrowserEngine(
      recipes: data.recipes,
      recipeCategories: data.recipeCategories,
      categories: data.categories,
      facets: data.facets,
      sources: data.sources,
      variations: data.variations,
      recipeIDsWithPhotos: data.recipeIDsWithPhotos
    )
    let evaluation = RecipeLensEvaluator.evaluate(
      lens: openLens, shelves: currentShelves, using: engine, facets: data.facets, categories: data.categories
    )
    cachedEvaluation = CachedEvaluation(lens: openLens, shelves: currentShelves, data: data, evaluation: evaluation)
    return evaluation
  }

  func open(_ lens: RecipeLens, editing: Bool = false) {
    openLensID = lens.id
    activeLens = lens
    isEditing = editing && scope == .mine
    browser.query = (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()
  }

  func open(id: RecipeLens.ID, editing: Bool = false) {
    openLensID = id
    isEditing = editing && scope == .mine
    guard let lens = lensLibrary.lenses.first(where: { $0.id == id }) else { return }
    activeLens = lens
    browser.query = (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()
  }

  func closeLens() {
    openLensID = nil
    activeLens = nil
    isEditing = false
  }

  @discardableResult
  func createFromValue(_ category: Category, facet: Facet) -> RecipeLens.ID? {
    guard scope == .mine else { return nil }
    let query = RecipeBrowserQuery(facetSelections: [
      .init(facetID: facet.id, categoryIDs: [category.id])
    ])
    return createLens(name: category.name, query: query)
  }

  @discardableResult
  func createLens(name: String, query: RecipeBrowserQuery) -> RecipeLens.ID? {
    guard scope == .mine else { return nil }
    do {
      let created = try database.write { db in
        try RecipeLensRepository.create(
          name: name, baseQuery: query, sortOrder: lensLibrary.lenses.count,
          in: db, now: now, uuid: { uuid() }
        )
      }
      destination = nil
      open(created, editing: true)
      return created.id
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func saveAsLens(name: String, query: RecipeBrowserQuery, onLensCreated: (RecipeLens.ID) -> Void) {
    guard let id = createLens(name: name, query: query) else { return }
    onLensCreated(id)
  }

  func recipeTapped(_ id: Recipe.ID) -> RecipeDetailPresentation {
    RecipeDetailPresentation(recipeID: id, scope: scope)
  }

  func addSuggestedShelf(_ value: RecipeBrowserResult.ValueAvailability, facet: Facet) {
    guard scope == .mine, let lens = openLens else { return }
    let query = RecipeBrowserQuery(facetSelections: [
      .init(facetID: facet.id, categoryIDs: [value.category.id])
    ])
    do {
      _ = try database.write { db in
        try RecipeLensRepository.addShelf(
          lensID: lens.id, title: value.category.name, query: query, in: db, uuid: { uuid() }
        )
      }
    } catch { errorMessage = error.localizedDescription }
  }

  func addCustomShelf(title: String, query: RecipeBrowserQuery) {
    guard scope == .mine, let lens = openLens else { return }
    do {
      _ = try database.write { db in
        try RecipeLensRepository.addShelf(
          lensID: lens.id, title: title, query: query, in: db, uuid: { uuid() }
        )
      }
      destination = nil
    } catch { errorMessage = error.localizedDescription }
  }

  func saveQuery(_ query: RecipeBrowserQuery, target: Destination.QueryContext, title: String? = nil) {
    guard scope == .mine else { return }
    let defaultTitle = browser.selectionLabels(for: query).first ?? "New Lens"
    do {
      var created: RecipeLens?
      try database.write { db in
        switch target {
        case .newBase:
          created = try RecipeLensRepository.create(
            name: title?.trimmedNonEmpty ?? defaultTitle,
            baseQuery: query, sortOrder: lensLibrary.lenses.count, in: db, now: now, uuid: { uuid() }
          )
        case let .editBase(id):
          try RecipeLensRepository.setBaseQuery(lensID: id, to: query, in: db, now: now)
        case let .addShelf(id):
          _ = try RecipeLensRepository.addShelf(
            lensID: id, title: title?.trimmedNonEmpty ?? defaultTitle,
            query: query, in: db, uuid: { uuid() }
          )
        case let .editShelf(id, _):
          try RecipeLensRepository.setShelfQuery(shelfID: id, to: query, in: db)
        }
      }
      destination = nil
      if let created { open(created, editing: true) }
      if case let .editBase(id) = target, var lens = activeLens, lens.id == id {
        lens.baseQuery = try RecipeLensQueryCodec.encode(query)
        lens.dateModified = now
        activeLens = lens
      }
    } catch { errorMessage = error.localizedDescription }
  }

  func renameLens(_ lens: RecipeLens, to name: String) {
    guard scope == .mine else { return }
    do {
      try database.write { db in try RecipeLensRepository.rename(lens, to: name, in: db, now: now) }
      if var activeLens, activeLens.id == lens.id { activeLens.name = name; activeLens.dateModified = now; self.activeLens = activeLens }
    }
    catch { errorMessage = error.localizedDescription }
  }

  func deleteLens(_ lens: RecipeLens) {
    guard scope == .mine else { return }
    do {
      try database.write { db in try RecipeLensRepository.delete(lens, in: db) }
      if openLensID == lens.id { closeLens() }
      pendingDelete = nil
    } catch { errorMessage = error.localizedDescription }
  }

  func reorderLenses(_ ids: [RecipeLens.ID]) {
    guard scope == .mine else { return }
    do { try database.write { db in try RecipeLensRepository.reorderLenses(orderedIDs: ids, in: db) } }
    catch { errorMessage = error.localizedDescription }
  }

  func applyLensReorder(sources: [RecipeLens.ID], before destinationID: RecipeLens.ID?) {
    var ids = lensLibrary.lenses.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
    let moving = Set(sources)
    let moved = ids.filter(moving.contains)
    ids.removeAll(where: moving.contains)
    let insertionIndex = destinationID.flatMap { destination in ids.firstIndex(of: destination) } ?? ids.endIndex
    ids.insert(contentsOf: moved, at: insertionIndex)
    reorderLenses(ids)
  }

  func renameShelf(_ shelf: RecipeLensShelf, to title: String) {
    guard scope == .mine else { return }
    do { try database.write { db in try RecipeLensRepository.renameShelf(shelf, to: title, in: db) } }
    catch { errorMessage = error.localizedDescription }
  }

  func deleteShelf(_ shelf: RecipeLensShelf) {
    guard scope == .mine else { return }
    do { try database.write { db in try RecipeLensRepository.removeShelf(shelf, in: db) } }
    catch { errorMessage = error.localizedDescription }
  }

  func reorderShelves(_ ids: [RecipeLensShelf.ID]) {
    guard scope == .mine, let openLensID else { return }
    do { try database.write { db in try RecipeLensRepository.reorderShelves(lensID: openLensID, orderedIDs: ids, in: db) } }
    catch { errorMessage = error.localizedDescription }
  }

  func applyShelfReorder(sources: [RecipeLensShelf.ID], before destinationID: RecipeLensShelf.ID?) {
    var ids = shelves.map(\.id)
    let moving = Set(sources)
    let moved = ids.filter(moving.contains)
    ids.removeAll(where: moving.contains)
    let insertionIndex = destinationID.flatMap { destination in ids.firstIndex(of: destination) } ?? ids.endIndex
    ids.insert(contentsOf: moved, at: insertionIndex)
    reorderShelves(ids)
  }

  func setShowsRemainder(_ value: Bool) {
    guard scope == .mine, let openLens else { return }
    do {
      try database.write { db in try RecipeLensRepository.setShowsRemainder(openLens, to: value, in: db, now: now) }
      if var activeLens, activeLens.id == openLens.id { activeLens.showsRemainder = value; self.activeLens = activeLens }
    }
    catch { errorMessage = error.localizedDescription }
  }

  func browseAll() {
    guard let openLens else { return }
    browser.query = (try? RecipeLensQueryCodec.decode(openLens.baseQuery)) ?? RecipeBrowserQuery()
  }
}

private extension String {
  var trimmedNonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
