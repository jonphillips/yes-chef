import CustomDump
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeFacetCoverageTests {
    @Test
    func derivedCoverageViewsUseFacetIdentityAndIgnoreHiddenVocabulary() {
      let protein = Facet(id: SampleUUIDSequence.uuid(80_001), name: "Protein", sortOrder: 0, dateCreated: .distantPast)
      let dishType = Facet(id: SampleUUIDSequence.uuid(80_002), name: "Dish Type", sortOrder: 1, dateCreated: .distantPast)
      let technique = Facet(id: SampleUUIDSequence.uuid(80_003), name: "Technique", sortOrder: 2, dateCreated: .distantPast)
      let dietary = Facet(id: SampleUUIDSequence.uuid(80_004), name: "Dietary", sortOrder: 3, dateCreated: .distantPast)
      let hidden = Facet(id: SampleUUIDSequence.uuid(80_005), name: "Hidden", sortOrder: 4, hidden: true, dateCreated: .distantPast)
      let chicken = Category(id: SampleUUIDSequence.uuid(80_011), name: "Chicken", facetID: protein.id, sortOrder: 0, dateCreated: .distantPast)
      let soup = Category(id: SampleUUIDSequence.uuid(80_012), name: "Soup", facetID: dishType.id, sortOrder: 0, dateCreated: .distantPast)
      let roast = Category(id: SampleUUIDSequence.uuid(80_013), name: "Roast", facetID: technique.id, sortOrder: 0, dateCreated: .distantPast)
      let vegan = Category(id: SampleUUIDSequence.uuid(80_014), name: "Vegan", facetID: dietary.id, sortOrder: 0, dateCreated: .distantPast)
      let hiddenProtein = Category(id: SampleUUIDSequence.uuid(80_015), name: "Hidden protein", facetID: hidden.id, sortOrder: 0, dateCreated: .distantPast)
      let complete = Recipe(id: SampleUUIDSequence.uuid(80_101), title: "Complete", dateCreated: .distantPast, dateModified: .distantPast)
      let noProtein = Recipe(id: SampleUUIDSequence.uuid(80_102), title: "No Protein", dateCreated: .distantPast, dateModified: .distantPast)
      let untouched = Recipe(id: SampleUUIDSequence.uuid(80_103), title: "Untouched", dateCreated: .distantPast, dateModified: .distantPast)
      let hiddenOnly = Recipe(id: SampleUUIDSequence.uuid(80_104), title: "Hidden Only", dateCreated: .distantPast, dateModified: .distantPast)

      let coverage = RecipeFacetCoverage(
        recipes: [complete, noProtein, untouched, hiddenOnly],
        recipeCategories: [
          .init(id: SampleUUIDSequence.uuid(80_201), recipeID: complete.id, categoryID: chicken.id),
          .init(id: SampleUUIDSequence.uuid(80_202), recipeID: complete.id, categoryID: soup.id),
          .init(id: SampleUUIDSequence.uuid(80_203), recipeID: complete.id, categoryID: roast.id),
          .init(id: SampleUUIDSequence.uuid(80_204), recipeID: complete.id, categoryID: vegan.id),
          .init(id: SampleUUIDSequence.uuid(80_205), recipeID: noProtein.id, categoryID: soup.id),
          .init(id: SampleUUIDSequence.uuid(80_206), recipeID: noProtein.id, categoryID: roast.id),
          .init(id: SampleUUIDSequence.uuid(80_207), recipeID: hiddenOnly.id, categoryID: hiddenProtein.id),
        ],
        categories: [chicken, soup, roast, vegan, hiddenProtein],
        facets: [protein, dishType, technique, dietary, hidden]
      )

      expectNoDifference(coverage.recipeIDs(matching: .missingProtein), [noProtein.id, untouched.id, hiddenOnly.id])
      expectNoDifference(coverage.recipeIDs(matching: .missingPrimaryFacet), [noProtein.id, untouched.id, hiddenOnly.id])
      expectNoDifference(coverage.recipeIDs(matching: .noEditorialLabels), [untouched.id, hiddenOnly.id])
      expectNoDifference(coverage.facetSummaries.first { $0.facet.id == protein.id }?.unclassifiedRecipeCount, 3)
      #expect(coverage.facetSummaries.allSatisfy { $0.facet.id != hidden.id })
    }
  }
}
