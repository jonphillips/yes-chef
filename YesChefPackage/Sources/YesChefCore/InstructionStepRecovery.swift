import Foundation
import SQLiteData

/// Plans and applies the one-table recovery needed for PROD-CUTOVER Step 10a.
public enum InstructionStepRecovery {
  public struct Plan: Equatable, Sendable {
    public let steps: [InstructionStep]
    public let recipeCount: Int
    public let skippedCount: Int

    public var stepCount: Int { steps.count }
  }

  /// Reads a migrated copy of the backup. The selected backup is never opened or modified.
  public static func plan(from backupURL: URL, in liveDatabase: any DatabaseWriter) throws -> Plan {
    let workingDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefInstructionStepRecovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workingDirectory) }

    let candidateURL = workingDirectory.appendingPathComponent("candidate.sqlite")
    try FileManager.default.copyItem(at: backupURL, to: candidateURL)
    try DependencyValues.migrateRestoreCandidate(at: candidateURL)

    let backupDatabase = try DatabaseQueue(path: candidateURL.path)
    defer { try? backupDatabase.close() }

    let backupSteps = try backupDatabase.read { try InstructionStep.fetchAll($0) }
    let liveState = try liveDatabase.read { db -> LiveState in
      LiveState(
        recipeIDs: Set(try Recipe.fetchAll(db).map(\.id)),
        sections: Dictionary(uniqueKeysWithValues: try InstructionSection.fetchAll(db).map { ($0.id, $0.recipeID) }),
        stepIDs: Set(try InstructionStep.fetchAll(db).map(\.id))
      )
    }

    var recovered: [InstructionStep] = []
    var skippedCount = 0
    for step in backupSteps {
      guard liveState.recipeIDs.contains(step.recipeID),
            liveState.sections[step.sectionID] == step.recipeID else {
        skippedCount += 1
        continue
      }
      guard !liveState.stepIDs.contains(step.id) else { continue }
      recovered.append(step)
    }

    return Plan(
      steps: recovered,
      recipeCount: Set(recovered.map(\.recipeID)).count,
      skippedCount: skippedCount
    )
  }

  /// Rechecks all parents in the write transaction and inserts only still-missing rows.
  @discardableResult
  public static func apply(_ plan: Plan, in database: any DatabaseWriter) throws -> Int {
    try database.write { db in
      let recipeIDs = Set(try Recipe.fetchAll(db).map(\.id))
      let sections = Dictionary(uniqueKeysWithValues: try InstructionSection.fetchAll(db).map { ($0.id, $0.recipeID) })
      let existingStepIDs = Set(try InstructionStep.fetchAll(db).map(\.id))
      var insertedCount = 0

      for step in plan.steps where
        !existingStepIDs.contains(step.id) &&
        recipeIDs.contains(step.recipeID) &&
        sections[step.sectionID] == step.recipeID {
        try InstructionStep.insert { step }.execute(db)
        insertedCount += 1
      }
      return insertedCount
    }
  }

  private struct LiveState {
    let recipeIDs: Set<Recipe.ID>
    let sections: [InstructionSection.ID: Recipe.ID]
    let stepIDs: Set<InstructionStep.ID>
  }
}
