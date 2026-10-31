import Foundation
import SQLiteData

@Table("recipeLenses")
public struct RecipeLens: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var baseQuery: String
  public var showsRemainder: Bool
  public var sortOrder: Int
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    name: String,
    baseQuery: String,
    showsRemainder: Bool = true,
    sortOrder: Int,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.name = name
    self.baseQuery = baseQuery
    self.showsRemainder = showsRemainder
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

@Table("recipeLensShelves")
public struct RecipeLensShelf: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var lensID: RecipeLens.ID
  public var title: String
  public var query: String
  public var sortOrder: Int

  public init(id: UUID, lensID: RecipeLens.ID, title: String, query: String, sortOrder: Int) {
    self.id = id
    self.lensID = lensID
    self.title = title
    self.query = query
    self.sortOrder = sortOrder
  }
}

public enum RecipeLensQueryCodec {
  private struct Envelope: Codable {
    var v: Int
    var query: RecipeBrowserQuery
  }

  public static func encode(_ query: RecipeBrowserQuery) throws -> String {
    let data = try JSONEncoder().encode(Envelope(v: 1, query: query))
    guard let string = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return string
  }

  public static func decode(_ string: String) throws -> RecipeBrowserQuery {
    let envelope = try JSONDecoder().decode(Envelope.self, from: Data(string.utf8))
    guard envelope.v == 1 else { throw DecodingError.dataCorrupted(.init(
      codingPath: [], debugDescription: "Unsupported recipe query version \(envelope.v)"
    )) }
    return envelope.query
  }
}

public enum RecipeLensShelfState: Equatable, Sendable {
  case ready([Recipe.ID])
  case empty
  case unresolved([String])
}

public struct RecipeLensEvaluation: Equatable, Sendable {
  public var baseState: RecipeLensShelfState
  public var baseRecipeIDs: [Recipe.ID]
  public var shelves: [ShelfResult]
  public var remainderRecipeIDs: [Recipe.ID]

  public struct ShelfResult: Identifiable, Equatable, Sendable {
    public var shelf: RecipeLensShelf
    public var state: RecipeLensShelfState
    public var id: RecipeLensShelf.ID { shelf.id }
  }
}

public struct RecipeLensLibrary: Equatable, Sendable {
  public var lenses: [RecipeLens]
  public var shelves: [RecipeLensShelf]

  public init(lenses: [RecipeLens], shelves: [RecipeLensShelf]) {
    self.lenses = lenses
    self.shelves = shelves
  }
}

public struct RecipeLensLibraryRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> RecipeLensLibrary {
    RecipeLensLibrary(
      lenses: try RecipeLens.order { $0.sortOrder }.fetchAll(db),
      shelves: try RecipeLensShelf.order { $0.sortOrder }.fetchAll(db)
    )
  }
}

public enum RecipeLensEvaluator {
  public static func evaluate(
    lens: RecipeLens,
    shelves: [RecipeLensShelf],
    using engine: RecipeBrowserEngine,
    facets: [Facet],
    categories: [Category]
  ) -> RecipeLensEvaluation {
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let facetsByID = Dictionary(uniqueKeysWithValues: facets.map { ($0.id, $0) })
    let baseQuery = try? RecipeLensQueryCodec.decode(lens.baseQuery)
    let baseProblems = baseQuery.map { unresolvedReasons(in: $0, facetsByID: facetsByID, categoriesByID: categoriesByID) }
      ?? ["The base query could not be decoded."]
    let baseIDs = baseQuery.map(engine.matchingRecipeIDs(for:)) ?? []
    let baseSet = Set(baseIDs)
    let baseState: RecipeLensShelfState
    if !baseProblems.isEmpty {
      baseState = .unresolved(baseProblems)
    } else {
      baseState = baseIDs.isEmpty ? .empty : .ready(baseIDs)
    }

    let shelfResults = shelves.sorted { $0.sortOrder < $1.sortOrder }.map { shelf in
      guard baseProblems.isEmpty else {
        return RecipeLensEvaluation.ShelfResult(shelf: shelf, state: .unresolved(baseProblems))
      }
      guard let query = try? RecipeLensQueryCodec.decode(shelf.query) else {
        return RecipeLensEvaluation.ShelfResult(
          shelf: shelf, state: .unresolved(["The shelf query could not be decoded."])
        )
      }
      let reasons = unresolvedReasons(in: query, facetsByID: facetsByID, categoriesByID: categoriesByID)
      guard reasons.isEmpty else {
        return RecipeLensEvaluation.ShelfResult(shelf: shelf, state: .unresolved(reasons))
      }
      let ids = engine.matchingRecipeIDs(for: query).filter(baseSet.contains)
      return RecipeLensEvaluation.ShelfResult(shelf: shelf, state: ids.isEmpty ? .empty : .ready(ids))
    }

    let coveredIDs = Set(shelfResults.flatMap { result -> [Recipe.ID] in
      guard case let .ready(ids) = result.state else { return [] }
      return ids
    })
    return RecipeLensEvaluation(
      baseState: baseState,
      baseRecipeIDs: baseIDs,
      shelves: shelfResults,
      remainderRecipeIDs: baseIDs.filter { !coveredIDs.contains($0) }
    )
  }

  public static func suggestions(
    for baseQuery: RecipeBrowserQuery,
    using engine: RecipeBrowserEngine
  ) -> [RecipeBrowserResult.FacetAvailability] {
    engine.result(for: baseQuery).availableFacets
  }

  private static func unresolvedReasons(
    in query: RecipeBrowserQuery,
    facetsByID: [Facet.ID: Facet],
    categoriesByID: [Category.ID: Category]
  ) -> [String] {
    var reasons: [String] = []
    for selection in query.facetSelections {
      guard let facet = facetsByID[selection.facetID], !facet.hidden else {
        reasons.append("A selected facet is missing or hidden.")
        continue
      }
      for id in selection.categoryIDs {
        guard let category = categoriesByID[id], category.facetID == facet.id, !category.hidden else {
          reasons.append("A selected value is missing or no longer belongs to its facet.")
          continue
        }
      }
    }
    for id in query.looseLabelIDs {
      guard let category = categoriesByID[id], category.facetID == nil, !category.hidden else {
        reasons.append("A selected label is missing or is no longer an ungrouped label.")
        continue
      }
    }
    return reasons
  }
}

public enum RecipeLensRepository {
  public static func create(
    name: String,
    baseQuery: RecipeBrowserQuery,
    sortOrder: Int,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeLens {
    let lens = RecipeLens(
      id: uuid(), name: name, baseQuery: try RecipeLensQueryCodec.encode(baseQuery),
      sortOrder: sortOrder, dateCreated: now, dateModified: now
    )
    try RecipeLens.insert { lens }.execute(db)
    return lens
  }

  public static func rename(_ lens: RecipeLens, to name: String, in db: Database, now: Date) throws {
    try RecipeLens.update { $0.name = name; $0.dateModified = now }
      .where { $0.id.eq(lens.id) }.execute(db)
  }

  public static func setBaseQuery(_ lens: RecipeLens, to query: RecipeBrowserQuery, in db: Database, now: Date) throws {
    let encoded = try RecipeLensQueryCodec.encode(query)
    try RecipeLens.find(lens.id).update { $0.baseQuery = encoded; $0.dateModified = now }.execute(db)
  }

  public static func delete(_ lens: RecipeLens, in db: Database) throws {
    try RecipeLens.where { $0.id.eq(lens.id) }.delete().execute(db)
  }

  public static func addShelf(
    lensID: RecipeLens.ID,
    title: String,
    query: RecipeBrowserQuery,
    in db: Database,
    uuid: () -> UUID
  ) throws -> RecipeLensShelf {
    let count = try RecipeLensShelf.where { $0.lensID.eq(lensID) }.fetchCount(db)
    let shelf = RecipeLensShelf(
      id: uuid(), lensID: lensID, title: title,
      query: try RecipeLensQueryCodec.encode(query), sortOrder: count
    )
    try RecipeLensShelf.insert { shelf }.execute(db)
    return shelf
  }

  public static func renameShelf(_ shelf: RecipeLensShelf, to title: String, in db: Database) throws {
    try RecipeLensShelf.update { $0.title = title }.where { $0.id.eq(shelf.id) }.execute(db)
  }

  public static func setShelfQuery(_ shelf: RecipeLensShelf, to query: RecipeBrowserQuery, in db: Database) throws {
    let encoded = try RecipeLensQueryCodec.encode(query)
    try RecipeLensShelf.find(shelf.id).update { $0.query = encoded }.execute(db)
  }

  public static func removeShelf(_ shelf: RecipeLensShelf, in db: Database) throws {
    try RecipeLensShelf.where { $0.id.eq(shelf.id) }.delete().execute(db)
    let remaining = try RecipeLensShelf.where { $0.lensID.eq(shelf.lensID) }
      .order { $0.sortOrder }.fetchAll(db)
    try rewriteOrder(remaining, in: db)
  }

  public static func reorderShelves(
    lensID: RecipeLens.ID,
    orderedIDs: [RecipeLensShelf.ID],
    in db: Database
  ) throws {
    let current = try RecipeLensShelf.where { $0.lensID.eq(lensID) }.order { $0.sortOrder }.fetchAll(db)
    guard current.count == orderedIDs.count, Set(current.map(\.id)) == Set(orderedIDs) else { return }
    let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    try rewriteOrder(orderedIDs.compactMap { byID[$0] }, in: db)
  }

  public static func setShowsRemainder(_ lens: RecipeLens, to value: Bool, in db: Database, now: Date) throws {
    try RecipeLens.update { $0.showsRemainder = value; $0.dateModified = now }
      .where { $0.id.eq(lens.id) }.execute(db)
  }

  private static func rewriteOrder(_ shelves: [RecipeLensShelf], in db: Database) throws {
    for (order, shelf) in shelves.enumerated() where shelf.sortOrder != order {
      try RecipeLensShelf.update { $0.sortOrder = order }.where { $0.id.eq(shelf.id) }.execute(db)
    }
  }
}
