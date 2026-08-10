import SwiftUI
import WebExtractorKit
import WebKit
import YesChefCore

struct AppMainLayout: View {
  @AppStorage("app-shell-tab-customization") private var customization: TabViewCustomization

  // Kept as an input so AppContainer retains its existing ownership shape. The per-tab split views
  // adapt automatically as their available width changes.
  let horizontalSizeClass: UserInterfaceSizeClass?
  let recipeModel: RecipeLibraryModel
  let powerBrowserModel: PowerBrowserModel
  let workbenchModel: WorkbenchLibraryModel
  let browserModel: BrowserModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel
  let createRecipeModel: CreateRecipeModel
  @Binding var selectedSection: AppSection?
  @Binding var selectedSettingsPane: SettingsPane?
  let onBrowserCapture: (WebPage) async -> Void
  var onRecipeSelected: (RecipeDetailPresentation) -> Void
  var onCookSessionRequested: (CookSessionPresentation) -> Void
  var onRecipeCreated: (Recipe.ID) -> Void

  var body: some View {
    TabView(selection: $selectedSection) {
      Tab(
        AppSection.recipes.title,
        systemImage: AppSection.recipes.systemImage,
        value: AppSection.recipes
      ) {
        RecipesTab(
          model: recipeModel,
          mealCalendarModel: mealCalendarModel,
          groceryModel: groceryModel
        )
      }

      Tab(
        AppSection.powerBrowser.title,
        systemImage: AppSection.powerBrowser.systemImage,
        value: AppSection.powerBrowser
      ) {
        PowerBrowserView(model: powerBrowserModel, onRecipeSelected: onRecipeSelected)
      }
      .defaultVisibility(.hidden, for: .tabBar)

      Tab(
        AppSection.menus.title,
        systemImage: AppSection.menus.systemImage,
        value: AppSection.menus
      ) {
        MenusTab(
          model: menuModel,
          recipeModel: recipeModel,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      }

      Tab(
        AppSection.mealCalendar.title,
        systemImage: AppSection.mealCalendar.systemImage,
        value: AppSection.mealCalendar
      ) {
        MealCalendarTab(
          model: mealCalendarModel,
          onMenuSelected: openMenuFromCalendar,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      }

      Tab(
        AppSection.groceries.title,
        systemImage: AppSection.groceries.systemImage,
        value: AppSection.groceries
      ) {
        GroceriesTab(
          model: groceryModel,
          mealCalendarModel: mealCalendarModel,
          usesCompactTabLayout: horizontalSizeClass == .compact
        )
      }

      Tab(
        AppSection.browser.title,
        systemImage: AppSection.browser.systemImage,
        value: AppSection.browser
      ) {
        NavigationStack {
          BrowserWorkspaceView(model: browserModel, onCapture: onBrowserCapture)
        }
      }
      .defaultVisibility(.hidden, for: .tabBar)

      Tab(
        AppSection.workbenches.title,
        systemImage: AppSection.workbenches.systemImage,
        value: AppSection.workbenches
      ) {
        WorkbenchesTab(
          model: workbenchModel,
          onRecipeSelected: onRecipeSelected,
          usesCompactTabLayout: horizontalSizeClass == .compact
        )
      }
      .defaultVisibility(.hidden, for: .tabBar)

      Tab(
        AppSection.createRecipe.title,
        systemImage: AppSection.createRecipe.systemImage,
        value: AppSection.createRecipe
      ) {
        NavigationStack {
          CreateRecipeView(model: createRecipeModel, onSaved: onRecipeCreated)
        }
      }
      .defaultVisibility(.hidden, for: .tabBar)

      Tab(
        AppSection.settings.title,
        systemImage: AppSection.settings.systemImage,
        value: AppSection.settings
      ) {
        SettingsTab(
          recipeModel: recipeModel,
          groceryModel: groceryModel,
          selectedPane: $selectedSettingsPane,
          usesCompactTabLayout: horizontalSizeClass == .compact
        )
      }
      .defaultVisibility(.hidden, for: .tabBar)
    }
    .tabViewStyle(.sidebarAdaptable)
    .tabViewCustomization($customization)
  }

  private func openMenuFromCalendar(_ menuID: CoreMenu.ID) {
    menuModel.selectMenu(menuID)
    selectedSection = .menus
  }
}

private struct RecipesTab: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let model: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      RecipeListView(model: model)
    } detail: {
      RecipeDetailColumn(
        model: model,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        columnVisibility: $columnVisibility
      )
    }
  }
}

private struct WorkbenchesTab: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let model: WorkbenchLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let usesCompactTabLayout: Bool

  var body: some View {
    if usesCompactTabLayout {
      WorkbenchListView(
        model: model,
        style: .navigation,
        onRecipeSelected: onRecipeSelected
      )
    } else {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        WorkbenchListView(model: model)
      } detail: {
        WorkbenchDetailColumn(
          model: model,
          onRecipeSelected: onRecipeSelected,
          isFocusActive: columnVisibility == .detailOnly,
          focusButtonTapped: focusButtonTapped
        )
      }
    }
  }

  private func focusButtonTapped() {
    columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
  }
}

private struct GroceriesTab: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let model: GroceryLibraryModel
  let mealCalendarModel: MealCalendarModel
  let usesCompactTabLayout: Bool

  var body: some View {
    if usesCompactTabLayout {
      GroceryDetailView(
        model: model,
        mealCalendarModel: mealCalendarModel,
        showsListPicker: true
      )
    } else {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        GroceryListView(model: model)
      } detail: {
        GroceryDetailColumn(model: model, mealCalendarModel: mealCalendarModel)
      }
    }
  }
}

private struct MenusTab: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let model: MenuLibraryModel
  let recipeModel: RecipeLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let onCookSessionRequested: (CookSessionPresentation) -> Void

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      MenuListView(model: model)
    } detail: {
      MenuDetailColumn(
        model: model,
        recipeModel: recipeModel,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested,
        isFocusActive: columnVisibility == .detailOnly,
        focusButtonTapped: focusButtonTapped
      )
    }
  }

  private func focusButtonTapped() {
    columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
  }
}

private struct MealCalendarTab: View {
  let model: MealCalendarModel
  let onMenuSelected: (CoreMenu.ID) -> Void
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let onCookSessionRequested: (CookSessionPresentation) -> Void

  // Single-column, like Browser/Create Recipe. `MealCalendarWorkspaceView` adapts to width on its
  // own (calendar + agenda rail + chat when wide, stacked when compact), so a plain NavigationStack
  // hosts its title/toolbar without a spurious empty leading column. Calendar has no list to focus,
  // so it carries no Focus button.
  var body: some View {
    NavigationStack {
      MealCalendarWorkspaceView(
        model: model,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
    }
  }
}

private struct SettingsTab: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let recipeModel: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel
  @Binding var selectedPane: SettingsPane?
  let usesCompactTabLayout: Bool

  var body: some View {
    if usesCompactTabLayout {
      // The More tab supplies the compact navigation context. Passing no pane binding keeps these
      // rows as NavigationLinks instead of changing a split-view selection with no compact push.
      SettingsView(model: recipeModel, groceryModel: groceryModel)
    } else {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SettingsView(
          model: recipeModel,
          groceryModel: groceryModel,
          selectedPane: $selectedPane
        )
      } detail: {
        SettingsDetailPane(
          selectedPane: selectedPane,
          model: recipeModel,
          groceryModel: groceryModel
        )
      }
    }
  }
}

private struct RecipeDetailColumn: View {
  let model: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  @Binding var columnVisibility: NavigationSplitViewVisibility

  var body: some View {
    if let recipe = model.selectedRecipe {
      RecipeDetailView(
        recipeID: recipe.id,
        libraryModel: model,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        isFocusActive: columnVisibility == .detailOnly,
        focusButtonTapped: focusButtonTapped,
        onRecipeSelected: { presentation in
          model.selectedRecipeID = presentation.recipeID
        }
      )
      .id(recipe.id)
    } else {
      ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
    }
  }

  private func focusButtonTapped() {
    columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
  }
}
