import AppIntents
import Dependencies
import Foundation
import YesChefCore

/// Producer-agnostic door for a new recipe. It stages source text only; the cook reviews and explicitly
/// saves through Create Recipe before any canonical `Recipe` can exist (ADR-0053 Amd2-D1/D4). Cockpit's
/// Find referral uses the same intent with optional provenance and a machine-only correlation token.
struct CaptureRecipeFromText: AppIntent {
  static let title: LocalizedStringResource = "Capture a Recipe from Text"
  static let description = IntentDescription("Open text in Create Recipe for review.")
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @Parameter(title: "Raw Text")
  var rawText: String

  /// JSON-encoded `FindProvenance`. Keeping the App Intent boundary string-valued avoids introducing a
  /// shared App-Intent value type; the core receives the typed value after decoding.
  @Parameter(title: "Provenance JSON")
  var provenance: String?

  @Parameter(title: "Referral ID")
  var referralID: String?

  init() {
    rawText = ""
    provenance = nil
    referralID = nil
  }

  init(text: String) {
    self.init(rawText: text)
  }

  init(rawText: String, provenance: FindProvenance? = nil, referralID: String? = nil) {
    self.rawText = rawText
    self.provenance = provenance.flatMap(Self.encode)
    self.referralID = referralID
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Capture recipe from \(\.$rawText)")
  }

  func perform() async throws -> some OpensIntent & ProvidesDialog {
    guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CaptureRecipeError.emptyText
    }

    let createRecipeCoordinator = DependencyValues._current.createRecipeCoordinator
    if let referralID, !referralID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let decodedProvenance: FindProvenance
      if let provenance {
        guard let value = Self.decode(provenance) else {
          throw CaptureRecipeError.invalidProvenance
        }
        decodedProvenance = value
      } else {
        decodedProvenance = FindProvenance()
      }
      await createRecipeCoordinator.stage(
        referral: FindReferral(
          referralID: referralID,
          rawText: rawText,
          provenance: decodedProvenance
        )
      )
    } else {
      await createRecipeCoordinator.stage(text: rawText)
    }
    return .result(
      opensIntent: OpenCreateRecipeIntent(),
      dialog: "Review the recipe text in Yes Chef."
    )
  }

  private static func encode(_ provenance: FindProvenance) -> String? {
    guard let data = try? JSONEncoder().encode(provenance) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func decode(_ provenance: String) -> FindProvenance? {
    guard let data = provenance.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(FindProvenance.self, from: data)
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
  case invalidProvenance

  var errorDescription: String? {
    switch self {
    case .emptyText:
      "Recipe text is empty. Copy recipe text and try again."
    case .invalidProvenance:
      "The recipe referral context could not be read. Try sending it to Yes Chef again."
    }
  }
}
