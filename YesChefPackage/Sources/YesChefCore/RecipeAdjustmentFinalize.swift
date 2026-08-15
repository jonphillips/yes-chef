import Foundation

/// How a recipe-body ("Adjust Recipe") hand-off was finalized in the external conversation.
///
/// The cook chooses at finalize time, in the conversation — not at export (ADR-0042 Amd: two
/// finalize outcomes). We recover the choice from the return's **shape**, not from a keyword: a new
/// recipe arrives as a schema.org `Recipe` JSON-LD object (per `RecipeJSONLDContract`); a revision
/// arrives as prose. Prose that merely mentions "recipe" carries no parseable Recipe object and
/// stays a revision.
///
/// The one cross-contamination case — a full JSON recipe returned when the cook only wanted a tweak
/// — is accepted by design: it opens Create Recipe (a visible, one-tap-discard draft), and the
/// prompt explicitly guards against it ("a revision is never a rewritten full recipe").
public enum RecipeAdjustmentFinalize: Equatable, Sendable {
  case revisionBrief
  case newRecipe

  /// Classifies a token-stripped recipe-body return payload by shape. Reuses the exact detection the
  /// workbench-draft path uses: split the deliverable's JSON-LD block and run the deterministic
  /// extractor. `WorkbenchDraftRecipe.fromJSONLD` yields `nil` unless the block has ingredients or
  /// instructions, so a real Recipe object is required to route to `.newRecipe`. `capturedAt` is
  /// provenance-only and irrelevant to classification.
  public static func classify(payload: String) -> RecipeAdjustmentFinalize {
    let unmarked = AIHandoffReturnContract.strippingMarker(from: payload) ?? payload
    let deliverable = AIHandoffReturn.plainText(from: unmarked).deliverable
    let jsonLD = AIHandoffReturn.splittingJSONLDAndRationale(deliverable).jsonLD
    let draft = WorkbenchDraftRecipe.fromJSONLD(jsonLD, rationale: "", capturedAt: .distantPast)
    return draft == nil ? .revisionBrief : .newRecipe
  }
}
