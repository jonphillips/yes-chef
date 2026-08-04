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

    Form {
      ForEach(groups) { group in
        Section(group.title) {
          if group.categories.isEmpty {
            Text("No tags in this group.")
              .foregroundStyle(.secondary)
          }
          ForEach(group.categories) { category in
            Button(role: .destructive) {
              Task { _ = await model.deleteTagButtonTapped(category.id) }
            } label: {
              Label(category.name, systemImage: "minus.circle")
            }
          }
        }
      }

      Section {
        Menu {
          ForEach(availableGroups) { group in
            Menu(group.title) {
              ForEach(group.categories) { category in
                Button(category.name) {
                  Task { _ = await model.addTagButtonTapped(category.id) }
                }
              }
            }
          }
        } label: {
          Label("Add Tag", systemImage: "plus.circle")
        }
      }

      Section("Suggestions") {
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
        if model.hasAcceptedSuggestedLabels {
          Button("Add Selected") {
            Task { _ = await model.saveSuggestedLabelsButtonTapped() }
          }
          .disabled(model.labelState.isSuggesting)
        }
      }
    }
  }

  private var groups: [RecipeTagGroup] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let assigned = model.detail?.categories ?? []
    let byFacetID = Dictionary(grouping: assigned, by: \.facetID)
    let facetGroups = facets.compactMap { facet -> RecipeTagGroup? in
      guard let categories = byFacetID[facet.id] else { return nil }
      return RecipeTagGroup(title: facet.name, categories: sorted(categories, categoriesByID: categoriesByID))
    }
    let loose = byFacetID[nil] ?? []
    return facetGroups + (loose.isEmpty ? [] : [RecipeTagGroup(title: "Other Tags", categories: sorted(loose, categoriesByID: categoriesByID))])
  }

  private var availableGroups: [RecipeTagGroup] {
    let assignedIDs = Set(model.detail?.categories.map(\.id) ?? [])
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let available = categories.filter { !assignedIDs.contains($0.id) }
    let facetGroups = facets.compactMap { facet -> RecipeTagGroup? in
      let values = available.filter { $0.facetID == facet.id }
      guard !values.isEmpty else { return nil }
      return RecipeTagGroup(title: facet.name, categories: sorted(values, categoriesByID: categoriesByID))
    }
    let loose = available.filter { $0.facetID == nil }
    return facetGroups + (loose.isEmpty ? [] : [RecipeTagGroup(title: "Other Tags", categories: sorted(loose, categoriesByID: categoriesByID))])
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
  let title: String
  let categories: [YesChefCore.Category]

  var id: String { title }
}
