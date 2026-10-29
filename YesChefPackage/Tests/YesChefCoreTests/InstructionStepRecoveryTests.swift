import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized)
struct InstructionStepRecoveryTests {
  @Test
  func recoversOnlyMissingStepsWithValidParentsAndIsIdempotent() async throws {
    let directory = try recoveryTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let backupURL = directory.appendingPathComponent("backup.sqlite")
    let liveURL = directory.appendingPathComponent("live.sqlite")

    let recipeA = UUID()
    let recipeB = UUID()
    let missingRecipe = UUID()
    let sectionA = UUID()
    let sectionB = UUID()
    let missingRecipeSection = UUID()
    let recoverableID = UUID()
    let existingID = UUID()
    let missingRecipeID = UUID()
    let missingSectionID = UUID()
    let wrongRecipeSectionID = UUID()
    let timestamp = Date(timeIntervalSinceReferenceDate: 812_000_000)

    let backup = try recoveryDatabase(at: backupURL)
    try await backup.write { db in
      for (id, title) in [(recipeA, "A"), (recipeB, "B"), (missingRecipe, "Missing")] {
        try Recipe.insert {
          Recipe(id: id, title: title, dateCreated: timestamp, dateModified: timestamp)
        }.execute(db)
      }
      try InstructionSection.insert {
        [
          InstructionSection(id: sectionA, recipeID: recipeA, name: "Main", sortOrder: 0),
          InstructionSection(id: sectionB, recipeID: recipeA, name: "Absent", sortOrder: 1),
          InstructionSection(id: missingRecipeSection, recipeID: missingRecipe, sortOrder: 0),
        ]
      }.execute(db)
      try InstructionStep.insert {
        [
          InstructionStep(id: recoverableID, recipeID: recipeA, sectionID: sectionA, text: "Recovered exactly.", sortOrder: 4, isOptional: true),
          InstructionStep(id: existingID, recipeID: recipeA, sectionID: sectionA, text: "Backup version.", sortOrder: 5),
          InstructionStep(id: missingRecipeID, recipeID: missingRecipe, sectionID: missingRecipeSection, text: "No recipe.", sortOrder: 0),
          InstructionStep(id: missingSectionID, recipeID: recipeA, sectionID: sectionB, text: "No section.", sortOrder: 0),
          InstructionStep(id: wrongRecipeSectionID, recipeID: recipeB, sectionID: sectionA, text: "Mismatched parent.", sortOrder: 0),
        ]
      }.execute(db)
    }
    try backup.close()
    let originalBackupBytes = try Data(contentsOf: backupURL)

    let live = try recoveryDatabase(at: liveURL)
    try await live.write { db in
      for (id, title) in [(recipeA, "A"), (recipeB, "B")] {
        try Recipe.insert {
          Recipe(id: id, title: title, dateCreated: timestamp, dateModified: timestamp)
        }.execute(db)
      }
      try InstructionSection.insert {
        InstructionSection(id: sectionA, recipeID: recipeA, name: "Main", sortOrder: 0)
      }.execute(db)
      try InstructionStep.insert {
        InstructionStep(id: existingID, recipeID: recipeA, sectionID: sectionA, text: "Keep live version.", sortOrder: 5)
      }.execute(db)
    }

    let plan = try InstructionStepRecovery.plan(from: backupURL, in: live)
    #expect(plan.steps == [
      InstructionStep(id: recoverableID, recipeID: recipeA, sectionID: sectionA, text: "Recovered exactly.", sortOrder: 4, isOptional: true),
    ])
    #expect(plan.recipeCount == 1)
    #expect(plan.skippedCount == 3)
    #expect(try Data(contentsOf: backupURL) == originalBackupBytes)

    #expect(try InstructionStepRecovery.apply(plan, in: live) == 1)
    #expect(try InstructionStepRecovery.apply(plan, in: live) == 0)
    let rows = try await live.read { db in
      try InstructionStep.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
    }
    #expect(rows.first(where: { $0.id == recoverableID }) == plan.steps[0])
    #expect(rows.first(where: { $0.id == existingID })?.text == "Keep live version.")
    #expect(try InstructionStepRecovery.plan(from: backupURL, in: live).steps.isEmpty)
    try live.close()
  }
}

private func recoveryTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("YesChefInstructionStepRecoveryTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func recoveryDatabase(at url: URL) throws -> any DatabaseWriter {
  try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  return try withDependencies {
    $0.context = .live
  } operation: {
    var dependencies = DependencyValues()
    try dependencies.bootstrapDatabase(path: url.path)
    return dependencies.defaultDatabase
  }
}
