import SwiftUI
import YesChefCore

struct RecipeDeliberationLogEntriesView: View {
  let entries: [RecipeDeliberationLogEntry]
  let variations: [RecipeVariation]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(entries) { entry in
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.dateCreated, format: .dateTime.month(.abbreviated).day().year().hour().minute())
              .font(.caption)
              .foregroundStyle(.secondary)
            if let variationName = variationName(for: entry) {
              Label(variationName, systemImage: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Text(entry.body)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func variationName(for entry: RecipeDeliberationLogEntry) -> String? {
    guard let variationID = entry.variationID else { return nil }
    return variations.first { $0.id == variationID }?.name
  }
}
