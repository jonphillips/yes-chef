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
    let proteinFacetID = facetIDsByName["protein"]
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

    recipeIDsByView = [
      .missingProtein: Set(recipes.compactMap { recipe in
        guard let proteinFacetID, !(assignedFacetIDsByRecipeID[recipe.id] ?? []).contains(proteinFacetID) else { return nil }
        return recipe.id
      }),
      .missingPrimaryFacet: Set(recipes.compactMap { recipe in
        let assignments = assignedFacetIDsByRecipeID[recipe.id] ?? []
        return primaryFacetIDs.isSubset(of: assignments) ? nil : recipe.id
      }),
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
      let classifiedRecipeCount = recipes.reduce(into: 0) { count, recipe in
        if (assignedFacetIDsByRecipeID[recipe.id] ?? []).contains(facet.id) { count += 1 }
      }
      return FacetSummary(
        facet: facet,
        classifiedRecipeCount: classifiedRecipeCount,
        unclassifiedRecipeCount: recipes.count - classifiedRecipeCount,
        valueCounts: valueCounts
      )
    }
  }

  public func recipeIDs(matching view: RecipeFacetCoverageView) -> Set<Recipe.ID> {
    recipeIDsByView[view] ?? []
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
