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
      PowerBrowserAttributeFilters(model: model)
      PowerBrowserUsageFilters(model: model)
      PowerBrowserSourceFilters(model: model)

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

private struct PowerBrowserAttributeFilters: View {
  let model: PowerBrowserModel

  var body: some View {
    @Bindable var model = model

    Section("Attributes") {
      TextField("Total time at most (min)", text: $model.totalTimeAtMostText)
        .keyboardType(.numberPad)
        .onSubmit(model.totalTimeTextChanged)
        .onChange(of: model.totalTimeAtMostText) { _, _ in
          model.totalTimeTextChanged()
        }

      TextField("Servings at least", text: $model.servingsAtLeastText)
        .keyboardType(.decimalPad)
        .onSubmit(model.servingsTextChanged)
        .onChange(of: model.servingsAtLeastText) { _, _ in
          model.servingsTextChanged()
        }

      Picker("Rating", selection: Binding(
        get: { model.minimumRating },
        set: model.minimumRatingChanged
      )) {
        Text("Any rating").tag(Optional<Int>.none)
        ForEach(1...5, id: \.self) { rating in
          Text("\(rating) or more").tag(Optional(rating))
        }
      }

      Toggle("Has make-ahead notes", isOn: Binding(
        get: { model.requiresMakeAhead },
        set: model.requiresMakeAheadChanged
      ))
    }
  }
}

private struct PowerBrowserUsageFilters: View {
  let model: PowerBrowserModel

  var body: some View {
    Section("Usage") {
      Toggle("Never cooked", isOn: Binding(
        get: { model.requiresNeverCooked },
        set: model.requiresNeverCookedChanged
      ))
      Toggle(
        "Cooked more than \(PowerBrowserModel.frequentCookedThreshold) times",
        isOn: Binding(
          get: { model.requiresFrequentCooking },
          set: model.requiresFrequentCookingChanged
        )
      )
      Toggle("Added after", isOn: Binding(
        get: { model.filtersByAddedDate },
        set: model.addedAfterChanged
      ))
      if model.filtersByAddedDate {
        DatePicker("Date", selection: Binding(
          get: { model.addedAfterDate },
          set: { model.addedAfterDate = $0; model.addedAfterDateChanged() }
        ), displayedComponents: .date)
      }
    }
  }
}

private struct PowerBrowserSourceFilters: View {
  let model: PowerBrowserModel

  var body: some View {
    Section("Source") {
      ForEach(RecipeBrowserSourceField.allCases, id: \.self) { field in
        let options = model.sourceFilterOptions[field] ?? []
        if !options.isEmpty {
          NavigationLink {
            PowerBrowserSourceFilterPicker(model: model, field: field, options: options)
          } label: {
            LabeledContent(field.title, value: model.selectedSourceValues(for: field).summary)
          }
        }
      }
    }
  }
}

private struct PowerBrowserSourceFilterPicker: View {
  let model: PowerBrowserModel
  let field: RecipeBrowserSourceField
  let options: [String]
  @State private var searchText = ""

  private var visibleOptions: [String] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return options }
    return options.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    List {
      ForEach(visibleOptions, id: \.self) { option in
        let isSelected = model.selectedSourceValues(for: field).contains(option)
        Button {
          model.sourceValueButtonTapped(option, field: field)
        } label: {
          HStack {
            Text(option)
            Spacer()
            if isSelected {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
      }
    }
    .navigationTitle(field.title)
    .searchable(text: $searchText, prompt: "Search \(field.title.lowercased())")
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

      if !model.activeSelections.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(model.activeSelections) { selection in
              Button {
                model.removeSelectionButtonTapped(selection)
              } label: {
                Label(
                  selection.title,
                  systemImage: "xmark"
                )
              }
              .buttonStyle(.bordered)
              .accessibilityLabel("Remove \(selection.title)")
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

private extension Set where Element == String {
  var summary: String {
    guard !isEmpty else { return "All" }
    let values = sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return values.count == 1 ? values[0] : "\(values.count) selected"
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
