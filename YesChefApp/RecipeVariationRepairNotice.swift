import SwiftUI
import YesChefCore

struct RecipeVariationRepairNotice: View {
  let anchors: [RecipeVariationUnresolvedAnchor]
  let blocksSaving: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Variation Needs Repair", systemImage: "exclamationmark.triangle.fill")
        .font(.title3.bold())
        .foregroundStyle(.orange)
      Text(message)
      Text(anchors.map(\.displayText).joined(separator: "\n"))
        .foregroundStyle(.secondary)
    }
    .attentionCard()
    .accessibilityElement(children: .combine)
  }

  private var message: String {
    if blocksSaving {
      "The remaining changes are applied, but this variation cannot be saved until these original anchors are repaired:"
    } else {
      "The remaining variation changes are applied, but these original anchors need repair:"
    }
  }
}
