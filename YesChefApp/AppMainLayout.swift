import SwiftUI
import WebExtractorKit
import WebKit
import YesChefCore

struct AppMainLayout: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let horizontalSizeClass: UserInterfaceSizeClass?
  let recipeModel: RecipeLibraryModel
  let workbenchModel: WorkbenchLibraryModel
  let browserModel: BrowserModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel
  @Binding var selectedSection: AppSection?
  @Binding var selectedSettingsPane: SettingsPane?
  let onBrowserCapture: (WebPage) async -> Void
  var onRecipeSelected: (RecipeDetailPresentation) -> Void
  var onCookSessionRequested: (CookSessionPresentation) -> Void

  var body: some View {
    if horizontalSizeClass == .compact {
      AppCompactTabView(
        selection: $selectedSection,
        recipeModel: recipeModel,
        workbenchModel: workbenchModel,
        browserModel: browserModel,
        mealCalendarModel: mealCalendarModel,
        menuModel: menuModel,
        groceryModel: groceryModel,
        onBrowserCapture: onBrowserCapture,
        onMenuSelected: openMenuFromCalendar,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
    } else if selectedSection == .browser {
      NavigationSplitView {
        AppSidebar(selection: $selectedSection)
      } detail: {
        BrowserWorkspaceView(
          model: browserModel,
          onCapture: onBrowserCapture
        )
      }
    } else if selectedSection == .mealCalendar {
      NavigationSplitView {
        AppSidebar(selection: $selectedSection)
      } detail: {
        MealCalendarWorkspaceView(
          model: mealCalendarModel,
          onMenuSelected: openMenuFromCalendar,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      }
    } else {
      let columnSection = AppMainColumnSection(selectedSection ?? .recipes) ?? .recipes
      NavigationSplitView(columnVisibility: $columnVisibility) {
        AppSidebar(selection: $selectedSection)
      } content: {
        switch columnSection {
        case .recipes:
          RecipeListView(model: recipeModel, style: .selection)
        case .workbenches:
          WorkbenchListView(model: workbenchModel, style: .selection)
        case .groceries:
          GroceryListView(model: groceryModel, style: .selection)
        case .menus:
          MenuListView(model: menuModel, style: .selection)
        case .settings:
          SettingsView(
            model: recipeModel,
            groceryModel: groceryModel,
            selectedPane: $selectedSettingsPane
          )
        }
      } detail: {
        switch columnSection {
        case .recipes:
          RecipeDetailColumn(
            model: recipeModel,
            mealCalendarModel: mealCalendarModel,
            groceryModel: groceryModel,
            columnVisibility: $columnVisibility
          )
        case .workbenches:
          WorkbenchDetailColumn(
            model: workbenchModel,
            onRecipeSelected: onRecipeSelected,
            isFocusActive: columnVisibility == .detailOnly,
            focusButtonTapped: {
              columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
            }
          )
        case .groceries:
          GroceryDetailColumn(
            model: groceryModel,
            mealCalendarModel: mealCalendarModel
          )
        case .menus:
          MenuDetailColumn(
            model: menuModel,
            recipeModel: recipeModel,
            onRecipeSelected: onRecipeSelected,
            onCookSessionRequested: onCookSessionRequested,
            isFocusActive: columnVisibility == .detailOnly,
            focusButtonTapped: {
              columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
            }
          )
        case .settings:
          SettingsDetailPane(
            selectedPane: selectedSettingsPane,
            model: recipeModel,
            groceryModel: groceryModel
          )
        }
      }
    }
  }

  private func openMenuFromCalendar(_ menuID: CoreMenu.ID) {
    menuModel.selectMenu(menuID)
    selectedSection = .menus
  }
}

func deleteMenuMessage(_ context: MenuDeletionContext) -> String {
  var details: [String] = []
  if context.itemCount > 0 {
    details.append(context.itemCount == 1 ? "1 dish" : "\(context.itemCount) dishes")
  }
  if context.placementCount > 0 {
    details.append(
      context.placementCount == 1 ? "1 calendar placement" : "\(context.placementCount) calendar placements"
    )
  }
  guard !details.isEmpty else {
    return "Delete \(context.menuTitle)?"
  }
  return "Delete \(context.menuTitle) and its \(details.joined(separator: " and "))?"
}

func deleteWorkbenchMessage(_ context: WorkbenchDeletionContext) -> String {
  guard context.candidateCount > 0 else {
    return "Delete \(context.title)?"
  }
  let candidateText = context.candidateCount == 1 ? "1 candidate" : "\(context.candidateCount) candidates"
  return "Delete \(context.title) and its \(candidateText)?"
}

private enum AppMainColumnSection {
  case recipes
  case workbenches
  case groceries
  case menus
  case settings

  init?(_ section: AppSection) {
    switch section {
    case .recipes:
      self = .recipes
    case .workbenches:
      self = .workbenches
    case .groceries:
      self = .groceries
    case .menus:
      self = .menus
    case .settings:
      self = .settings
    case .browser, .mealCalendar:
      return nil
    }
  }
}

private struct AppCompactTabView: View {
  @Binding var selection: AppSection?
  let recipeModel: RecipeLibraryModel
  let workbenchModel: WorkbenchLibraryModel
  let browserModel: BrowserModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel
  let onBrowserCapture: (WebPage) async -> Void
  let onMenuSelected: (CoreMenu.ID) -> Void
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  let onCookSessionRequested: (CookSessionPresentation) -> Void

  var body: some View {
    TabView(selection: $selection) {
      RecipesStack(
        model: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        onRecipeSelected: onRecipeSelected
      )
        .tabItem { AppSection.recipes.label }
        .tag(AppSection.recipes as AppSection?)
      WorkbenchesStack(model: workbenchModel, onRecipeSelected: onRecipeSelected)
        .tabItem { AppSection.workbenches.label }
        .tag(AppSection.workbenches as AppSection?)
      BrowserStack(
        model: browserModel,
        onCapture: onBrowserCapture
      )
        .tabItem { AppSection.browser.label }
        .tag(AppSection.browser as AppSection?)
      MealCalendarStack(
        model: mealCalendarModel,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
        .tabItem { AppSection.mealCalendar.label }
        .tag(AppSection.mealCalendar as AppSection?)
      GroceriesStack(
        model: groceryModel,
        mealCalendarModel: mealCalendarModel
      )
        .tabItem { AppSection.groceries.label }
        .tag(AppSection.groceries as AppSection?)
      MenusStack(
        model: menuModel,
        recipeModel: recipeModel,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
        .tabItem { AppSection.menus.label }
        .tag(AppSection.menus as AppSection?)
      SettingsStack(model: recipeModel, groceryModel: groceryModel)
        .tabItem { AppSection.settings.label }
        .tag(AppSection.settings as AppSection?)
    }
  }
}

private struct AppSidebar: View {
  @Binding var selection: AppSection?

  var body: some View {
    List(AppSection.allCases, selection: $selection) { section in
      section.label
        .tag(section)
    }
    .navigationTitle("Yes Chef")
  }
}

private struct RecipesStack: View {
  let model: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    NavigationStack {
      RecipeListView(model: model, style: .navigation)
        .navigationDestination(for: Recipe.ID.self) { recipeID in
          RecipeDetailView(
            recipeID: recipeID,
            libraryModel: model,
            mealCalendarModel: mealCalendarModel,
            groceryModel: groceryModel,
            onRecipeSelected: onRecipeSelected
          )
            .id(recipeID)
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
