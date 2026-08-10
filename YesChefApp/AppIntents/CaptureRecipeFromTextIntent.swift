import AppIntents
import Dependencies
import Foundation

/// Producer-agnostic Shortcuts door for a new recipe. It stages source text only; the cook reviews and
/// explicitly saves through Create Recipe before any canonical `Recipe` can exist (ADR-0053 Amd2-D1/D4).
struct CaptureRecipeFromText: AppIntent {
  static let title: LocalizedStringResource = "Capture a Recipe from Text"
  static let description = IntentDescription("Open text in Create Recipe for review.")
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @Parameter(title: "Recipe Text")
  var text: String

  init() {}

  init(text: String) {
    self.text = text
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Capture recipe from \(\.$text)")
  }

  func perform() async throws -> some OpensIntent & ProvidesDialog {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CaptureRecipeError.emptyText
    }

    let createRecipeCoordinator = DependencyValues._current.createRecipeCoordinator
    await createRecipeCoordinator.stage(text: text)
    return .result(
      opensIntent: OpenCreateRecipeIntent(),
      dialog: "Review the recipe text in Yes Chef."
    )
  }
}

struct OpenCreateRecipeIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Create Recipe"
  static var openAppWhenRun: Bool { true }
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  init() {}

  func perform() async throws -> some IntentResult {
    .result()
  }
}

enum CaptureRecipeError: Error, LocalizedError, Equatable {
  case emptyText

  var errorDescription: String? {
    switch self {
    case .emptyText:
      "Recipe text is empty. Copy recipe text and try again."
    }
  }
}
