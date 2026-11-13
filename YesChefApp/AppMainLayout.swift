import CloudSyncKit
import SwiftUI
import WebExtractorKit
import WebKit
import YesChefCore

struct AppMainLayout: View {
  @AppStorage("app-shell-tab-customization") private var customization: TabViewCustomization

  let horizontalSizeClass: UserInterfaceSizeClass?
  let recipeModel: RecipeLibraryModel
  let powerBrowserModel: PowerBrowserModel
  let workbenchModel: WorkbenchLibraryModel
  let browserModel: BrowserModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel
  let cookbookLibraryModel: CookbookLibraryModel
  let cookbookCopyModel: CookbookCopyModel
  let createRecipeModel: CreateRecipeModel
  let chatAccessInboxModel: ChatAccessInboxModel
  let chatAccessExportModel: ChatAccessExportModel
  let automaticBackupModel: AutomaticBackupModel
  @Binding var selectedSection: AppSection?
  @Binding var selectedSettingsPane: SettingsPane?
  let onBrowserCapture: (WebPage) async -> Void
  var onRecipeSelected: (RecipeDetailPresentation) -> Void
  var onCookSessionRequested: (CookSessionPresentation) -> Void
  var onTodayPrepRequested: (TodayPrepPresentation) -> Void
  var onRecipeCreated: (Recipe.ID) -> Void

  var body: some View {
    TabView(selection: $selectedSection) {
      if UIDevice.current.userInterfaceIdiom == .phone {
        recipesTab
        groceriesTab
        mealCalendarTab
        menusTab
        fromChatTab
        createRecipeTab
        powerBrowserTab
        if !cookbookLibraryModel.contexts.isEmpty { cookbooksTab }
        browserTab
        workbenchesTab
        settingsTab
      } else {
        recipesTab
        powerBrowserTab
        if !cookbookLibraryModel.contexts.isEmpty { cookbooksTab }
        menusTab
        mealCalendarTab
        groceriesTab
        browserTab
        workbenchesTab
        fromChatTab
        createRecipeTab
        settingsTab
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .tabViewCustomization($customization)
  }

  private var recipesTab: some TabContent<AppSection?> {
    Tab(value: AppSection.recipes) {
      RecipesTab(
        model: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        onArchivedRecipesRequested: {
          selectedSection = .settings
          selectedSettingsPane = .archivedRecipes
        }
      )
    } label: {
      Label(AppSection.recipes.title, symbol: AppSection.recipes.symbol)
    }
  }

  private var groceriesTab: some TabContent<AppSection?> {
    Tab(value: AppSection.groceries) {
      GroceriesTab(
        model: groceryModel,
        mealCalendarModel: mealCalendarModel,
        usesCompactTabLayout: horizontalSizeClass == .compact
      )
    } label: {
      Label(AppSection.groceries.title, symbol: AppSection.groceries.symbol)
    }
  }

  private var mealCalendarTab: some TabContent<AppSection?> {
    Tab(value: AppSection.mealCalendar) {
      MealCalendarTab(
        model: mealCalendarModel,
        onMenuSelected: openMenuFromCalendar,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
    } label: {
      Label(AppSection.mealCalendar.title, symbol: AppSection.mealCalendar.symbol)
    }
  }

  private var menusTab: some TabContent<AppSection?> {
    Tab(value: AppSection.menus) {
      MenusTab(
        model: menuModel,
        recipeModel: recipeModel,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested,
        onTodayPrepRequested: onTodayPrepRequested
      )
    } label: {
      Label(AppSection.menus.title, symbol: AppSection.menus.symbol)
    }
  }

  private var createRecipeTab: some TabContent<AppSection?> {
    Tab(value: AppSection.createRecipe) {
      NavigationStack {
        CreateRecipeView(
          model: createRecipeModel,
          onSaved: onRecipeCreated
        )
      }
    } label: {
      Label(AppSection.createRecipe.title, symbol: AppSection.createRecipe.symbol)
    }
    .defaultVisibility(.hidden, for: .tabBar)
  }

  private var fromChatTab: some TabContent<AppSection?> {
    Tab(value: AppSection.fromChat) {
      NavigationStack {
        FromChatView(model: chatAccessInboxModel)
      }
    } label: {
      Label(AppSection.fromChat.title, symbol: AppSection.fromChat.symbol)
    }
    .badge(chatAccessInboxModel.inboxCount)
    .defaultVisibility(.hidden, for: .tabBar)
  }

  private var powerBrowserTab: some TabContent<AppSection?> {
    Tab(value: AppSection.powerBrowser) {
      if selectedSection == .powerBrowser {
        PowerBrowserView(model: powerBrowserModel, onRecipeSelected: onRecipeSelected)
      }
    } label: {
      Label(AppSection.powerBrowser.title, symbol: AppSection.powerBrowser.symbol)
    }
    .defaultVisibility(.hidden, for: .tabBar)
  }

  private var cookbooksTab: some TabContent<AppSection?> {
    Tab(value: AppSection.cookbooks) {
      FamilyCookbooksView(
        model: cookbookLibraryModel,
        copyModel: cookbookCopyModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        onRecipeSelected: onRecipeSelected
      )
    } label: {
      Label(AppSection.cookbooks.title, symbol: AppSection.cookbooks.symbol)
    }
  }

  private var browserTab: some TabContent<AppSection?> {
    Tab(value: AppSection.browser) {
      NavigationStack {
        BrowserWorkspaceView(model: browserModel, onCapture: onBrowserCapture)
      }
    } label: {
      Label(AppSection.browser.title, symbol: AppSection.browser.symbol)
    }
    .defaultVisibility(.hidden, for: .tabBar)
  }

  private var workbenchesTab: some TabContent<AppSection?> {
    Tab(value: AppSection.workbenches) {
      WorkbenchesTab(
        model: workbenchModel,
        onRecipeSelected: onRecipeSelected,
        usesCompactTabLayout: horizontalSizeClass == .compact
      )
    } label: {
      Label(AppSection.workbenches.title, symbol: AppSection.workbenches.symbol)
    }
    .defaultVisibility(.hidden, for: .tabBar)
  }

  private var settingsTab: some TabContent<AppSection?> {
    Tab(value: AppSection.settings) {
      SettingsTab(
        recipeModel: recipeModel,
        groceryModel: groceryModel,
        automaticBackupModel: automaticBackupModel,
        chatAccessExportModel: chatAccessExportModel,
        chatAccessInboxModel: chatAccessInboxModel,
        selectedPane: $selectedSettingsPane,
        usesCompactTabLayout: horizontalSizeClass == .compact
      )
    } label: {
      Label(AppSection.settings.title, symbol: AppSection.settings.symbol)
    }
    .defaultVisibility(.hidden, for: .tabBar)
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
  let onArchivedRecipesRequested: () -> Void

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      RecipeListView(
        model: model,
        onArchivedRecipesRequested: onArchivedRecipesRequested
      )
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
      NavigationStack {
        GroceryDetailView(
          model: model,
          mealCalendarModel: mealCalendarModel,
          showsListPicker: true
        )
      }
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
  let onTodayPrepRequested: (TodayPrepPresentation) -> Void

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      MenuListView(model: model)
    } detail: {
      MenuDetailColumn(
        model: model,
        recipeModel: recipeModel,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested,
        onTodayPrepRequested: onTodayPrepRequested,
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
  let automaticBackupModel: AutomaticBackupModel
  let chatAccessExportModel: ChatAccessExportModel
  let chatAccessInboxModel: ChatAccessInboxModel
  @Binding var selectedPane: SettingsPane?
  let usesCompactTabLayout: Bool

  var body: some View {
    if usesCompactTabLayout {
      // The More tab supplies the compact navigation context. Passing no pane binding keeps these
      // rows as NavigationLinks instead of changing a split-view selection with no compact push.
      SettingsView(model: recipeModel, groceryModel: groceryModel, automaticBackupModel: automaticBackupModel, chatAccessExportModel: chatAccessExportModel, chatAccessInboxModel: chatAccessInboxModel)
    } else {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SettingsView(
          model: recipeModel,
          groceryModel: groceryModel,
          automaticBackupModel: automaticBackupModel,
          chatAccessExportModel: chatAccessExportModel,
          chatAccessInboxModel: chatAccessInboxModel,
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
      ContentUnavailableView {
        Label("Select a Recipe", symbol: .recipe)
      }
    }
  }

  private func focusButtonTapped() {
    columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
  }
}
