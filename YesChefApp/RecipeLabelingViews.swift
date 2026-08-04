import SQLiteData
import SwiftUI
import YesChefCore

struct RecipeSuggestedLabelsSheet: View {
  let model: RecipeDetailModel

  var body: some View {
    NavigationStack {
      RecipeTagEditorView(model: model)
        .navigationTitle("Edit Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { model.destination = nil }
          }
        }
    }
  }
}

struct RecipeTagEditorDestination: View {
  @State private var model: RecipeDetailModel

  init(recipeID: Recipe.ID) {
    _model = State(initialValue: RecipeDetailModel(recipeID: recipeID))
  }

  var body: some View {
    RecipeTagEditorView(model: model)
      .navigationTitle("Edit Tags")
      .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RecipeTagEditorView: View {
  let model: RecipeDetailModel
  @Fetch(CategoryListRequest(), animation: .default) private var categories: [YesChefCore.Category] = []
  @Fetch(FacetListRequest(), animation: .default) private var facets: [Facet] = []

  var body: some View {
    @Bindable var model = model
    let assignedIDs = Set(model.detail?.categories.map(\.id) ?? [])

    ScrollView {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
        alignment: .leading,
        spacing: 16
      ) {
        ForEach(groups) { group in
          RecipeTagFacetCard(
            group: group,
            availableCategories: availableCategories(for: group),
            assignedIDs: assignedIDs,
            onToggle: { category in
              Task {
                if assignedIDs.contains(category.id) {
                  _ = await model.deleteTagButtonTapped(category.id)
                } else {
                  _ = await model.addTagButtonTapped(category.id)
                }
              }
            },
            onRemove: { category in
              Task { _ = await model.deleteTagButtonTapped(category.id) }
            }
          )
        }
      }
      .padding()

      VStack(alignment: .leading, spacing: 12) {
        Text("Suggestions")
          .font(.headline)

        Button {
          model.suggestLabelsButtonTapped()
        } label: {
          Label(model.labelState.suggestions.isEmpty ? "Suggest" : "Suggest More", systemImage: "sparkles")
        }
        .disabled(model.labelState.isSuggesting)

        if model.labelState.isSuggesting {
          ProgressView("Suggesting tags")
        }
        ForEach(model.labelState.suggestions) { suggestion in
          if case let .existingCategory(category) = suggestion, assignedIDs.contains(category.id) {
            HStack {
              Text(suggestion.reviewTitle)
              Spacer()
              Label("Added", systemImage: "checkmark.circle.fill")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(suggestion.reviewTitle), Added")
          } else {
            Button {
              model.suggestedLabelTapped(suggestion)
            } label: {
              Label(
                suggestion.reviewTitle,
                systemImage: model.isSuggestedLabelAccepted(suggestion) ? "checkmark.circle.fill" : "circle"
              )
            }
            .tint(model.isSuggestedLabelAccepted(suggestion) ? .green : .accentColor)
          }
        }
        if model.hasAcceptedSuggestedLabels {
          Button("Add Selected") {
            Task { _ = await model.saveSuggestedLabelsButtonTapped() }
          }
          .disabled(model.labelState.isSuggesting)
        }
      }
      .padding()
    }
  }

  private func availableCategories(for group: RecipeTagGroup) -> [YesChefCore.Category] {
    availableGroups.first { $0.id == group.id }?.categories ?? []
  }

  private var groups: [RecipeTagGroup] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let assigned = model.detail?.categories ?? []
    let byFacetID = Dictionary(grouping: assigned, by: \.facetID)
    let facetGroups = facets.map { facet in
      RecipeTagGroup(
        facetID: facet.id,
        title: facet.name,
        categories: sorted(byFacetID[facet.id] ?? [], categoriesByID: categoriesByID)
      )
    }
    let loose = byFacetID[nil] ?? []
    return facetGroups + [
      RecipeTagGroup(
        facetID: nil,
        title: "Other Tags",
        categories: sorted(loose, categoriesByID: categoriesByID)
      )
    ]
  }

  private var availableGroups: [RecipeTagGroup] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let facetGroups = facets.map { facet in
      RecipeTagGroup(
        facetID: facet.id,
        title: facet.name,
        categories: sorted(categories.filter { $0.facetID == facet.id }, categoriesByID: categoriesByID)
      )
    }
    let loose = categories.filter { $0.facetID == nil }
    return facetGroups + [
      RecipeTagGroup(
        facetID: nil,
        title: "Other Tags",
        categories: sorted(loose, categoriesByID: categoriesByID)
      )
    ]
  }

  private func sorted(
    _ categories: [YesChefCore.Category],
    categoriesByID: [YesChefCore.Category.ID: YesChefCore.Category]
  ) -> [YesChefCore.Category] {
    categories.sorted {
      CategoryHierarchy.displayName(for: $0, categoriesByID: categoriesByID)
        .localizedStandardCompare(CategoryHierarchy.displayName(for: $1, categoriesByID: categoriesByID)) == .orderedAscending
    }
  }
}

private struct RecipeTagGroup: Identifiable {
  let facetID: Facet.ID?
  let title: String
  let categories: [YesChefCore.Category]

  var id: String { facetID?.uuidString ?? "loose" }
}

private struct RecipeTagFacetCard: View {
  let group: RecipeTagGroup
  let availableCategories: [YesChefCore.Category]
  let assignedIDs: Set<YesChefCore.Category.ID>
  let onToggle: (YesChefCore.Category) -> Void
  let onRemove: (YesChefCore.Category) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(group.title)
        .font(.headline)

      if group.categories.isEmpty {
        Text("None")
          .foregroundStyle(.secondary)
      } else {
        VerticalCategoryChips(categories: group.categories, onRemove: onRemove)
      }

      Divider()

      Menu {
        ForEach(availableCategories) { category in
          Button {
            onToggle(category)
          } label: {
            Label(
              category.name,
              systemImage: assignedIDs.contains(category.id) ? "checkmark" : "circle"
            )
          }
        }
      } label: {
        Label("Add / Change", systemImage: "plus.circle")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(.background, in: .rect(cornerRadius: 16))
  }
}

private struct VerticalCategoryChips: View {
  let categories: [YesChefCore.Category]
  let onRemove: (YesChefCore.Category) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      chips
    }
  }

  @ViewBuilder
  private var chips: some View {
    ForEach(categories) { category in
      Button {
        onRemove(category)
      } label: {
        Label(category.name, systemImage: "xmark")
          .recipeChip()
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Remove \(category.name)")
    }
  }
}
