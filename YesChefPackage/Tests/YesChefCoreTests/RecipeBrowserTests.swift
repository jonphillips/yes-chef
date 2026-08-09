import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeBrowserTests {
    @Test
    func facetSelectionsOrWithinAFacetAndAndAcrossFacetsWithSelfExcludingCounts() throws {
      let fixture = BrowserFixture()
      let query = RecipeBrowserQuery(
        facetSelections: [
          .init(facetID: fixture.cuisine.id, categoryIDs: [fixture.korean.id]),
          .init(facetID: fixture.protein.id, categoryIDs: [fixture.beef.id]),
        ]
      )

      let result = fixture.engine.result(for: query)

      expectNoDifference(result.matchingRecipeIDs, [fixture.koreanBeef.id])
      expectNoDifference(result.availableFacets.map(\.facet.id), [fixture.protein.id, fixture.cuisine.id])
      let cuisineValues = try #require(result.availableFacets.first { $0.facet.id == fixture.cuisine.id }?.values)
      expectNoDifference(cuisineValues.map(\.category.id), [fixture.korean.id, fixture.mexican.id])
      expectNoDifference(cuisineValues.map(\.matchingRecipeCount), [1, 2])
      expectNoDifference(cuisineValues.map(\.isSelected), [true, false])
      let proteinValues = try #require(result.availableFacets.first { $0.facet.id == fixture.protein.id }?.values)
      expectNoDifference(proteinValues.map(\.category.id), [fixture.beef.id, fixture.pork.id])
      expectNoDifference(proteinValues.map(\.matchingRecipeCount), [1, 2])
      expectNoDifference(proteinValues.map(\.isSelected), [true, false])
    }

    @Test
    func selectingAFacetAncestorMatchesAssignmentsToItsDescendants() {
      let fixture = BrowserFixture()
      let engine = RecipeBrowserEngine(
        recipes: [fixture.koreanBeef, fixture.koreanPork],
        recipeCategories: [
          .init(id: fixture.ids.next(), recipeID: fixture.koreanBeef.id, categoryID: fixture.tenderloin.id),
          .init(id: fixture.ids.next(), recipeID: fixture.koreanPork.id, categoryID: fixture.pork.id),
        ],
        categories: [fixture.beef, fixture.tenderloin, fixture.pork],
        facets: [fixture.protein]
      )

      expectNoDifference(
        engine.matchingRecipeIDs(
          for: RecipeBrowserQuery(
            facetSelections: [.init(facetID: fixture.protein.id, categoryIDs: [fixture.beef.id])]
          )
        ),
        [fixture.koreanBeef.id]
      )
    }

    @Test
    func looseLabelsAndWithFacetSelections() {
      let fixture = BrowserFixture()
      let result = fixture.engine.result(
        for: RecipeBrowserQuery(
          facetSelections: [.init(facetID: fixture.cuisine.id, categoryIDs: [fixture.korean.id])],
          looseLabelIDs: [fixture.weeknight.id]
        )
      )

      expectNoDifference(result.matchingRecipeIDs, [fixture.koreanPork.id])
    }

    @Test
    func variationNamesAreTextSearchAliasesWithoutExpandingRelatedRecipes() throws {
      @Dependency(\.defaultDatabase) var database
      let fixture = BrowserFixture()

      try database.write { db in
        for recipe in [fixture.koreanBeef, fixture.koreanPork] {
          try Recipe.insert {
            Recipe(
              id: recipe.id,
              title: recipe.title,
              dateCreated: recipe.dateCreated,
              dateModified: recipe.dateModified
            )
          }
          .execute(db)
        }
        try RecipeVariation.insert {
          RecipeVariation(
            id: fixture.ids.next(),
            recipeID: fixture.koreanBeef.id,
            name: "Lime Bulgogi",
            sortIndex: 0,
            dateCreated: fixture.now,
            dateModified: fixture.now
          )
        }
        .execute(db)
        try RecipeRelatedRecipe.insert {
          RecipeRelatedRecipe(
            id: fixture.ids.next(),
            recipeID: fixture.koreanBeef.id,
            relatedRecipeID: fixture.koreanPork.id,
            dateCreated: fixture.now
          )
        }
        .execute(db)

        expectNoDifference(
          try RecipeRepository.browserResult(
            for: RecipeBrowserQuery(text: "Lime Bulgogi"),
            in: db
          )
          .matchingRecipeIDs,
          [fixture.koreanBeef.id]
        )
      }
    }
  }
}

private final class BrowserFixture {
  var ids = SampleUUIDSequence(start: 93_000)
  let now = Date(timeIntervalSinceReferenceDate: 903_000_000)

  let cuisine: Facet
  let protein: Facet
  let korean: YesChefCore.Category
  let mexican: YesChefCore.Category
  let beef: YesChefCore.Category
  let tenderloin: YesChefCore.Category
  let pork: YesChefCore.Category
  let weeknight: YesChefCore.Category
  let koreanBeef: RecipeBrowserRecipe
  let mexicanBeef: RecipeBrowserRecipe
  let koreanPork: RecipeBrowserRecipe
  let mexicanPork: RecipeBrowserRecipe

  init() {
    cuisine = Facet(id: ids.next(), name: "Cuisine", sortOrder: 1, dateCreated: now)
    protein = Facet(id: ids.next(), name: "Protein", sortOrder: 0, dateCreated: now)
    korean = YesChefCore.Category(id: ids.next(), name: "Korean", facetID: cuisine.id, sortOrder: 0, dateCreated: now)
    mexican = YesChefCore.Category(id: ids.next(), name: "Mexican", facetID: cuisine.id, sortOrder: 1, dateCreated: now)
    beef = YesChefCore.Category(id: ids.next(), name: "Beef", facetID: protein.id, sortOrder: 0, dateCreated: now)
    tenderloin = YesChefCore.Category(
      id: ids.next(), name: "Tenderloin", facetID: protein.id, parentCategoryID: beef.id, sortOrder: 0, dateCreated: now
    )
    pork = YesChefCore.Category(id: ids.next(), name: "Pork", facetID: protein.id, sortOrder: 1, dateCreated: now)
    weeknight = YesChefCore.Category(id: ids.next(), name: "Weeknight", sortOrder: 0, dateCreated: now)
    koreanBeef = RecipeBrowserRecipe(
      id: ids.next(), title: "Korean Beef", dateCreated: now, dateModified: now
    )
    mexicanBeef = RecipeBrowserRecipe(
      id: ids.next(), title: "Mexican Beef", dateCreated: now, dateModified: now
    )
    koreanPork = RecipeBrowserRecipe(
      id: ids.next(), title: "Korean Pork", dateCreated: now, dateModified: now
    )
    mexicanPork = RecipeBrowserRecipe(
      id: ids.next(), title: "Mexican Pork", dateCreated: now, dateModified: now
    )
  }

  var engine: RecipeBrowserEngine {
    RecipeBrowserEngine(
      recipes: [koreanBeef, mexicanBeef, koreanPork, mexicanPork],
      recipeCategories: [
        .init(id: ids.next(), recipeID: koreanBeef.id, categoryID: korean.id),
        .init(id: ids.next(), recipeID: koreanBeef.id, categoryID: beef.id),
        .init(id: ids.next(), recipeID: mexicanBeef.id, categoryID: mexican.id),
        .init(id: ids.next(), recipeID: mexicanBeef.id, categoryID: beef.id),
        .init(id: ids.next(), recipeID: koreanPork.id, categoryID: korean.id),
        .init(id: ids.next(), recipeID: koreanPork.id, categoryID: pork.id),
        .init(id: ids.next(), recipeID: koreanPork.id, categoryID: weeknight.id),
        .init(id: ids.next(), recipeID: mexicanPork.id, categoryID: mexican.id),
        .init(id: ids.next(), recipeID: mexicanPork.id, categoryID: pork.id),
      ],
      categories: [korean, mexican, beef, tenderloin, pork, weeknight],
      facets: [cuisine, protein]
    )
  }
}
