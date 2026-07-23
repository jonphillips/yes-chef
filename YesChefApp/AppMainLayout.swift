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
  @State private var selectedTab: AppCompactTab
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

  init(
    selection: Binding<AppSection?>,
    recipeModel: RecipeLibraryModel,
    workbenchModel: WorkbenchLibraryModel,
    browserModel: BrowserModel,
    mealCalendarModel: MealCalendarModel,
    menuModel: MenuLibraryModel,
    groceryModel: GroceryLibraryModel,
    onBrowserCapture: @escaping (WebPage) async -> Void,
    onMenuSelected: @escaping (CoreMenu.ID) -> Void,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void,
    onCookSessionRequested: @escaping (CookSessionPresentation) -> Void
  ) {
    _selection = selection
    _selectedTab = State(initialValue: AppCompactTab(section: selection.wrappedValue))
    self.recipeModel = recipeModel
    self.workbenchModel = workbenchModel
    self.browserModel = browserModel
    self.mealCalendarModel = mealCalendarModel
    self.menuModel = menuModel
    self.groceryModel = groceryModel
    self.onBrowserCapture = onBrowserCapture
    self.onMenuSelected = onMenuSelected
    self.onRecipeSelected = onRecipeSelected
    self.onCookSessionRequested = onCookSessionRequested
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab(
        AppSection.recipes.title,
        systemImage: AppSection.recipes.systemImage,
        value: .recipes
      ) {
        RecipesStack(
          model: recipeModel,
          mealCalendarModel: mealCalendarModel,
          groceryModel: groceryModel,
          onRecipeSelected: onRecipeSelected
        )
      }
      Tab(
        AppSection.menus.title,
        systemImage: AppSection.menus.systemImage,
        value: .menus
      ) {
        MenusStack(
          model: menuModel,
          recipeModel: recipeModel,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      }
      Tab(
        AppSection.mealCalendar.title,
        systemImage: AppSection.mealCalendar.systemImage,
        value: .mealCalendar
      ) {
        MealCalendarStack(
          model: mealCalendarModel,
          onMenuSelected: onMenuSelected,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      }
      Tab(
        AppSection.groceries.title,
        systemImage: AppSection.groceries.systemImage,
        value: .groceries
      ) {
        GroceriesStack(
          model: groceryModel,
          mealCalendarModel: mealCalendarModel
        )
      }
      Tab("More", systemImage: "ellipsis.circle", value: .more) {
        AppMoreStack(
          workbenchModel: workbenchModel,
          browserModel: browserModel,
          recipeModel: recipeModel,
          groceryModel: groceryModel,
          onBrowserCapture: onBrowserCapture,
          onRecipeSelected: onRecipeSelected
        )
      }
    }
    .onChange(of: selectedTab) { _, tab in
      guard let section = tab.section else { return }
      selection = section
    }
    .onChange(of: selection) { _, section in
      selectedTab = AppCompactTab(section: section)
    }
  }
}

private enum AppCompactTab: Hashable {
  case recipes
  case menus
  case mealCalendar
  case groceries
  case more

  init(section: AppSection?) {
    switch section {
    case .recipes, nil:
      self = .recipes
    case .menus:
      self = .menus
    case .mealCalendar:
      self = .mealCalendar
    case .groceries:
      self = .groceries
    case .browser, .workbenches, .settings:
      self = .more
    }
  }

  var section: AppSection? {
    switch self {
    case .recipes: .recipes
    case .menus: .menus
    case .mealCalendar: .mealCalendar
    case .groceries: .groceries
    case .more: nil
    }
  }
}

private struct AppMoreStack: View {
  let workbenchModel: WorkbenchLibraryModel
  let browserModel: BrowserModel
  let recipeModel: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel
  let onBrowserCapture: (WebPage) async -> Void
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    @Bindable var workbenchModel = workbenchModel

    NavigationStack(path: $workbenchModel.navigationPath) {
      List {
        NavigationLink {
          BrowserWorkspaceView(model: browserModel, onCapture: onBrowserCapture)
        } label: {
          AppSection.browser.label
        }
        NavigationLink {
          WorkbenchListView(model: workbenchModel, style: .navigation)
        } label: {
          AppSection.workbenches.label
        }
        NavigationLink {
          SettingsView(model: recipeModel, groceryModel: groceryModel)
        } label: {
          AppSection.settings.label
        }
      }
      .navigationTitle("More")
      .navigationDestination(for: Workbench.ID.self) { workbenchID in
        WorkbenchDetailView(workbenchID: workbenchID, onRecipeSelected: onRecipeSelected)
          .id(workbenchID)
      }
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
