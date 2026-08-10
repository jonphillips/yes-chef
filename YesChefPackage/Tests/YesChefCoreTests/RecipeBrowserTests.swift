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
    func anEmptyQueryOffersEveryDividingFacetWithSelfExcludingCounts() throws {
      let fixture = BrowserFixture()

      let result = fixture.engine.result(for: RecipeBrowserQuery())

      expectNoDifference(result.matchingRecipeIDs.count, 4)
      expectNoDifference(result.availableFacets.map(\.facet.id), [fixture.protein.id, fixture.cuisine.id])
      let cuisineValues = try #require(result.availableFacets.first { $0.facet.id == fixture.cuisine.id }?.values)
      expectNoDifference(cuisineValues.map(\.category.id), [fixture.korean.id, fixture.mexican.id])
      expectNoDifference(cuisineValues.map(\.matchingRecipeCount), [2, 2])
      let proteinValues = try #require(result.availableFacets.first { $0.facet.id == fixture.protein.id }?.values)
      expectNoDifference(proteinValues.map(\.category.id), [fixture.beef.id, fixture.pork.id])
      expectNoDifference(proteinValues.map(\.matchingRecipeCount), [2, 2])
    }

    @Test
    func typedAttributeAndUsageFiltersAreAndedAtTheSharedEngineBoundary() {
      let fixture = BrowserFixture()
      let olderDate = fixture.now.addingTimeInterval(-86_400)
      let matching = RecipeBrowserRecipe(
        id: fixture.ids.next(),
        title: "Weeknight Braise",
        dateCreated: fixture.now,
        dateModified: fixture.now,
        totalTimeMinutes: 45,
        servings: 6,
        rating: 5,
        timesCooked: 6,
        makeAheadText: "Braised dishes improve overnight."
      )
      let tooSlow = RecipeBrowserRecipe(
        id: fixture.ids.next(),
        title: "Slow Braise",
        dateCreated: fixture.now,
        dateModified: fixture.now,
        totalTimeMinutes: 90,
        servings: 6,
        rating: 5,
        timesCooked: 6,
        makeAheadText: "Braised dishes improve overnight."
      )
      let neverCooked = RecipeBrowserRecipe(
        id: fixture.ids.next(),
        title: "New Recipe",
        dateCreated: fixture.now,
        dateModified: fixture.now,
        totalTimeMinutes: 45,
        servings: 6,
        rating: 5,
        timesCooked: 0,
        makeAheadText: "Make it early."
      )
      let oldRecipe = RecipeBrowserRecipe(
        id: fixture.ids.next(),
        title: "Old Recipe",
        dateCreated: olderDate,
        dateModified: olderDate,
        totalTimeMinutes: 45,
        servings: 6,
        rating: 5,
        timesCooked: 6,
        makeAheadText: "Make it early."
      )
      let engine = RecipeBrowserEngine(recipes: [matching, tooSlow, neverCooked, oldRecipe], recipeCategories: [], categories: [], facets: [])

      expectNoDifference(
        engine.matchingRecipeIDs(
          for: RecipeBrowserQuery(
            attributeFilters: [
              .totalTimeAtMost(45),
              .servingsAtLeast(6),
              .ratingAtLeast(5),
              .hasMakeAhead,
              .addedAfter(olderDate.addingTimeInterval(1)),
              .cookedMoreThan(5),
            ]
          )
        ),
        [matching.id]
      )
      expectNoDifference(
        engine.matchingRecipeIDs(for: RecipeBrowserQuery(attributeFilters: [.neverCooked])),
        [neverCooked.id]
      )
    }

    @Test
    func sourceValuesAreAlternativesWithinAFieldAndDifferentFieldsAreAnded() {
      let fixture = BrowserFixture()
      let matching = RecipeBrowserRecipe(id: fixture.ids.next(), title: "Book Recipe", dateCreated: fixture.now, dateModified: fixture.now)
      let wrongAuthor = RecipeBrowserRecipe(id: fixture.ids.next(), title: "Other Author", dateCreated: fixture.now, dateModified: fixture.now)
      let wrongBook = RecipeBrowserRecipe(id: fixture.ids.next(), title: "Other Book", dateCreated: fixture.now, dateModified: fixture.now)
      let engine = RecipeBrowserEngine(
        recipes: [matching, wrongAuthor, wrongBook],
        recipeCategories: [],
        categories: [],
        facets: [],
        sources: [
          .init(recipeID: matching.id, author: "Samin Nosrat", cookbook: "Salt Fat Acid Heat"),
          .init(recipeID: wrongAuthor.id, author: "Other Cook", cookbook: "Salt Fat Acid Heat"),
          .init(recipeID: wrongBook.id, author: "Samin Nosrat", cookbook: "Other Book"),
        ]
      )

      expectNoDifference(
        engine.matchingRecipeIDs(
          for: RecipeBrowserQuery(
            sourceFilters: [
              .values(field: .author, values: ["Samin Nosrat", "Other Cook"]),
              .values(field: .cookbook, values: ["Salt Fat Acid Heat"]),
            ]
          )
        ),
        [matching.id, wrongAuthor.id]
      )
    }

    @Test
    func selectingOneFacetKeepsOtherFacetsAvailableWithNarrowedCounts() throws {
      let fixture = BrowserFixture()

      let result = fixture.engine.result(
        for: RecipeBrowserQuery(
          facetSelections: [.init(facetID: fixture.cuisine.id, categoryIDs: [fixture.korean.id])]
        )
      )

      expectNoDifference(result.matchingRecipeIDs, [fixture.koreanBeef.id, fixture.koreanPork.id])
      let proteinValues = try #require(result.availableFacets.first { $0.facet.id == fixture.protein.id }?.values)
      expectNoDifference(proteinValues.map(\.category.id), [fixture.beef.id, fixture.pork.id])
      expectNoDifference(proteinValues.map(\.matchingRecipeCount), [1, 1])
      expectNoDifference(proteinValues.map(\.isSelected), [false, false])
    }

    @Test
    func aFacetWithASingleDividingValueStaysAvailable() throws {
      // Sparse coverage: three Korean recipes, only one carries a Protein value. Selecting
      // Korean must still offer Protein → Beef (1) as a valid narrowing rather than hiding the
      // facet for having fewer than two populated values (D4).
      let fixture = BrowserFixture()
      let koreanStew = RecipeBrowserRecipe(
        id: fixture.ids.next(), title: "Korean Stew", dateCreated: fixture.now, dateModified: fixture.now
      )
      let koreanSoup = RecipeBrowserRecipe(
        id: fixture.ids.next(), title: "Korean Soup", dateCreated: fixture.now, dateModified: fixture.now
      )
      let engine = RecipeBrowserEngine(
        recipes: [fixture.koreanBeef, koreanStew, koreanSoup],
        recipeCategories: [
          .init(id: fixture.ids.next(), recipeID: fixture.koreanBeef.id, categoryID: fixture.korean.id),
          .init(id: fixture.ids.next(), recipeID: fixture.koreanBeef.id, categoryID: fixture.beef.id),
          .init(id: fixture.ids.next(), recipeID: koreanStew.id, categoryID: fixture.korean.id),
          .init(id: fixture.ids.next(), recipeID: koreanSoup.id, categoryID: fixture.korean.id),
        ],
        categories: [fixture.korean, fixture.mexican, fixture.beef, fixture.pork],
        facets: [fixture.cuisine, fixture.protein]
      )

      let result = engine.result(
        for: RecipeBrowserQuery(
          facetSelections: [.init(facetID: fixture.cuisine.id, categoryIDs: [fixture.korean.id])]
        )
      )

      expectNoDifference(result.matchingRecipeIDs.count, 3)
      let proteinValues = try #require(result.availableFacets.first { $0.facet.id == fixture.protein.id }?.values)
      expectNoDifference(proteinValues.map(\.category.id), [fixture.beef.id])
      expectNoDifference(proteinValues.map(\.matchingRecipeCount), [1])
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
