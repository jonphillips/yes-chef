import Foundation
import SQLiteData

/// The derived coverage views used by the label-backfill queue. These are absence predicates,
/// not stored category values: a recipe without a Protein assignment is not "Other."
public enum RecipeFacetCoverageView: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case missingProtein
  case missingPrimaryFacet
  case noEditorialLabels

  public var id: Self { self }

  public var title: String {
    switch self {
    case .missingProtein: "Missing Protein"
    case .missingPrimaryFacet: "Missing a Primary Facet"
    case .noEditorialLabels: "No Editorial Labels"
    }
  }

  public var detail: String {
    switch self {
    case .missingProtein: "No Protein value"
    case .missingPrimaryFacet: "Missing Protein, Dish Type, or Technique"
    case .noEditorialLabels: "No Protein, Dietary, Dish Type, or Technique values"
    }
  }
}

public struct RecipeFacetCoverage: Equatable, Sendable {
  public struct FacetSummary: Identifiable, Equatable, Sendable {
    public var facet: Facet
    public var classifiedRecipeCount: Int
    public var unclassifiedRecipeCount: Int
    public var valueCounts: [ValueCount]

    public var id: Facet.ID { facet.id }
  }

  public struct ValueCount: Identifiable, Equatable, Sendable {
    public var category: Category
    public var recipeCount: Int

    public var id: Category.ID { category.id }
  }

  public var recipeIDsByView: [RecipeFacetCoverageView: Set<Recipe.ID>]
  public var unclassifiedRecipeIDsByFacetID: [Facet.ID: Set<Recipe.ID>]
  public var facetSummaries: [FacetSummary]

  public init(
    recipes: [Recipe],
    recipeCategories: [RecipeCategory],
    categories: [Category],
    facets: [Facet]
  ) {
    let visibleCategories = CategoryRepository.visibleCategories(categories, facets: facets)
    let visibleCategoriesByID = Dictionary(uniqueKeysWithValues: visibleCategories.map { ($0.id, $0) })
    let visibleFacets = CategoryRepository.sortedFacets(facets.filter { !$0.hidden })
    let facetIDsByName = Dictionary(
      uniqueKeysWithValues: visibleFacets.map { ($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current), $0.id) }
    )
    let editorialFacetIDs = Set(["Protein", "Dietary", "Dish Type", "Technique"].compactMap {
      facetIDsByName[$0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)]
    })
    let primaryFacetIDs = Set(["Protein", "Dish Type", "Technique"].compactMap {
      facetIDsByName[$0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)]
    })
    let assignedCategoryIDsByRecipeID = Dictionary(grouping: recipeCategories, by: \.recipeID)
      .mapValues { Set($0.map(\.categoryID)) }
    let assignedFacetIDsByRecipeID = Dictionary(
      uniqueKeysWithValues: recipes.map { recipe in
        let facetIDs = Set((assignedCategoryIDsByRecipeID[recipe.id] ?? []).compactMap {
          visibleCategoriesByID[$0]?.facetID
        })
        return (recipe.id, facetIDs)
      }
    )

    let unclassifiedByFacetID = Dictionary(
      uniqueKeysWithValues: visibleFacets.map { facet in
        (facet.id, Self.unclassifiedRecipeIDs(
          inFacetID: facet.id,
          recipeIDs: recipes.map(\.id),
          assignedFacetIDsByRecipeID: assignedFacetIDsByRecipeID
        ))
      }
    )
    unclassifiedRecipeIDsByFacetID = unclassifiedByFacetID
    recipeIDsByView = [
      .missingProtein: facetIDsByName["protein"].flatMap { unclassifiedByFacetID[$0] } ?? [],
      .missingPrimaryFacet: primaryFacetIDs.reduce(into: Set<Recipe.ID>()) { result, facetID in
        result.formUnion(unclassifiedByFacetID[facetID] ?? [])
      },
      .noEditorialLabels: Set(recipes.compactMap { recipe in
        let assignments = assignedFacetIDsByRecipeID[recipe.id] ?? []
        return assignments.isDisjoint(with: editorialFacetIDs) ? recipe.id : nil
      }),
    ]

    facetSummaries = visibleFacets.map { facet in
      let values = CategoryRepository.sortedCategories(visibleCategories.filter { $0.facetID == facet.id })
      let valueCounts = values.map { category in
        ValueCount(
          category: category,
          recipeCount: recipes.reduce(into: 0) { count, recipe in
            if assignedCategoryIDsByRecipeID[recipe.id]?.contains(category.id) == true { count += 1 }
          }
        )
      }
      let unclassifiedRecipeCount = unclassifiedByFacetID[facet.id]?.count ?? recipes.count
      return FacetSummary(
        facet: facet,
        classifiedRecipeCount: recipes.count - unclassifiedRecipeCount,
        unclassifiedRecipeCount: unclassifiedRecipeCount,
        valueCounts: valueCounts
      )
    }
  }

  public func recipeIDs(matching view: RecipeFacetCoverageView) -> Set<Recipe.ID> {
    recipeIDsByView[view] ?? []
  }

  public func recipeIDs(unclassifiedInFacetID facetID: Facet.ID) -> Set<Recipe.ID> {
    unclassifiedRecipeIDsByFacetID[facetID] ?? []
  }

  /// The single absence predicate behind both the D8 facet counts and discovery lists.
  public static func unclassifiedRecipeIDs(
    inFacetID facetID: Facet.ID,
    recipes: [Recipe],
    recipeCategories: [RecipeCategory],
    categories: [Category],
    facets: [Facet]
  ) -> Set<Recipe.ID> {
    let visibleCategoriesByID = Dictionary(
      uniqueKeysWithValues: CategoryRepository.visibleCategories(categories, facets: facets).map { ($0.id, $0) }
    )
    let assignedFacetIDsByRecipeID = Dictionary(grouping: recipeCategories, by: \.recipeID)
      .mapValues { recipeCategories in
        Set(recipeCategories.compactMap { visibleCategoriesByID[$0.categoryID]?.facetID })
      }
    return unclassifiedRecipeIDs(
      inFacetID: facetID,
      recipeIDs: recipes.map(\.id),
      assignedFacetIDsByRecipeID: assignedFacetIDsByRecipeID
    )
  }

  private static func unclassifiedRecipeIDs(
    inFacetID facetID: Facet.ID,
    recipeIDs: [Recipe.ID],
    assignedFacetIDsByRecipeID: [Recipe.ID: Set<Facet.ID>]
  ) -> Set<Recipe.ID> {
    Set(recipeIDs.filter { !(assignedFacetIDsByRecipeID[$0] ?? []).contains(facetID) })
  }
}

public struct RecipeFacetCoverageRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> RecipeFacetCoverage {
    RecipeFacetCoverage(
      recipes: try Recipe.fetchAll(db),
      recipeCategories: try RecipeCategory.fetchAll(db),
      categories: try Category.fetchAll(db),
      facets: try Facet.fetchAll(db)
    )
  }
}

public extension RecipeDetailData {
  var labelProposalRecipe: LabelProposalRecipe {
    LabelProposalRecipe(
      title: recipe.title,
      summary: recipe.summary,
      publisherName: source?.name,
      ingredientLines: ingredientLines.filter { !$0.isHeader }.map(\.originalText)
    )
  }
}
