import SwiftUI
import SwiftUINavigation
import YesChefCore

struct RecipeLibraryView: View {
  @State private var model = RecipeLibraryModel()

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      List(selection: $model.selectedRecipeID) {
        ForEach(model.visibleRecipes) { recipe in
          RecipeListRow(recipe: recipe)
            .tag(recipe.id)
        }
      }
      .navigationTitle("Recipes")
      .searchable(text: $model.searchText, prompt: "Search recipes")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            model.addRecipeButtonTapped()
          } label: {
            Label("Add Recipe", systemImage: "plus")
          }
        }
      }
    } detail: {
      if let recipe = model.selectedRecipe {
        RecipeDetailView(recipeID: recipe.id, libraryModel: model)
          .id(recipe.id)
      } else {
        ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
      }
    }
    .sheet(isPresented: $model.destination.addRecipe) {
      NavigationStack {
        RecipeEditorView(model: RecipeEditorModel(recipeID: nil))
      }
    }
    .sheet(item: $model.destination.editRecipe, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        RecipeEditorView(model: RecipeEditorModel(recipeID: recipeID))
      }
    }
    .sheet(item: $model.destination.cookingMode, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        CookingModeView(model: CookingModeModel(recipeID: recipeID))
      }
    }
    .sheet(item: $model.destination.markCooked, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        MarkCookedView(model: MarkCookedModel(recipeID: recipeID))
      }
    }
    .sheet(item: $model.destination.originalSnapshot, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        OriginalSnapshotView(recipe: model.recipes.first { $0.id == recipeID })
      }
    }
  }
}

private struct RecipeListRow: View {
  let recipe: Recipe

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(recipe.title)
          .font(.headline)
        if recipe.favorite {
          Image(systemName: "star.fill")
            .font(.caption)
            .foregroundStyle(.yellow)
        }
      }
      HStack(spacing: 6) {
        if let subtitle = recipe.subtitle {
          Text(subtitle)
        } else if let summary = recipe.summary {
          Text(summary)
        }
        if recipe.timesCooked > 0 {
          Text("Cooked \(recipe.timesCooked)x")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.seedSampleDataIfNeeded()
  }
  RecipeLibraryView()
}
