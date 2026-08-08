import Dependencies
import Foundation

/// One item of source material a Create Recipe session was given (ADR-0053 D5). The session holds an
/// **ordered list** of these; V1 ships text only (`pastedText`, `typedText`), but it ships the list and
/// the `kind` so an `image`/`url`/`document` source is an addition later, not a rewrite of how a session
/// stores what it was handed. `extractedText` carries a derived transcription where it differs from the
/// original `content` (e.g. a future OCR pass); for the two text kinds they are the same, so it stays nil.
public struct CreateRecipeSourceItem: Identifiable, Equatable, Sendable {
  public enum Kind: String, Codable, Equatable, Sendable {
    case pastedText
    case typedText
  }

  public var id: UUID
  public var kind: Kind
  public var content: String
  public var extractedText: String?

  public init(id: UUID, kind: Kind, content: String, extractedText: String? = nil) {
    self.id = id
    self.kind = kind
    self.content = content
    self.extractedText = extractedText
  }

  /// The text an extraction should read: the derived transcription when present, else the original.
  public var text: String {
    extractedText ?? content
  }
}

/// The two-tier text→recipe front-end for Create Recipe (ADR-0053 S1, holding the ADR-0051 D4 pattern):
/// a deterministic schema.org/JSON-LD parse first — free, no model — and the faithful LLM extraction
/// engine only when the paste is ordinary prose. Both tiers terminate in `RecipeExtraction`, the shared
/// core the sink is built from. Neither tier invents (ADR-0053 D7 / ADR-0051 D3): the LLM engine's
/// system prompt is fidelity-only, and the deterministic tier only reports what the markup stated.
public enum CreateRecipeExtraction {
  public static func extract(text: String) async throws -> RecipeExtraction {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw RecipeExtractionError.emptyRecipe }

    if let deterministic = deterministicJSONLD(trimmed) {
      return deterministic
    }

    @Dependency(\.recipeExtractionClient) var recipeExtractionClient
    return try await recipeExtractionClient(text: trimmed)
  }

  /// The free deterministic tier: a paste that *is* a schema.org `Recipe` JSON-LD block (the same shape
  /// the workbench-return path mines). Returns nil for ordinary prose — no `{`, no recipe node, or a
  /// node with neither ingredients nor instructions — so the caller falls through to the LLM engine
  /// rather than admitting an empty deterministic result.
  static func deterministicJSONLD(_ text: String) -> RecipeExtraction? {
    guard text.contains("{"), text.localizedCaseInsensitiveContains("recipe") else { return nil }
    var builder = RecipeParseBuilder(sourceURL: nil, originalHTML: "")
    RecipeJSONLDExtractor.extract(fromJSONLD: text, into: &builder)
    // `capturedAt` is stamped onto a page field we discard, so a fixed instant keeps this free of a
    // clock dependency.
    let page = builder.build(capturedAt: Date(timeIntervalSince1970: 0))
    guard !page.ingredientSections.isEmpty || !page.instructionSections.isEmpty else { return nil }
    return RecipeExtraction(page: page).cleaned
  }
}
