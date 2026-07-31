import Foundation
import YesChefCore

struct WebRecipeCaptureSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var title: String
  var outcome: RecipeImportOutcome
  var warningCount: Int

  init(result: RecipeImportBundleResult) {
    self.title = result.title
    self.outcome = result.outcome
    self.warningCount = result.warnings.count
  }

  var message: String {
    var lines: [String]
    switch outcome {
    case .imported:
      lines = ["Saved \(title)."]
    case .alreadyImported:
      lines = ["Skipped \(title) because it is already in your library."]
    }
    if warningCount > 0 {
      lines.append("\(warningCount) identity \(warningCount == 1 ? "warning" : "warnings").")
    }
    return lines.joined(separator: "\n")
  }
}
