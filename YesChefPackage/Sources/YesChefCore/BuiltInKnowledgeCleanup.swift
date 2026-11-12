import Foundation
import SQLiteData

/// Removes only learned rows whose answers are now supplied by the bundled knowledge file.
///
/// `knowledge` drives the area and trip checks. Name fixes are judged by `CanonicalIngredient.baseName`,
/// which always reads the shipped aliases (`BuiltInKnowledge.current`), so injecting other aliases here
/// changes nothing for them.
public enum BuiltInKnowledgeCleanup {
  @discardableResult
  public static func run(in db: Database, knowledge: BuiltInKnowledge) throws -> Int {
    var deleted = 0
    let fixes = try IngredientNameFix.fetchAll(db)
    for fix in fixes where CanonicalIngredient.baseName(fix.fromName) == CanonicalIngredient.baseName(fix.toName) {
      try IngredientNameFix.find(fix.id).delete().execute(db)
      deleted += 1
    }

    let builtInAreas = knowledge.seedAreas
    for assignment in try GroceryAreaAssignment.fetchAll(db) {
      let redundantUser = assignment.source == .user
        && builtInAreas[assignment.canonicalName]?.title == GroceryStoreArea.normalized(assignment.area)?.title
      let shadowedModel = assignment.source == .model && builtInAreas[assignment.canonicalName] != nil
      guard redundantUser || shadowedModel else { continue }
      try GroceryAreaAssignment.find(assignment.id).delete().execute(db)
      deleted += 1
    }

    for assignment in try GroceryTripAssignment.fetchAll(db) {
      guard let rawTrip = knowledge.trips[assignment.canonicalName],
            GroceryTrip(rawValue: rawTrip) == assignment.trip else { continue }
      try GroceryTripAssignment.find(assignment.id).delete().execute(db)
      deleted += 1
    }
    return deleted
  }
}
