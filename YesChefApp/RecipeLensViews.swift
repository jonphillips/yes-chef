import SwiftUI
import YesChefCore

struct SaveRecipeLensView: View {
  let model: PowerBrowserModel
  var onLensCreated: (RecipeLens.ID) -> Void = { _ in }
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  var body: some View {
    NavigationStack {
      Form { TextField("Lens name", text: $name) }
        .navigationTitle("Save as Lens")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              if let id = model.saveLensButtonTapped(name: name) { onLensCreated(id) }
              dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        .onAppear {
          if name.isEmpty { name = model.selectionLabels(for: model.query).first ?? "New Lens" }
        }
    }
  }
}

struct LensSeeAllView: View {
  let title: String
  let rows: [RecipeListRowData]
  let scope: LibraryScope
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  var onCopyShelf: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], alignment: .leading, spacing: 12) {
          ForEach(rows) { row in
            Button {
              onRecipeSelected(RecipeDetailPresentation(recipeID: row.recipe.id, scope: scope))
              dismiss()
            } label: {
              RecipeListRow(row: row, options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding()
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        if let onCopyShelf {
          ToolbarItem(placement: .primaryAction) { Button("Copy shelf", action: onCopyShelf) }
        }
      }
    }
  }
}

struct ChipRow: View {
  var labels: [String]

  var body: some View {
    if labels.isEmpty {
      Text("All recipes").font(.caption).foregroundStyle(.secondary)
    } else {
      ScrollView(.horizontal) {
        HStack {
          ForEach(labels, id: \.self) { label in
            Text(label).font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
              .background(.quaternary, in: Capsule())
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }
}
