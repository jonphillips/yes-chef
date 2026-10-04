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
