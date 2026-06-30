import SwiftUI
import YesChefCore

struct OriginalSnapshotView: View {
  let recipe: Recipe?
#if DEBUG
  @State private var originalImportDOMExport: OriginalImportDOMExport?
  @State private var originalImportDOMExportError: String?
  @State private var isShowingOriginalImportDOMExportError = false
#endif

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
#if DEBUG
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if let originalImportDOMExport {
          ShareLink(item: originalImportDOMExport.fileURL) {
            Label("Export DOM", systemImage: "square.and.arrow.up")
          }
        }
      }
    }
    .task(id: recipe?.id) {
      prepareOriginalImportDOMExport()
    }
    .alert("Could Not Export DOM", isPresented: $isShowingOriginalImportDOMExportError) {
      Button("OK") {}
    } message: {
      Text(originalImportDOMExportError ?? "")
    }
#endif
  }

#if DEBUG
  private func prepareOriginalImportDOMExport() {
    do {
      originalImportDOMExport = try Self.makeOriginalImportDOMExport(for: recipe)
      originalImportDOMExportError = nil
      isShowingOriginalImportDOMExportError = false
    } catch {
      originalImportDOMExport = nil
      originalImportDOMExportError = String(describing: error)
      isShowingOriginalImportDOMExportError = true
    }
  }

  private static func makeOriginalImportDOMExport(for recipe: Recipe?) throws -> OriginalImportDOMExport? {
    guard let recipe, let html = recipe.originalImportText, !html.isEmpty else { return nil }

    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefDebugDOMExports", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileURL = directoryURL
      .appendingPathComponent("\(slug(for: recipe.title))-\(recipe.id.uuidString).html")
    try html.write(to: fileURL, atomically: true, encoding: .utf8)
    return OriginalImportDOMExport(fileURL: fileURL)
  }

  private static func slug(for title: String) -> String {
    let slug = String(title
      .lowercased()
      .map { character in
        character.isLetter || character.isNumber ? character : "-"
      }
      .split(separator: "-")
      .joined(separator: "-"))
    return slug.isEmpty ? "recipe" : slug
  }
#endif
}

#if DEBUG
private struct OriginalImportDOMExport {
  var fileURL: URL
}
#endif

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
