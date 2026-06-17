import SwiftUI
import SwiftUINavigation
import UIKit
import UniformTypeIdentifiers
import YesChefCore

struct AppContainer: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var recipeModel = RecipeLibraryModel()
  @State private var selectedSection: AppSection? = .recipes

  var body: some View {
    @Bindable var recipeModel = recipeModel

    Group {
      if horizontalSizeClass == .compact {
        TabView(selection: $selectedSection) {
          RecipesStack(model: recipeModel)
            .tabItem { AppSection.recipes.label }
            .tag(AppSection.recipes as AppSection?)
          NavigationStack {
            AppPlaceholderView(section: .mealCalendar)
          }
            .tabItem { AppSection.mealCalendar.label }
            .tag(AppSection.mealCalendar as AppSection?)
          NavigationStack {
            AppPlaceholderView(section: .menus)
          }
            .tabItem { AppSection.menus.label }
            .tag(AppSection.menus as AppSection?)
        }
      } else {
        NavigationSplitView {
          List(AppSection.allCases, selection: $selectedSection) { section in
            section.label
              .tag(section)
          }
          .navigationTitle("Yes Chef")
        } content: {
          switch selectedSection ?? .recipes {
          case .recipes:
            RecipeListView(model: recipeModel, style: .selection)
          case .mealCalendar:
            AppPlaceholderView(section: .mealCalendar)
          case .menus:
            AppPlaceholderView(section: .menus)
          }
        } detail: {
          switch selectedSection ?? .recipes {
          case .recipes:
            RecipeDetailColumn(model: recipeModel)
          case .mealCalendar:
            AppPlaceholderView(section: .mealCalendar)
          case .menus:
            AppPlaceholderView(section: .menus)
          }
        }
      }
    }
    .sheet(isPresented: $recipeModel.destination.addRecipe) {
      NavigationStack {
        RecipeEditorView(model: RecipeEditorModel(recipeID: nil))
      }
    }
    .sheet(item: $recipeModel.destination.editRecipe, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        RecipeEditorView(model: RecipeEditorModel(recipeID: recipeID))
      }
    }
    .sheet(item: $recipeModel.destination.cookingMode, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        CookingModeView(model: CookingModeModel(recipeID: recipeID))
      }
    }
    .sheet(item: $recipeModel.destination.originalSnapshot, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        OriginalSnapshotView(recipe: recipeModel.recipeRows.first { $0.recipe.id == recipeID }?.recipe)
      }
    }
    .confirmationDialog(
      "Delete Recipe?",
      item: $recipeModel.destination.deleteRecipe,
      titleVisibility: .visible
    ) { recipeID in
      Button("Delete Recipe", role: .destructive) {
        recipeModel.confirmDeleteRecipeButtonTapped(recipeID: recipeID)
      }
      Button("Cancel", role: .cancel) {}
    } message: { recipeID in
      Text("Delete \(recipeModel.title(for: recipeID)) from your recipe library?")
    }
    .alert("Import Complete", item: $recipeModel.destination.importSummary) { _ in
      Button("OK") {}
    } message: { summary in
      Text(summary.message)
    }
    .alert("Something Went Wrong", isPresented: $recipeModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(recipeModel.errorMessage ?? "")
    }
  }

}

private enum AppSection: String, CaseIterable, Identifiable {
  case recipes
  case mealCalendar
  case menus

  var id: Self { self }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }

  var title: String {
    switch self {
    case .recipes: "Recipes"
    case .mealCalendar: "Meal Calendar"
    case .menus: "Menus"
    }
  }

  var systemImage: String {
    switch self {
    case .recipes: "book.closed"
    case .mealCalendar: "calendar"
    case .menus: "menucard"
    }
  }
}

private struct RecipesStack: View {
  let model: RecipeLibraryModel

  var body: some View {
    NavigationStack {
      RecipeListView(model: model, style: .navigation)
        .navigationDestination(for: Recipe.ID.self) { recipeID in
          RecipeDetailView(recipeID: recipeID, libraryModel: model)
            .id(recipeID)
        }
    }
  }
}

private struct RecipeDetailColumn: View {
  let model: RecipeLibraryModel

  var body: some View {
    if let recipe = model.selectedRecipe {
      RecipeDetailView(recipeID: recipe.id, libraryModel: model)
        .id(recipe.id)
    } else {
      ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
    }
  }
}

private struct RecipeListView: View {
  enum Style {
    case navigation
    case selection
  }

  let model: RecipeLibraryModel
  let style: Style

  var body: some View {
    @Bindable var model = model

    Group {
      switch style {
      case .navigation:
        List {
          ForEach(model.visibleRecipeRows) { row in
            NavigationLink(value: row.recipe.id) {
              RecipeListRow(row: row)
            }
            .swipeActions {
              Button {
                model.deleteButtonTapped(recipeID: row.recipe.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
              .tint(.red)
            }
          }
        }
      case .selection:
        List(selection: $model.selectedRecipeID) {
          ForEach(model.visibleRecipeRows) { row in
            RecipeListRow(row: row)
              .tag(row.recipe.id)
              .swipeActions {
                Button {
                  model.deleteButtonTapped(recipeID: row.recipe.id)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
                .tint(.red)
              }
          }
        }
      }
    }
    .navigationTitle("Recipes")
    .searchable(text: $model.searchText, prompt: "Search recipes")
    .fileImporter(
      isPresented: $model.isPresentingPaprikaImporter,
      allowedContentTypes: [.zip]
    ) { result in
      Task {
        await model.paprikaExportSelected(result)
      }
    }
    .overlay {
      if model.isImporting {
        ZStack {
          Rectangle()
            .fill(.background.opacity(0.65))
          ProgressView("Importing")
            .controlSize(.large)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.addRecipeButtonTapped()
        } label: {
          Label("Add Recipe", systemImage: "plus")
        }
        .disabled(model.isImporting)
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          model.importPaprikaExportButtonTapped()
        } label: {
          Label("Import Paprika Export", systemImage: "square.and.arrow.down")
        }
        .disabled(model.isImporting)
      }
    }
  }
}

private struct AppPlaceholderView: View {
  let section: AppSection

  var body: some View {
    ContentUnavailableView(section.title, systemImage: section.systemImage)
      .navigationTitle(section.title)
  }
}

private struct RecipeListRow: View {
  let row: RecipeListRowData

  private var recipe: Recipe { row.recipe }

  var body: some View {
    HStack(spacing: 12) {
      RecipeListThumbnail(data: row.thumbnailData)

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
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct RecipeListThumbnail: View {
  let data: Data?

  var body: some View {
    ZStack {
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 52, height: 52)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.seedSampleDataIfNeeded()
  }
  AppContainer()
}
