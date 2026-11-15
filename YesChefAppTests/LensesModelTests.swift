import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct LensesModelTests {
  @Test
  func creatingLensFromFacetValueOpensItInEditMode() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 906_000_000)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let model = LensesModel()
      let facet = Facet(id: SampleUUIDSequence.uuid(96_001), name: "Cuisine", sortOrder: 0, dateCreated: now)
      let category = Category(id: SampleUUIDSequence.uuid(96_002), name: "Korean", facetID: facet.id, sortOrder: 0, dateCreated: now)

      let id = try #require(model.createFromValue(category, facet: facet))
      let lensRecord = try await database.read { db in try RecipeLens.find(id).fetchOne(db) }
      let lens = try #require(lensRecord)
      #expect(lens.name == "Korean")
      #expect(model.openLensID == id)
      #expect(model.isEditing)
      #expect(try RecipeLensQueryCodec.decode(lens.baseQuery) == RecipeBrowserQuery(
        facetSelections: [.init(facetID: facet.id, categoryIDs: [category.id])]
      ))
    }
  }

  @Test
  func suggestedShelfStoresItsTitleAndStableRowID() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 906_010_000)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let model = LensesModel()
      let lensID = try await database.write { db in
        try RecipeLensRepository.create(name: "Korean", baseQuery: RecipeBrowserQuery(), sortOrder: 0,
          in: db, now: now, uuid: { SampleUUIDSequence.uuid(96_011) }).id
      }
      let lensRecord = try await database.read { db in try RecipeLens.find(lensID).fetchOne(db) }
      let lens = try #require(lensRecord)
      model.open(lens, editing: true)
      let facet = Facet(id: SampleUUIDSequence.uuid(96_012), name: "Dish", sortOrder: 0, dateCreated: now)
      let category = Category(id: SampleUUIDSequence.uuid(96_013), name: "Tacos", facetID: facet.id, sortOrder: 0, dateCreated: now)
      model.addSuggestedShelf(.init(category: category, matchingRecipeCount: 4, isSelected: false), facet: facet)
      let shelfRecord = try await database.read { db in
        try RecipeLensShelf.where { $0.lensID.eq(lensID) }.fetchOne(db)
      }
      let shelf = try #require(shelfRecord)
      #expect(shelf.title == "Tacos")
      try await model.browser.$lensLibrary.load()
      #expect(model.alreadyShelvedFacetValues.contains("\(facet.id.uuidString):\(category.id.uuidString)"))
      let rowID = shelf.id
      try await database.write { db in try RecipeLensRepository.renameShelf(shelf, to: "Street tacos", in: db) }
      let renamedRecord = try await database.read { db in try RecipeLensShelf.find(rowID).fetchOne(db) }
      let renamed = try #require(renamedRecord)
      #expect(renamed.title == "Street tacos")
      #expect(renamed.id == rowID)
    }
  }

  @Test
  func recipePresentationKeepsTheModelScope() throws {
    try withDependencies { try $0.bootstrapDatabase() } operation: {
      let recipeID = SampleUUIDSequence.uuid(96_021)
      let model = LensesModel()
      #expect(model.recipeTapped(recipeID).scope == .mine)
    }
  }

  @Test
  func customShelfStartsEmptyAndUsesAllItsOwnSelectionsForTitle() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 906_020_000)
    try await withDependencies { try $0.bootstrapDatabase() } operation: {
      let browser = PowerBrowserModel()
      let model = LensesModel(browser: browser)
      let facet = Facet(id: UUID(), name: "Cuisine", sortOrder: 0, dateCreated: now)
      let courseFacet = Facet(id: UUID(), name: "Course", sortOrder: 1, dateCreated: now)
      let korean = Category(id: UUID(), name: "Korean", facetID: facet.id, sortOrder: 0, dateCreated: now)
      let oaxacan = Category(id: UUID(), name: "Oaxacan", facetID: facet.id, sortOrder: 1, dateCreated: now)
      let dessert = Category(id: UUID(), name: "Dessert", facetID: courseFacet.id, sortOrder: 0, dateCreated: now)
      let base = RecipeBrowserQuery(facetSelections: [.init(facetID: facet.id, categoryIDs: [korean.id])])
      let lens = RecipeLens(id: UUID(), name: "Korean", baseQuery: try RecipeLensQueryCodec.encode(base),
        sortOrder: 0, dateCreated: now, dateModified: now)
      let data = RecipeBrowserData(recipes: [], recipeCategories: [], categories: [korean, oaxacan, dessert], facets: [facet, courseFacet])
      try await browser.$browserData.load(StaticLensBrowserDataRequest(data: data))

      let draft = model.customShelfDraft(for: lens)
      #expect(draft.query == RecipeBrowserQuery())
      #expect(draft.restrictedRecipeIDs.isEmpty)
      let ownSelections = RecipeBrowserQuery(facetSelections: [
        .init(facetID: facet.id, categoryIDs: [oaxacan.id]),
        .init(facetID: courseFacet.id, categoryIDs: [dessert.id]),
      ])
      #expect(model.defaultShelfTitle(for: ownSelections) == "Cuisine: Oaxacan · Course: Dessert")
      #expect(model.defaultShelfTitle(for: RecipeBrowserQuery()) == "New shelf")
    }
  }

  @Test
  func newLensValuesUseTheWholeLibraryAfterOpeningAFilteredLens() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 906_030_000)
    try await withDependencies { try $0.bootstrapDatabase() } operation: {
      let browser = PowerBrowserModel()
      let model = LensesModel(browser: browser)
      let facet = Facet(id: UUID(), name: "Cuisine", sortOrder: 0, dateCreated: now)
      let korean = Category(id: UUID(), name: "Korean", facetID: facet.id, sortOrder: 0, dateCreated: now)
      let mexican = Category(id: UUID(), name: "Mexican", facetID: facet.id, sortOrder: 1, dateCreated: now)
      let recipeIDs = [UUID(), UUID()]
      let data = RecipeBrowserData(
        recipes: recipeIDs.map { .init(id: $0, title: "Recipe", dateCreated: now, dateModified: now) },
        recipeCategories: [
          RecipeCategory(id: UUID(), recipeID: recipeIDs[0], categoryID: korean.id),
          RecipeCategory(id: UUID(), recipeID: recipeIDs[1], categoryID: mexican.id),
        ], categories: [korean, mexican], facets: [facet]
      )
      try await browser.$browserData.load(StaticLensBrowserDataRequest(data: data))
      let lens = RecipeLens(id: UUID(), name: "Mexican", baseQuery: try RecipeLensQueryCodec.encode(
        RecipeBrowserQuery(facetSelections: [.init(facetID: facet.id, categoryIDs: [mexican.id])])),
        sortOrder: 0, dateCreated: now, dateModified: now)

      browser.query = (try RecipeLensQueryCodec.decode(lens.baseQuery))
      model.open(lens)
      let availability = model.newLensAvailability.first?.values ?? []
      #expect(Set(availability.map(\.category.id)) == Set([korean.id, mexican.id]))
    }
  }

  @Test
  func unresolvedShelvesRemainVisibleOutsideEditMode() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 906_040_000)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let model = LensesModel()
      let lens = try await database.write { db in
        try RecipeLensRepository.create(name: "Dinner", baseQuery: RecipeBrowserQuery(), sortOrder: 0,
          in: db, now: now, uuid: { SampleUUIDSequence.uuid(96_041) })
      }
      let shelf = try await database.write { db in
        try RecipeLensRepository.addShelf(lensID: lens.id, title: "Missing facet",
          query: RecipeBrowserQuery(facetSelections: [.init(facetID: UUID(), categoryIDs: [UUID()])]),
          in: db, uuid: { SampleUUIDSequence.uuid(96_042) })
      }
      try await model.browser.$lensLibrary.load()
      model.open(lens)
      #expect(model.visibleShelves(for: lens).map(\.shelf.id) == [shelf.id])
      #expect(model.visibleShelves(for: lens).first?.state != .empty)
    }
  }

  @Test
  func shelfReorderThroughModelPreservesIDs() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 906_050_000)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let model = LensesModel()
      let lens = try await database.write { db in
        try RecipeLensRepository.create(name: "Dinner", baseQuery: RecipeBrowserQuery(), sortOrder: 0,
          in: db, now: now, uuid: { SampleUUIDSequence.uuid(96_051) })
      }
      let first = try await database.write { db in
        try RecipeLensRepository.addShelf(lensID: lens.id, title: "First", query: RecipeBrowserQuery(),
          in: db, uuid: { SampleUUIDSequence.uuid(96_052) })
      }
      let second = try await database.write { db in
        try RecipeLensRepository.addShelf(lensID: lens.id, title: "Second", query: RecipeBrowserQuery(),
          in: db, uuid: { SampleUUIDSequence.uuid(96_053) })
      }
      try await model.browser.$lensLibrary.load()
      model.open(lens, editing: true)
      model.applyShelfReorder(sources: [first.id], before: nil)
      let ordered = try await database.read { db in
        try RecipeLensShelf.where { $0.lensID.eq(lens.id) }.order { $0.sortOrder }.fetchAll(db)
      }
      #expect(ordered.map(\.id) == [second.id, first.id])
      #expect(Set(ordered.map(\.id)) == Set([first.id, second.id]))
    }
  }
}

private struct StaticLensBrowserDataRequest: FetchKeyRequest {
  var data: RecipeBrowserData
  static func == (lhs: Self, rhs: Self) -> Bool { true }
  func hash(into hasher: inout Hasher) { hasher.combine(0) }
  func fetch(_ db: Database) throws -> RecipeBrowserData { data }
}
