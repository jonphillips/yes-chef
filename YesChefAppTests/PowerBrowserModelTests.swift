import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct PowerBrowserModelTests {
  @Test
  func facetValueSelectionsToggleIndividuallyWithinTheirFacet() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let model = PowerBrowserModel()
      let now = Date(timeIntervalSinceReferenceDate: 904_000_000)
      let facet = Facet(id: SampleUUIDSequence.uuid(94_001), name: "Protein", sortOrder: 0, dateCreated: now)
      let beef = Category(id: SampleUUIDSequence.uuid(94_002), name: "Beef", facetID: facet.id, sortOrder: 0, dateCreated: now)
      let pork = Category(id: SampleUUIDSequence.uuid(94_003), name: "Pork", facetID: facet.id, sortOrder: 1, dateCreated: now)

      model.facetValueButtonTapped(beef, in: facet)
      model.facetValueButtonTapped(pork, in: facet)

      expectNoDifference(
        model.query.facetSelections,
        [.init(facetID: facet.id, categoryIDs: [beef.id, pork.id])]
      )

      model.facetValueButtonTapped(beef, in: facet)

      expectNoDifference(
        model.query.facetSelections,
        [.init(facetID: facet.id, categoryIDs: [pork.id])]
      )
    }
  }

  @Test
  func clearRestoresTheDefaultQuery() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let model = PowerBrowserModel()
      model.searchText = "noodles"
      model.query.sort = .recentlyCooked

      model.clearButtonTapped()

      expectNoDifference(model.query, RecipeBrowserQuery())
    }
  }

  @Test
  func firstAvailableFacetStartsExpandedWithoutOverwritingLaterUserChoices() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let model = PowerBrowserModel()
      let firstFacetID = SampleUUIDSequence.uuid(94_101)
      let secondFacetID = SampleUUIDSequence.uuid(94_102)

      model.availableFacetsAppeared([firstFacetID, secondFacetID])
      model.expandedFacetIDs = [secondFacetID]
      model.availableFacetsAppeared([firstFacetID, secondFacetID])

      expectNoDifference(model.expandedFacetIDs, [secondFacetID])
    }
  }

  @Test
  func sourceAndUsageControlsWriteTheTypedBrowserQuery() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let model = PowerBrowserModel()

      model.sourceValueButtonTapped("Milk Street", field: .publication)
      model.requiresNeverCookedChanged(true)
      model.requiresFrequentCookingChanged(true)

      expectNoDifference(
        model.query.sourceFilters,
        [.values(field: .publication, values: ["Milk Street"])]
      )
      expectNoDifference(
        Set(model.query.attributeFilters),
        [.neverCooked, .cookedMoreThan(PowerBrowserModel.frequentCookedThreshold)]
      )
    }
  }

  @Test
  func sourceAndLooseCategoryOptionsPreserveFoldedCountsAndSelectedValues() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 904_100_000)
    let firstRecipeID = SampleUUIDSequence.uuid(94_201)
    let secondRecipeID = SampleUUIDSequence.uuid(94_202)
    let looseCategoryID = SampleUUIDSequence.uuid(94_203)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: firstRecipeID, title: "First", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: secondRecipeID, title: "Second", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try RecipeSource.insert {
          RecipeSource(id: SampleUUIDSequence.uuid(94_204), recipeID: firstRecipeID, author: "Café")
        }
        .execute(db)
        try RecipeSource.insert {
          RecipeSource(id: SampleUUIDSequence.uuid(94_205), recipeID: secondRecipeID, author: "cafe")
        }
        .execute(db)
        try Category.insert {
          Category(id: looseCategoryID, name: "Weeknight", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(id: SampleUUIDSequence.uuid(94_206), recipeID: firstRecipeID, categoryID: looseCategoryID)
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(id: SampleUUIDSequence.uuid(94_207), recipeID: secondRecipeID, categoryID: looseCategoryID)
        }
        .execute(db)
      }

      let model = PowerBrowserModel()
      try await model.$browserData.load()
      try await model.$recipeRows.load()

      model.sourceValueButtonTapped("Café", field: .author)
      let sourceOptions = model.sourceFilterOptions(for: model.result)[.author] ?? []
      expectNoDifference(
        Dictionary(uniqueKeysWithValues: sourceOptions.map { ($0.value, $0.matchingRecipeCount) }),
        ["Café": 2, "cafe": 2]
      )
      expectNoDifference(sourceOptions.first { $0.value == "Café" }?.isSelected, true)
      expectNoDifference(sourceOptions.first { $0.value == "cafe" }?.isSelected, false)

      let looseOptions = model.looseCategoryOptions(for: model.result)
      expectNoDifference(looseOptions.count, 1)
      expectNoDifference(looseOptions.first?.category.name, "Weeknight")
      expectNoDifference(looseOptions.first?.matchingRecipeCount, 2)

      model.sourceValueButtonTapped("Missing", field: .publication)
      let emptyResult = model.result
      expectNoDifference(emptyResult.matchingRecipeIDs, [])
      let retainedPublication = model.sourceFilterOptions(for: emptyResult)[.publication]
      expectNoDifference(retainedPublication?.count, 1)
      expectNoDifference(retainedPublication?.first?.value, "Missing")
      expectNoDifference(retainedPublication?.first?.matchingRecipeCount, 0)
      expectNoDifference(retainedPublication?.first?.isSelected, true)
    }
  }

  @Test
  func selectingLensLoadsItsBaseAndAllRecipesReturnsToBrowser() throws {
    let now = Date(timeIntervalSinceReferenceDate: 904_900_000)
    let query = RecipeBrowserQuery(text: "taco")
    let lens = RecipeLens(
      id: SampleUUIDSequence.uuid(94_901), name: "Tacos",
      baseQuery: try RecipeLensQueryCodec.encode(query), sortOrder: 0,
      dateCreated: now, dateModified: now
    )
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let model = PowerBrowserModel()
      model.lensSelectionChanged(lens.id, using: lens)
      #expect(model.selectedLensID == lens.id)
      #expect(model.query == query)

      model.lensSelectionChanged(nil)
      #expect(model.selectedLensID == nil)
      #expect(model.query == RecipeBrowserQuery())
    }
  }

  @Test
  func savingAsLensPersistsCurrentQueryAndShelfReorderKeepsIDs() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 904_910_000)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let model = PowerBrowserModel()
      model.query = RecipeBrowserQuery(text: "salsa")
      model.saveLensButtonTapped(name: "Salsa")
      let lens = try await database.read { db in try #require(RecipeLens.fetchAll(db).first) }
      #expect(try RecipeLensQueryCodec.decode(lens.baseQuery) == model.query)

      let first = try await database.write { db in
        try RecipeLensRepository.addShelf(lensID: lens.id, title: "First", query: RecipeBrowserQuery(), in: db, uuid: { UUID() })
      }
      let second = try await database.write { db in
        try RecipeLensRepository.addShelf(lensID: lens.id, title: "Second", query: RecipeBrowserQuery(), in: db, uuid: { UUID() })
      }
      try await database.write { db in
        try RecipeLensRepository.reorderShelves(lensID: lens.id, orderedIDs: [second.id, first.id], in: db)
      }
      let reordered = try await database.read { db in
        try RecipeLensShelf.where { $0.lensID.eq(lens.id) }.order { $0.sortOrder }.fetchAll(db)
      }
      #expect(reordered.map(\.id) == [second.id, first.id])
      #expect(reordered.map(\.sortOrder) == [0, 1])
    }
  }

  @Test
  func savingEditedLensQueryRestoresLensSelectionWithoutReloadingStaleBase() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 904_920_000)
    let lensID = SampleUUIDSequence.uuid(94_921)
    let shelfID = SampleUUIDSequence.uuid(94_922)
    let initialQuery = RecipeBrowserQuery(text: "initial")
    let editedQuery = RecipeBrowserQuery(text: "edited")
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let lens = RecipeLens(
        id: lensID, name: "Edited", baseQuery: try RecipeLensQueryCodec.encode(initialQuery),
        sortOrder: 0, dateCreated: now, dateModified: now
      )
      let shelf = RecipeLensShelf(
        id: shelfID, lensID: lensID, title: "Shelf",
        query: try RecipeLensQueryCodec.encode(initialQuery), sortOrder: 0
      )
      try await database.write { db in
        try RecipeLens.insert { lens }.execute(db)
        try RecipeLensShelf.insert { shelf }.execute(db)
      }

      let model = PowerBrowserModel()
      model.query = editedQuery
      model.queryEditTarget = .lensBase(lensID)
      model.saveQueryEditsButtonTapped()
      #expect(model.selectedLensID == lensID)
      #expect(model.query == editedQuery)
      model.lensSelectionChanged(lensID)
      #expect(model.query == editedQuery)

      let shelfEdit = RecipeBrowserQuery(text: "shelf edit")
      model.query = shelfEdit
      model.queryEditTarget = .shelf(shelfID, lensID: lensID)
      model.saveQueryEditsButtonTapped()
      #expect(model.selectedLensID == lensID)
      #expect(model.query == shelfEdit)
      model.lensSelectionChanged(lensID)
      #expect(model.query == shelfEdit)
    }
  }

  @Test
  func browserDataPhotoIDsExcludeNilThumbnailsAndReferenceDocuments() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 904_200_000)
    let includedRecipeID = SampleUUIDSequence.uuid(94_301)
    let nilThumbnailRecipeID = SampleUUIDSequence.uuid(94_302)
    let referenceRecipeID = SampleUUIDSequence.uuid(94_303)

    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        for (offset, recipeID) in [includedRecipeID, nilThumbnailRecipeID, referenceRecipeID].enumerated() {
          try Recipe.insert {
            Recipe(id: recipeID, title: "Recipe \(offset)", dateCreated: now, dateModified: now)
          }
          .execute(db)
        }
        try RecipePhoto.insert {
          RecipePhoto(
            id: SampleUUIDSequence.uuid(94_304), recipeID: includedRecipeID,
            imageDataReference: "included", thumbnailData: Data([1]), sortOrder: 0, dateCreated: now
          )
        }
        .execute(db)
        try RecipePhoto.insert {
          RecipePhoto(
            id: SampleUUIDSequence.uuid(94_305), recipeID: nilThumbnailRecipeID,
            imageDataReference: "nil-thumbnail", sortOrder: 0, dateCreated: now
          )
        }
        .execute(db)
        try RecipePhoto.insert {
          RecipePhoto(
            id: SampleUUIDSequence.uuid(94_306), recipeID: referenceRecipeID,
            imageDataReference: "reference", thumbnailData: Data([1]), kind: .referenceDocument,
            sortOrder: 0, dateCreated: now
          )
        }
        .execute(db)
      }

      let data = try await database.read { db in
        try RecipeBrowserDataRequest(today: now).fetch(db)
      }
      expectNoDifference(data.recipeIDsWithPhotos, [includedRecipeID])
    }
  }

  @Test
  func rowMappingRefreshesWhenRecipeRowsArriveAfterBrowserData() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 904_300_000)
    let recipeID = SampleUUIDSequence.uuid(94_401)
    let recipe = Recipe(id: recipeID, title: "Late Row", dateCreated: now, dateModified: now)
    let browserData = RecipeBrowserData(
      recipes: [.init(id: recipeID, title: recipe.title, dateCreated: now, dateModified: now)],
      recipeCategories: [],
      categories: [],
      facets: []
    )
    let rows = [RecipeListRowData(recipe: recipe)]

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      let powerBrowserModel = PowerBrowserModel()
      let libraryModel = RecipeLibraryModel()

      try await powerBrowserModel.$browserData.load(StaticBrowserDataRequest(data: browserData))
      try await libraryModel.$browserData.load(StaticBrowserDataRequest(data: browserData))

      expectNoDifference(powerBrowserModel.recipeRows(for: powerBrowserModel.result), [])
      expectNoDifference(libraryModel.visibleRecipeRows, [])

      try await powerBrowserModel.$recipeRows.load(StaticRecipeRowsRequest(rows: rows))
      try await libraryModel.$recipeRows.load(StaticRecipeRowsRequest(rows: rows))

      expectNoDifference(powerBrowserModel.recipeRows(for: powerBrowserModel.result).map(\.recipe.id), [recipeID])
      expectNoDifference(libraryModel.visibleRecipeRows.map(\.recipe.id), [recipeID])
    }
  }

}

private struct StaticBrowserDataRequest: FetchKeyRequest {
  let data: RecipeBrowserData

  static func == (lhs: Self, rhs: Self) -> Bool { true }

  func hash(into hasher: inout Hasher) {
    hasher.combine(0)
  }

  func fetch(_ db: Database) throws -> RecipeBrowserData {
    data
  }
}

private struct StaticRecipeRowsRequest: FetchKeyRequest {
  let rows: [RecipeListRowData]

  static func == (lhs: Self, rhs: Self) -> Bool { true }

  func hash(into hasher: inout Hasher) {
    hasher.combine(0)
  }

  func fetch(_ db: Database) throws -> [RecipeListRowData] {
    rows
  }
}
