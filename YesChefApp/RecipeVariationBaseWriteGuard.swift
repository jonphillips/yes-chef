import SwiftUI
import YesChefCore

/// A variation is a **display-time overlay**: every read path folds it, but no write path knows it
/// exists — the editor and the recipe-body hand-off both act on the base recipe. A write made while a
/// variation is active must *say* it is going to the base rather than silently surprising the cook (Jon
/// hit this on device, 2026-07-21), and ADR-0042 Amd1-OQ3 requires the same of the hand-off door.
///
/// The editor points at the promote release valve; the recipe-body hand-off points at the Choices section,
/// which owns variation-scoped hand-offs.
enum RecipeVariationBaseWriteGuard {
  static func editorNotice(variationName: String) -> String {
    """
    Changes save to the base recipe. “\(variationName)” stays a set of changes on top of it — \
    promote the variation if you want to edit it directly.
    """
  }

  static let handoffConfirmationTitle = "Hand off the base recipe?"

  static func handoffConfirmation(variationName: String) -> String {
    """
    “\(variationName)” is active, but this hand-off sends the base recipe, and any revision you bring \
    back applies to the base. Use its Hand Off action in Choices to revise the variation instead.
    """
  }
}

/// The inline form notice. Kept visually quiet — this is orientation, not an error.
struct RecipeVariationBaseWriteNotice: View {
  let variationName: String

  var body: some View {
    Label {
      Text(RecipeVariationBaseWriteGuard.editorNotice(variationName: variationName))
    } icon: {
      Image(systemName: "info.circle")
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
  }
}
