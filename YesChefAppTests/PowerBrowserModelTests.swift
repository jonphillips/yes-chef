import CustomDump
import Dependencies
import Foundation
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
}
