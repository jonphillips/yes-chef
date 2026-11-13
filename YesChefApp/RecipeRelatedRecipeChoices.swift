import SwiftUI
import YesChefCore

struct RecipeRelatedRecipeChoices: View {
  let relatedRecipes: [Recipe]
  let model: RecipeDetailModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  var showsSectionTitle = true
  var isReadOnly = false

  @State private var unlinkingRecipe: Recipe?

  var body: some View {
    @Bindable var model = model

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        if showsSectionTitle {
          Text("Related Recipes")
            .font(.title3.bold())
        }
        Spacer()
        if !isReadOnly {
          Button("Link Recipe", systemImage: "link") {
            model.linkRelatedRecipeButtonTapped()
          }
          .buttonStyle(.bordered)
          .disabled(model.isLoadingRelatedRecipePicker)
        }
      }

      if relatedRecipes.isEmpty {
        Text("Link recipes you want to keep together.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        ForEach(relatedRecipes) { recipe in
          relatedRecipeRow(recipe, isReadOnly: isReadOnly)
        }
      }
    }
    .sheet(isPresented: isReadOnly ? .constant(false) : $model.destination.relatedRecipePicker) {
      RelatedRecipePicker(
        recipeRows: model.relatedRecipePickerRows,
        excludedRecipeIDs: Set(relatedRecipes.map(\.id)).union([model.recipeID]),
        link: { model.linkRelatedRecipe($0.id) }
      )
    }
    .confirmationDialog(
      "Unlink this recipe?",
      isPresented: Binding(
        get: { unlinkingRecipe != nil },
        set: { if !$0 { unlinkingRecipe = nil } }
      ),
      titleVisibility: .visible,
      presenting: unlinkingRecipe
    ) { recipe in
      Button("Unlink", role: .destructive) {
        model.unlinkRelatedRecipe(recipe.id)
      }
      Button("Cancel", role: .cancel) {}
    } message: { recipe in
      Text("\(recipe.title) will no longer appear as a related recipe.")
    }
  }

  private func relatedRecipeRow(_ recipe: Recipe, isReadOnly: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Button {
        onRecipeSelected(RecipeDetailPresentation(recipeID: recipe.id, scope: model.scope))
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(recipe.title)
            .font(.headline)
          if let subtitle = recipe.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(recipe.title)
    }
    .contextMenu {
      if !isReadOnly {
        Button("Unlink", role: .destructive) {
          unlinkingRecipe = recipe
        }
      }
    }
    .swipeActions(edge: .trailing) {
      if !isReadOnly {
        Button("Unlink", systemImage: "link.slash", role: .destructive) {
          unlinkingRecipe = recipe
        }
      }
    }
    .padding(.vertical, 6)
  }
}

struct RelatedRecipePicker: View {
  @Environment(\.dismiss) private var dismiss

  let recipeRows: [RecipeRelatedRecipePickerRow]
  let excludedRecipeIDs: Set<Recipe.ID>
  let link: (RecipeRelatedRecipePickerRow) -> Void

  @State private var searchText = ""

  private var availableRecipeRows: [RecipeRelatedRecipePickerRow] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return recipeRows
      .filter { !excludedRecipeIDs.contains($0.id) }
      .filter { row in
        query.isEmpty || RecipeSearchMatcher.matches(
          query: query,
          in: [row.title, row.subtitle, row.summary]
            .compactMap(\.self) + row.categoryNames
        )
      }
      .sorted { lhs, rhs in
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
      }
  }

  var body: some View {
    NavigationStack {
      List {
        if availableRecipeRows.isEmpty {
          ContentUnavailableView.search(text: searchText)
        } else {
          ForEach(availableRecipeRows) { row in
            Button {
              link(row)
              dismiss()
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                  .font(.headline)
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                  Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else if !row.categoryNames.isEmpty {
                  Text(row.categoryNames.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .foregroundStyle(.primary)
          }
        }
      }
      .searchable(text: $searchText, prompt: "Find recipes")
      .navigationTitle("Link Recipe")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}
