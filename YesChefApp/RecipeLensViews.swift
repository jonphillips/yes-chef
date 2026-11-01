import SwiftUI
import YesChefCore

struct RecipeLensShelvesView: View {
  let model: PowerBrowserModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    let evaluation = model.lensEvaluation
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        if let lens = model.selectedLens {
          VStack(alignment: .leading, spacing: 8) {
            Text(lens.name).font(.largeTitle.bold())
            ChipRow(labels: model.selectionLabels(for: (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()))
          }
          .padding(.horizontal)
        }
        if let evaluation {
          if case let .unresolved(reasons) = evaluation.baseState {
            ContentUnavailableView {
              Label("Lens base needs repair", systemImage: "exclamationmark.triangle")
            } description: {
              Text(reasons.joined(separator: " "))
            } actions: {
              Button("Fix") {
                if let lens = model.selectedLens { model.editLensBaseQueryButtonTapped(lens) }
              }
            }
            .frame(minHeight: 180)
          }
          ForEach(evaluation.shelves) { shelfResult in
            switch shelfResult.state {
            case .empty:
              EmptyView()
            case let .unresolved(reasons):
              ContentUnavailableView {
                Label(shelfResult.shelf.title, systemImage: "exclamationmark.triangle")
              } description: {
                Text(reasons.joined(separator: " "))
              } actions: {
                Button("Fix") { model.editLensButtonTapped() }
              }
              .frame(minHeight: 180)
            case let .ready(ids):
              ShelfRow(
                title: shelfResult.shelf.title,
                rows: model.recipeRows(for: RecipeBrowserResult(matchingRecipeIDs: ids, availableFacets: [])),
                onSeeAll: { model.presentShelf(shelfResult.shelf) },
                onRecipeSelected: onRecipeSelected
              )
            }
          }
          if model.selectedLens?.showsRemainder == true, !evaluation.remainderRecipeIDs.isEmpty {
            ShelfRow(
              title: "Everything else",
              rows: model.recipeRows(for: RecipeBrowserResult(matchingRecipeIDs: evaluation.remainderRecipeIDs, availableFacets: [])),
              onSeeAll: { model.presentRemainder() },
              onRecipeSelected: onRecipeSelected
            )
          }
        }
      }
      .padding(.vertical)
    }
    .navigationTitle(model.selectedLens?.name ?? "Lens")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct ShelfRow: View {
  let title: String
  let rows: [RecipeListRowData]
  let onSeeAll: () -> Void
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title).font(.title2.bold())
        Text(rows.count, format: .number).foregroundStyle(.secondary)
        Spacer()
        Button("See all", action: onSeeAll)
      }
      .padding(.horizontal)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 16) {
          ForEach(rows) { row in
            Button { onRecipeSelected(RecipeDetailPresentation(recipeID: row.recipe.id)) } label: {
              RecipeListRow(row: row, options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true))
                .frame(width: 340)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal)
      }
    }
  }
}

struct RecipeLensEditorView: View {
  let model: PowerBrowserModel
  let lens: RecipeLens
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var showsRemainder = true
  @State private var editingShelf: RecipeLensShelf.ID?
  @State private var shelfTitleDraft = ""
  @State private var isRenamingShelf = false

  private var shelves: [RecipeLensShelf] {
    model.lensLibrary.shelves.filter { $0.lensID == lens.id }.sorted { $0.sortOrder < $1.sortOrder }
  }

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      List {
        Section("Lens") {
          TextField("Name", text: $name)
          LabeledContent("Base query") {
            ChipRow(labels: model.selectionLabels(for: (try? RecipeLensQueryCodec.decode(lens.baseQuery)) ?? RecipeBrowserQuery()))
          }
          Button("Edit base query in browser") {
            model.editLensBaseQueryButtonTapped(lens)
            dismiss()
          }
          Toggle("Show Everything else", isOn: $showsRemainder)
            .onChange(of: showsRemainder) { _, value in model.showsRemainderChanged(value, lens: lens) }
        }
        Section("Shelves") {
          ForEach(shelves) { shelf in
            HStack {
              Button(shelf.title) {
                editingShelf = shelf.id
                shelfTitleDraft = shelf.title
                isRenamingShelf = true
              }
              .buttonStyle(.plain)
              Text(model.shelfCount(shelf.id).map(String.init) ?? "Fix")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("Edit query") { model.editShelfQueryButtonTapped(shelf); dismiss() }
                .buttonStyle(.borderless)
              Button(role: .destructive) { model.deleteShelfButtonTapped(shelf) } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
            }
          }
          .onMove { source, destination in
            var ids = shelves.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            model.reorderShelvesButtonTapped(ids, lensID: lens.id)
          }
          Button("New shelf") { model.newShelfButtonTapped(lensID: lens.id); dismiss() }
        }
        Section {
          Button("Delete Lens", role: .destructive) {
            model.deleteLensButtonTapped(lens)
            dismiss()
          }
        }
        ForEach(model.lensSuggestions, id: \.facet.id) { availability in
          Section("\(availability.facet.name) suggestions") {
            ForEach(availability.values.filter {
              !isShelfSuggestion($0.category.id, facetID: availability.facet.id)
            }) { value in
              Button {
                let query = RecipeBrowserQuery(facetSelections: [
                  .init(facetID: availability.facet.id, categoryIDs: [value.category.id])
                ])
                model.addShelfButtonTapped(lensID: lens.id, title: value.category.name, query: query)
              } label: {
                HStack {
                  Text(value.category.name)
                  Spacer()
                  Text(value.matchingRecipeCount, format: .number).foregroundStyle(.secondary)
                  Image(systemName: "plus.circle")
                }
              }
            }
          }
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle("Edit Lens")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            model.renameLensButtonTapped(lens, name: name)
            dismiss()
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("Rename Shelf", isPresented: $isRenamingShelf) {
        TextField("Shelf title", text: $shelfTitleDraft)
        Button("Save") {
          guard let shelf = shelves.first(where: { $0.id == editingShelf }) else { return }
          model.renameShelfButtonTapped(shelf, title: shelfTitleDraft)
        }
        Button("Cancel", role: .cancel) {}
      }
      .onAppear {
        if name.isEmpty { name = lens.name }
        showsRemainder = lens.showsRemainder
      }
    }
  }

  private func isShelfSuggestion(_ categoryID: YesChefCore.Category.ID, facetID: Facet.ID) -> Bool {
    shelves.contains { shelf in
      guard let query = try? RecipeLensQueryCodec.decode(shelf.query) else { return false }
      return query.facetSelections.contains {
        $0.facetID == facetID && $0.categoryIDs.contains(categoryID)
      }
    }
  }
}

struct SaveRecipeLensView: View {
  let model: PowerBrowserModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  var body: some View {
    NavigationStack {
      Form { TextField("Lens name", text: $name) }
        .navigationTitle("Save as Lens")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { model.saveLensButtonTapped(name: name); dismiss() }
              .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }
  }
}

struct LensSeeAllView: View {
  let title: String
  let rows: [RecipeListRowData]
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], alignment: .leading, spacing: 12) {
        ForEach(rows) { row in
          Button { onRecipeSelected(RecipeDetailPresentation(recipeID: row.recipe.id)); dismiss() } label: {
            RecipeListRow(row: row, options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true))
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .padding()
      }
      .navigationTitle(title)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

private struct ChipRow: View {
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
