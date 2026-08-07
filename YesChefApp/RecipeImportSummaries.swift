import Foundation
import YesChefCore

// Split out of RecipeModels.swift to keep that file under the SwiftLint file-length budget.

struct RecipeImportSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var importedCount: Int
  var alreadyImportedCount: Int
  var warningCount: Int
  var identityWarningCount: Int
  var missingRecipePageCount: Int
  var missingPhotoCount: Int
  var unreadableRecipeCount: Int
  var importedIDs: [Recipe.ID]
  var rollbackDeletedRecipeCount: Int

  init(
    importedCount: Int,
    alreadyImportedCount: Int,
    warningCount: Int,
    identityWarningCount: Int,
    missingRecipePageCount: Int,
    missingPhotoCount: Int,
    unreadableRecipeCount: Int,
    importedIDs: [Recipe.ID] = [],
    rollbackDeletedRecipeCount: Int = 0
  ) {
    self.importedCount = importedCount
    self.alreadyImportedCount = alreadyImportedCount
    self.warningCount = warningCount
    self.identityWarningCount = identityWarningCount
    self.missingRecipePageCount = missingRecipePageCount
    self.missingPhotoCount = missingPhotoCount
    self.unreadableRecipeCount = unreadableRecipeCount
    self.importedIDs = importedIDs
    self.rollbackDeletedRecipeCount = rollbackDeletedRecipeCount
  }

  init(parseResult: PaprikaHTMLImportResult, importResult: RecipeImportBatchResult) {
    self.init(
      importedCount: importResult.importedCount,
      alreadyImportedCount: importResult.alreadyImportedCount,
      warningCount: parseResult.warnings.count + importResult.warnings.count,
      identityWarningCount: importResult.warnings.count,
      missingRecipePageCount: parseResult.warnings
        .filter { $0.kind == .missingRecipePages }
        .compactMap(\.affectedCount)
        .reduce(0, +),
      missingPhotoCount: parseResult.warnings.filter { $0.kind == .missingPhoto }.count,
      unreadableRecipeCount: parseResult.warnings.filter { $0.kind == .unreadableRecipe }.count,
      importedIDs: importResult.importedIDs
    )
  }

  var message: String {
    var lines = ["Imported \(importedCount) \(importedCount == 1 ? "recipe" : "recipes")."]
    if rollbackDeletedRecipeCount > 0 {
      lines = ["Undo removed \(rollbackDeletedRecipeCount) imported \(rollbackDeletedRecipeCount == 1 ? "recipe" : "recipes")."]
    }
    if alreadyImportedCount > 0 {
      lines.append("Skipped \(alreadyImportedCount) already-imported \(alreadyImportedCount == 1 ? "recipe" : "recipes").")
    }
    if missingRecipePageCount > 0 {
      lines.append("\(missingRecipePageCount) index \(missingRecipePageCount == 1 ? "entry was" : "entries were") missing from the ZIP.")
    }
    if missingPhotoCount > 0 {
      lines.append("\(missingPhotoCount) image \(missingPhotoCount == 1 ? "file was" : "files were") missing.")
    }
    if unreadableRecipeCount > 0 {
      lines.append("\(unreadableRecipeCount) recipe \(unreadableRecipeCount == 1 ? "page could" : "pages could") not be read.")
    }
    if identityWarningCount > 0 {
      lines.append("\(identityWarningCount) import identity \(identityWarningCount == 1 ? "warning" : "warnings").")
    }
    if warningCount == 0 {
      lines.append("No warnings.")
    }
    return lines.joined(separator: "\n")
  }

  var canUndo: Bool {
    rollbackDeletedRecipeCount == 0 && !importedIDs.isEmpty
  }

  func rolledBack(_ rollback: RecipeImportRollbackResult) -> Self {
    RecipeImportSummary(
      importedCount: importedCount,
      alreadyImportedCount: alreadyImportedCount,
      warningCount: warningCount,
      identityWarningCount: identityWarningCount,
      missingRecipePageCount: missingRecipePageCount,
      missingPhotoCount: missingPhotoCount,
      unreadableRecipeCount: unreadableRecipeCount,
      importedIDs: rollback.recipes > 0 ? [] : importedIDs,
      rollbackDeletedRecipeCount: rollback.recipes
    )
  }
}

struct RecipeBackupSupplementSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var summary: PaprikaRecipeBackupSupplementSummary

  var message: String {
    [
      "Read \(summary.backupRecipeCount) \(summary.backupRecipeCount == 1 ? "backup recipe" : "backup recipes").",
      "Updated \(summary.updatedRecipeCount) \(summary.updatedRecipeCount == 1 ? "recipe" : "recipes").",
      "Left \(summary.unchangedRecipeCount) already-correct \(summary.unchangedRecipeCount == 1 ? "recipe" : "recipes") unchanged.",
      "\(summary.unmatchedRecipeCount) did not match an existing recipe.",
      "\(summary.ambiguousRecipeCount) had ambiguous title matches.",
      "\(summary.skippedRecordCount) \(summary.skippedRecordCount == 1 ? "record was" : "records were") skipped."
    ]
    .joined(separator: "\n")
  }
}
