import SwiftUI
import YesChefCore

struct PowerBrowserView: View {
  let model: PowerBrowserModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    let result = model.result

    NavigationSplitView {
      PowerBrowserFacetsView(model: model, result: result)
    } detail: {
      PowerBrowserResultsView(model: model, result: result, onRecipeSelected: onRecipeSelected)
    }
    // Facets and results are peer work areas, so this intentionally stays balanced rather than
    // adopting a focus toggle intended for master/detail surfaces.
    .navigationSplitViewStyle(.balanced)
    .onChange(of: result.availableFacets.map(\.id), initial: true) { _, facetIDs in
      model.availableFacetsAppeared(facetIDs)
    }
  }
}

private struct PowerBrowserFacetsView: View {
  let model: PowerBrowserModel
  let result: RecipeBrowserResult

  var body: some View {
    @Bindable var model = model

    List {
      if result.availableFacets.isEmpty {
        ContentUnavailableView(
          "No Facets Available",
          systemImage: "square.grid.2x2",
          description: Text("As recipes are classified, useful ways to narrow this result will appear here.")
        )
      } else {
        ForEach(result.availableFacets) { availability in
          Section {
            DisclosureGroup(
              isExpanded: $model.expandedFacetIDs[contains: availability.facet.id]
            ) {
              ForEach(availability.values) { value in
                PowerBrowserFacetValueRow(
                  value: value,
                  action: { model.facetValueButtonTapped(value.category, in: availability.facet) }
                )
              }
            } label: {
              Label(availability.facet.name, systemImage: "square.grid.2x2")
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .toolbar(removing: .sidebarToggle)
  }
}

private struct PowerBrowserFacetValueRow: View {
  let value: RecipeBrowserResult.ValueAvailability
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(value.category.name)
          .foregroundStyle(.primary)

        Spacer()

        Text(value.matchingRecipeCount, format: .number)
          .font(.caption)
          .foregroundStyle(.secondary)

        if value.isSelected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        } else {
          Image(systemName: "circle")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(value.category.name)
    .accessibilityValue("\(value.matchingRecipeCount) recipes\(value.isSelected ? ", selected" : "")")
    .accessibilityHint(value.isSelected ? "Removes this selection" : "Adds this selection")
  }
}

private struct PowerBrowserResultsView: View {
  let model: PowerBrowserModel
  let result: RecipeBrowserResult
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    @Bindable var model = model
    let rows = model.recipeRows(for: result)

    List {
      ForEach(rows) { row in
        Button {
          onRecipeSelected(RecipeDetailPresentation(recipeID: row.recipe.id))
        } label: {
          RecipeListRow(
            row: row,
            options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true)
          )
        }
        .buttonStyle(.plain)
      }
    }
    .overlay {
      if rows.isEmpty {
        ContentUnavailableView(
          "No Matching Recipes",
          systemImage: "magnifyingglass",
          description: Text("Try removing a selection or changing your search.")
        )
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      PowerBrowserSelectionBar(model: model, matchingRecipeCount: result.matchingRecipeIDs.count)
    }
    .navigationTitle("Results")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $model.searchText, prompt: "Search recipes")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Sort", selection: $model.query.sort) {
            ForEach(RecipeBrowserSort.allCases, id: \.self) { sort in
              Text(sort.title).tag(sort)
            }
          }
        } label: {
          Label("Sort", systemImage: "arrow.up.arrow.down")
        }
      }
    }
  }
}

private struct PowerBrowserSelectionBar: View {
  let model: PowerBrowserModel
  let matchingRecipeCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(matchingRecipeCount) \(matchingRecipeCount == 1 ? "recipe" : "recipes")")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)

        Spacer()

        Button("Clear", action: model.clearButtonTapped)
          .disabled(!model.hasActiveSelections)
      }

      if !model.activeFacetSelections.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(model.activeFacetSelections) { selection in
              Button {
                model.removeSelectionButtonTapped(
                  categoryID: selection.category.id,
                  in: selection.facet.id
                )
              } label: {
                Label(
                  model.selectionTitle(for: selection.category.id, in: selection.facet),
                  systemImage: "xmark"
                )
              }
              .buttonStyle(.bordered)
              .accessibilityLabel("Remove \(model.selectionTitle(for: selection.category.id, in: selection.facet))")
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }
    .padding()
    .background(.bar)
  }
}

private extension RecipeBrowserSort {
  var title: String {
    switch self {
    case .title: "Title"
    case .newest: "Newest"
    case .recentlyModified: "Recently Modified"
    case .cookTime: "Cook Time"
    case .recentlyCooked: "Recently Cooked"
    }
  }
}

private extension Set {
  subscript(contains element: Element) -> Bool {
    get { contains(element) }
    set {
      if newValue {
        insert(element)
      } else {
        remove(element)
      }
    }
  }
}
