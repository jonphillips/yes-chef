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
}
