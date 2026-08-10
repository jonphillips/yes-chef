import Foundation
import SQLiteData

public struct RecipeCuisineCourseFacetBackfillReport: Equatable, Sendable {
  public enum Field: String, Equatable, Sendable {
    case cuisine
    case course
  }

  public struct UnmatchedValue: Equatable, Sendable {
    public var recipeID: Recipe.ID
    public var field: Field
    public var rawValue: String

    public init(recipeID: Recipe.ID, field: Field, rawValue: String) {
      self.recipeID = recipeID
      self.field = field
      self.rawValue = rawValue
    }
  }

  public var assignedCount: Int
  public var clearedCount: Int
  public var alreadyClassifiedCount: Int
  public var unmatchedValues: [UnmatchedValue]

  public init(
    assignedCount: Int = 0,
    clearedCount: Int = 0,
    alreadyClassifiedCount: Int = 0,
    unmatchedValues: [UnmatchedValue] = []
  ) {
    self.assignedCount = assignedCount
    self.clearedCount = clearedCount
    self.alreadyClassifiedCount = alreadyClassifiedCount
    self.unmatchedValues = unmatchedValues
  }

  public var hasFindings: Bool {
    assignedCount > 0 || clearedCount > 0 || alreadyClassifiedCount > 0 || !unmatchedValues.isEmpty
  }

  public var unmatchedCount: Int {
    unmatchedValues.count
  }

  public var logSummary: String {
    let unmatched = unmatchedValues.map {
      "\($0.field.rawValue)(recipeID=\($0.recipeID.uuidString),value=\($0.rawValue))"
    }
    return [
      "cuisine-course-facet-backfill",
      "assignedCount=\(assignedCount)",
      "clearedCount=\(clearedCount)",
      "alreadyClassifiedCount=\(alreadyClassifiedCount)",
      "unmatchedCount=\(unmatchedCount)",
      "unmatched=[\(unmatched.joined(separator: ","))]",
    ]
    .joined(separator: " ")
  }
}

extension RecipeRepository {
  /// Moves known cuisine and course source values into their matching facets. Assignment identities are derived
  /// so each device converges on the same row, and the source column is cleared only once its value has a home.
  public static func backfillCuisineCourseFacets(in db: Database) throws -> RecipeCuisineCourseFacetBackfillReport {
    let facets = try Facet.fetchAll(db)
    let categories = try Category.fetchAll(db)
    let recipes = try Recipe.all.order { $0.id }.fetchAll(db)
    let assignments = try RecipeCategory.fetchAll(db)
    let cuisineFacet = facet(named: "Cuisine", in: facets)
    let courseFacet = facet(named: "Course", in: facets)
    var assignedCategoryIDsByRecipeID = Dictionary(grouping: assignments, by: \.recipeID)
      .mapValues { Set($0.map(\.categoryID)) }
    var report = RecipeCuisineCourseFacetBackfillReport()

    for var recipe in recipes {
      var clearsRecipe = false
      if let cuisineFacet {
        if try backfill(
          rawValue: recipe.cuisine,
          field: .cuisine,
          recipeID: recipe.id,
          facet: cuisineFacet,
          categories: categories,
          assignedCategoryIDsByRecipeID: &assignedCategoryIDsByRecipeID,
          report: &report,
          in: db
        ) {
          recipe.cuisine = ""
          clearsRecipe = true
        }
      }
      if let courseFacet {
        if try backfill(
          rawValue: recipe.course,
          field: .course,
          recipeID: recipe.id,
          facet: courseFacet,
          categories: categories,
          assignedCategoryIDsByRecipeID: &assignedCategoryIDsByRecipeID,
          report: &report,
          in: db
        ) {
          recipe.course = ""
          clearsRecipe = true
        }
      }
      if clearsRecipe {
        try Recipe.upsert { recipe }.execute(db)
      }
    }
    return report
  }

  private static func backfill(
    rawValue: String?,
    field: RecipeCuisineCourseFacetBackfillReport.Field,
    recipeID: Recipe.ID,
    facet: Facet,
    categories: [Category],
    assignedCategoryIDsByRecipeID: inout [Recipe.ID: Set<Category.ID>],
    report: inout RecipeCuisineCourseFacetBackfillReport,
    in db: Database
  ) throws -> Bool {
    guard let rawValue, !normalizedFacetValue(rawValue).isEmpty else { return false }

    let facetValues = categories.filter { $0.facetID == facet.id }
    let facetCategoryIDs = Set(facetValues.map(\.id))
    let category = facetValues
      .filter { normalizedFacetValue($0.name) == normalizedFacetValue(rawValue) }
      .sorted(by: { $0.id.uuidString < $1.id.uuidString })
      .first
    guard let category else {
      report.unmatchedValues.append(.init(recipeID: recipeID, field: field, rawValue: rawValue))
      return false
    }

    if !(assignedCategoryIDsByRecipeID[recipeID] ?? []).isDisjoint(with: facetCategoryIDs) {
      report.alreadyClassifiedCount += 1
      report.clearedCount += 1
      return true
    }

    let assignment = RecipeCategory(
      id: DeterministicID.recipeCategory(recipeID: recipeID, categoryID: category.id),
      recipeID: recipeID,
      categoryID: category.id
    )
    try RecipeCategory.upsert { assignment }.execute(db)
    assignedCategoryIDsByRecipeID[recipeID, default: []].insert(category.id)
    report.assignedCount += 1
    report.clearedCount += 1
    return true
  }

  private static func facet(named name: String, in facets: [Facet]) -> Facet? {
    facets
      .filter { normalizedFacetValue($0.name) == normalizedFacetValue(name) }
      .sorted(by: { $0.id.uuidString < $1.id.uuidString })
      .first
  }

  private static func normalizedFacetValue(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}
