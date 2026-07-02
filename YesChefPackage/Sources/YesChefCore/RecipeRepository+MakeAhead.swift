import Foundation
import SQLiteData

extension RecipeRepository {
  public static func applyMakeAheadPlan(
    _ plan: MakeAheadPlan,
    to recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try updateMakeAhead(plan.rendered().nonEmptyMakeAheadText, recipeID: recipeID, in: db, now: now)
  }

  public static func clearMakeAhead(recipeID: Recipe.ID, in db: Database, now: Date) throws {
    try updateMakeAhead(nil, recipeID: recipeID, in: db, now: now)
  }

  private static func updateMakeAhead(
    _ makeAhead: String?,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    try Recipe.find(recipeID).update {
      $0.makeAhead = makeAhead
      $0.dateModified = now
    }
    .execute(db)
  }
}

private extension String {
  var nonEmptyMakeAheadText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
