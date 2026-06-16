import SwiftUI
import YesChefCore

struct OriginalSnapshotView: View {
  let recipe: Recipe?

  private var snapshot: RecipeBundleCoding.Snapshot? {
    guard let data = recipe?.originalSnapshot else { return nil }
    return try? RecipeBundleCoding.decodeSnapshot(data)
  }

  var body: some View {
    ScrollView {
      if let snapshot {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.recipe.title)
              .font(.largeTitle.bold())
            if let subtitle = snapshot.recipe.subtitle {
              Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            }
            if let summary = snapshot.recipe.summary {
              Text(summary)
            }
          }

          if let source = snapshot.source, source.name != nil || source.url != nil {
            VStack(alignment: .leading, spacing: 6) {
              Text("Source")
                .font(.headline)
              Text([source.name, source.url].compactMap { $0 }.joined(separator: "\n"))
            }
          }

          SnapshotSection(title: "Ingredients", rows: snapshot.ingredients)
          SnapshotSection(title: "Instructions", rows: snapshot.instructions)
          SnapshotSection(title: "Notes", rows: snapshot.notes)
          SnapshotSection(title: "Tags", rows: snapshot.tags)
          SnapshotSection(title: "Categories", rows: snapshot.categories)
        }
        .padding()
        .frame(maxWidth: 860, alignment: .leading)
      } else {
        ContentUnavailableView("No Original Snapshot", systemImage: "doc.text")
      }
    }
    .navigationTitle("Original")
  }
}

private struct SnapshotSection: View {
  let title: String
  let rows: [String]

  var body: some View {
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text(title)
          .font(.title2.bold())
        ForEach(rows, id: \.self) { row in
          Text(row)
        }
      }
    }
  }
}

