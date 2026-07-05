import SwiftUI
import SwiftUINavigation
import UIKit
import UniformTypeIdentifiers
import WebExtractorKit
import WebKit
import YesChefCore

struct AppContainer: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var toastCenter: AppToastCenter
  @State private var recipeModel = RecipeLibraryModel()
  @State private var browserModel = BrowserModel()
  @State private var mealCalendarModel: MealCalendarModel
  @State private var menuModel = MenuLibraryModel()
  @State private var groceryModel: GroceryLibraryModel
  @State private var selectedSection: AppSection? = .recipes
  @State private var selectedSettingsPane: SettingsPane? = .categories
  @State private var presentedRecipe: RecipeDetailPresentation?
  @State private var presentedCookSession: CookSessionPresentation?

  init() {
    let toastCenter = AppToastCenter()
    _toastCenter = State(wrappedValue: toastCenter)
    _mealCalendarModel = State(wrappedValue: MealCalendarModel(toastCenter: toastCenter))
    _groceryModel = State(wrappedValue: GroceryLibraryModel(toastCenter: toastCenter))
  }

  var body: some View {
    @Bindable var recipeModel = recipeModel
    @Bindable var mealCalendarModel = mealCalendarModel
    @Bindable var menuModel = menuModel
    @Bindable var groceryModel = groceryModel

    AppMainLayout(
      horizontalSizeClass: horizontalSizeClass,
      recipeModel: recipeModel,
      browserModel: browserModel,
      mealCalendarModel: mealCalendarModel,
      menuModel: menuModel,
      groceryModel: groceryModel,
      selectedSection: $selectedSection,
      selectedSettingsPane: $selectedSettingsPane,
      onBrowserCapture: browserCaptureButtonTapped,
      onRecipeSelected: { presentation in
        presentedRecipe = presentation
      },
      onCookSessionRequested: { presentation in
        presentedCookSession = presentation
      }
    )
    .fullScreenCover(item: $presentedRecipe) { presentation in
      RecipeFullScreenCover(
        presentation: presentation,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        toastCenter: toastCenter
      )
    }
    .fullScreenCover(item: $presentedCookSession) { presentation in
      CookSessionFullScreenCover(
        presentation: presentation,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        toastCenter: toastCenter
      )
    }
    .mealCalendarItemEditorDestination(
      mealCalendarModel: mealCalendarModel,
      isPresentationEnabled: presentedRecipe == nil && presentedCookSession == nil
    )
    .sheet(isPresented: $menuModel.destination.addMenu) {
      NavigationStack {
        MenuEditorView(model: menuModel)
      }
    }
    .sheet(item: $menuModel.destination.addItem, id: \.self) { context in
      NavigationStack {
        MenuItemEditorView(model: menuModel, context: context)
      }
    }
    .sheet(item: $menuModel.destination.placeMenu, id: \.self) { context in
      NavigationStack {
        MenuPlacementEditorView(model: menuModel, context: context)
      }
    }
    .groceryDestinations(
      groceryModel: groceryModel,
      mealCalendarModel: mealCalendarModel,
      isPresentationEnabled: presentedRecipe == nil && presentedCookSession == nil
    )
    .recipeDetailDestinations(
      recipeModel: recipeModel,
      isPresentationEnabled: presentedRecipe == nil && presentedCookSession == nil
    )
    .sheet(isPresented: $recipeModel.destination.addRecipe) {
      NavigationStack {
        RecipeEditorView(recipeID: nil)
      }
    }
    .sheet(isPresented: $recipeModel.destination.captureRecipe) {
      NavigationStack {
        RecipeCaptureView(libraryModel: recipeModel, model: recipeModel.captureModel)
      }
    }
    .sheet(isPresented: $recipeModel.destination.importReview) {
      NavigationStack {
        PaprikaImportReviewView(libraryModel: recipeModel, model: recipeModel.importModel)
      }
    }
    .sheet(isPresented: $recipeModel.destination.filterRecipes) {
      NavigationStack {
        RecipeFilterView(model: recipeModel)
      }
    }
    .confirmationDialog(
      "Remove Meal Plan Item?",
      item: $mealCalendarModel.destination.deleteItem,
      titleVisibility: .visible
    ) { itemID in
      Button("Remove", role: .destructive) {
        mealCalendarModel.confirmDeleteItemButtonTapped(itemID: itemID)
      }
      Button("Cancel", role: .cancel) {}
    } message: { itemID in
      Text("Remove \(mealCalendarModel.title(for: itemID)) from your meal calendar?")
    }
    .confirmationDialog(
      "Remove Menu from Calendar?",
      item: $menuModel.destination.deletePlacement,
      titleVisibility: .visible
    ) { context in
      Button("Remove from Calendar", role: .destructive) {
        menuModel.confirmDeletePlacementButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { context in
      Text("Remove \(context.menuTitle) from \(context.startDate.formatted(.dateTime.month(.wide).day().year()))?")
    }
    .alert("Import Complete", item: $recipeModel.destination.importSummary) { summary in
      if summary.canUndo {
        Button("Undo Import", role: .destructive) {
          Task {
            await recipeModel.undoPaprikaImportButtonTapped(summary)
          }
        }
      }
      Button("OK") {}
    } message: { summary in
      Text(summary.message)
    }
    .alert("Backup Supplement Complete", item: $recipeModel.destination.backupSupplementSummary) { _ in
      Button("OK") {}
    } message: { summary in
      Text(summary.message)
    }
    .alert("Capture Complete", item: $recipeModel.destination.captureSummary) { _ in
      Button("OK") {}
    } message: { summary in
      Text(summary.message)
    }
    .alert("Something Went Wrong", isPresented: $recipeModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(recipeModel.errorMessage ?? "")
    }
    .alert("Meal Calendar Error", isPresented: $mealCalendarModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(mealCalendarModel.errorMessage ?? "")
    }
    .alert("Menus Error", isPresented: $menuModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(menuModel.errorMessage ?? "")
    }
    .alert("Groceries Error", isPresented: $groceryModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(groceryModel.errorMessage ?? "")
    }
    .fileImporter(
      isPresented: $recipeModel.isPresentingPaprikaImporter,
      allowedContentTypes: [.zip]
    ) { result in
      Task {
        await recipeModel.paprikaExportSelected(result)
      }
    }
    .fileImporter(
      isPresented: $recipeModel.isPresentingPaprikaBackupSupplementer,
      allowedContentTypes: [.paprikaRecipes]
    ) { result in
      Task {
        await recipeModel.paprikaBackupSelected(result)
      }
    }
    .overlay {
      if recipeModel.isImporting {
        ZStack {
          Rectangle()
            .fill(.background.opacity(0.65))
          ProgressView(recipeModel.importActivityTitle)
            .controlSize(.large)
        }
      }
    }
    .overlay(alignment: .top) {
      AppToastOverlay(toastCenter: toastCenter)
        .ignoresSafeArea(.keyboard)
    }
    .sensoryFeedback(.success, trigger: toastCenter.feedbackTrigger)
    .externalDatabaseChangeReload(
      recipeModel: recipeModel,
      browserModel: browserModel,
      mealCalendarModel: mealCalendarModel,
      menuModel: menuModel,
      groceryModel: groceryModel
    )
  }

  @MainActor private func browserCaptureButtonTapped(page: WebPage) async {
    let outcome = await browserModel.captureButtonTapped(page: page) { html, url in
      await recipeModel.captureModel.ingestBrowserCapture(html: html, sourceURL: url)
    }
    if outcome == .extracted {
      recipeModel.destination = .captureRecipe
    }
  }
}

private struct RecipeFullScreenCover: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: RecipeDetailPresentation
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let toastCenter: AppToastCenter

  var body: some View {
    NavigationStack {
      RecipeDetailView(
        recipeID: presentation.recipeID,
        scaleContext: presentation.scaleContext,
        libraryModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
    .overlay(alignment: .top) {
      AppToastOverlay(toastCenter: toastCenter)
        .ignoresSafeArea(.keyboard)
    }
    .sensoryFeedback(.success, trigger: toastCenter.feedbackTrigger)
    .mealCalendarItemEditorDestination(mealCalendarModel: mealCalendarModel)
    .groceryDestinations(
      groceryModel: groceryModel,
      mealCalendarModel: mealCalendarModel
    )
    .recipeDetailDestinations(recipeModel: recipeModel)
  }
}

private struct CookSessionFullScreenCover: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: CookSessionPresentation
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let toastCenter: AppToastCenter

  var body: some View {
    NavigationStack {
      CookSessionView(
        presentation: presentation,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
    }
    .overlay(alignment: .top) {
      AppToastOverlay(toastCenter: toastCenter)
        .ignoresSafeArea(.keyboard)
    }
    .sensoryFeedback(.success, trigger: toastCenter.feedbackTrigger)
    .mealCalendarItemEditorDestination(mealCalendarModel: mealCalendarModel)
    .groceryDestinations(
      groceryModel: groceryModel,
      mealCalendarModel: mealCalendarModel
    )
    .recipeDetailDestinations(recipeModel: recipeModel)
  }
}

private struct AppMainLayout: View {
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  let horizontalSizeClass: UserInterfaceSizeClass?
  let recipeModel: RecipeLibraryModel
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
            onCookSessionRequested: onCookSessionRequested
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

private enum AppMainColumnSection {
  case recipes
  case groceries
  case menus
  case settings

  init?(_ section: AppSection) {
    switch section {
    case .recipes:
      self = .recipes
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
        groceryModel: groceryModel
      )
        .tabItem { AppSection.recipes.label }
        .tag(AppSection.recipes as AppSection?)
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

  var body: some View {
    NavigationStack {
      RecipeListView(model: model, style: .navigation)
        .navigationDestination(for: Recipe.ID.self) { recipeID in
          RecipeDetailView(
            recipeID: recipeID,
            libraryModel: model,
            mealCalendarModel: mealCalendarModel,
            groceryModel: groceryModel
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
        focusButtonTapped: focusButtonTapped
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

private struct RecipeListView: View {
  enum Style {
    case navigation
    case selection
  }

  @AppStorage("RecipeList.rowDensity") private var rowDensityRawValue = RecipeListRowDensity.rich.rawValue
  @AppStorage("RecipeList.showsSourceMetadata") private var showsSourceMetadata = true
  @AppStorage("RecipeList.showsCategoryMetadata") private var showsCategoryMetadata = true
  @AppStorage("RecipeList.savedPresets") private var savedPresetsData = Data()

  @State private var isSavingListPreset = false
  @State private var isManagingListPresets = false

  let model: RecipeLibraryModel
  let style: Style

  var body: some View {
    @Bindable var model = model
    let viewOptions = RecipeListViewOptions(
      density: RecipeListRowDensity(rawValue: rowDensityRawValue) ?? .rich,
      showsSourceMetadata: showsSourceMetadata,
      showsCategoryMetadata: showsCategoryMetadata
    )
    let savedPresets = savedListPresets
    let activePresetID = activeListPresetID

    Group {
      switch style {
      case .navigation:
        List {
          ForEach(model.visibleRecipeRows) { row in
            NavigationLink(value: row.recipe.id) {
              RecipeListRow(row: row, options: viewOptions)
            }
            .swipeActions {
              Button {
                model.deleteButtonTapped(recipeID: row.recipe.id)
              } label: {
                Label("Archive", systemImage: "archivebox")
              }
              .tint(.red)
            }
          }
        }
      case .selection:
        List(selection: $model.selectedRecipeID) {
          ForEach(model.visibleRecipeRows) { row in
            RecipeListRow(row: row, options: viewOptions)
              .tag(row.recipe.id)
              .swipeActions {
                Button {
                  model.deleteButtonTapped(recipeID: row.recipe.id)
                } label: {
                  Label("Archive", systemImage: "archivebox")
                }
                .tint(.red)
              }
          }
        }
      }
    }
    .navigationTitle("Recipes")
    .searchable(
      text: $model.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search recipes"
    )
    .safeAreaInset(edge: .top, spacing: 0) {
      RecipeListStatusBar(model: model)
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        RecipeListPresetMenu(
          presets: savedPresets,
          activePresetID: activePresetID
        ) { preset in
          model.applyListPreset(preset)
        } saveCurrentView: {
          isSavingListPreset = true
        } managePresets: {
          isManagingListPresets = true
        }
        .disabled(model.isImporting)
        RecipeSortMenu(model: model)
        RecipeListViewOptionsMenu(
          rowDensityRawValue: $rowDensityRawValue,
          showsSourceMetadata: $showsSourceMetadata,
          showsCategoryMetadata: $showsCategoryMetadata
        )
        Button {
          model.filterButtonTapped()
        } label: {
          Label(
            "Filter Recipes",
            systemImage: model.hasActiveFilters
              ? "line.3.horizontal.decrease.circle.fill"
              : "line.3.horizontal.decrease.circle"
          )
        }
        .disabled(model.isImporting)
        Button {
          model.addRecipeButtonTapped()
        } label: {
          Label("Add Recipe", systemImage: "plus")
        }
        .disabled(model.isImporting)
        Button {
          model.captureRecipeButtonTapped()
        } label: {
          Label("Capture Recipe", systemImage: "link.badge.plus")
        }
        .disabled(model.isImporting)
      }
    }
    .sheet(isPresented: $isSavingListPreset) {
      NavigationStack {
        RecipeListPresetSaveView(
          state: model.currentListPresetState,
          recipeCount: model.filteredRecipeCount,
          existingNames: savedListPresets.map(\.name)
        ) { name in
          saveCurrentListPreset(named: name)
        }
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $isManagingListPresets) {
      NavigationStack {
        RecipeListPresetManagementView(
          presets: savedListPresets,
          activePresetID: activeListPresetID
        ) { preset in
          model.recipeCount(for: preset)
        } applyPreset: { preset in
          model.applyListPreset(preset)
        } deletePreset: { preset in
          deleteListPreset(preset)
        }
      }
    }
  }

  private var savedListPresets: [RecipeListPreset] {
    get {
      RecipeListPresetPersistence.decode(savedPresetsData)
    }
    nonmutating set {
      savedPresetsData = RecipeListPresetPersistence.encode(newValue)
    }
  }

  private var activeListPresetID: RecipeListPreset.ID? {
    savedListPresets.first { $0.state == model.currentListPresetState }?.id
  }

  private func saveCurrentListPreset(named name: String) {
    let timestamp = Date()
    let preset = RecipeListPreset(
      id: UUID(),
      name: name,
      state: model.currentListPresetState,
      dateCreated: timestamp,
      dateModified: timestamp
    )
    var presets = savedListPresets
    presets.append(preset)
    savedListPresets = presets
  }

  private func deleteListPreset(_ preset: RecipeListPreset) {
    var presets = savedListPresets
    presets.removeAll { $0.id == preset.id }
    savedListPresets = presets
  }
}

struct ArchivedRecipesView: View {
  let model: RecipeLibraryModel

  var body: some View {
    List {
      if model.archivedRecipeRows.isEmpty {
        ContentUnavailableView("No Archived Recipes", systemImage: "archivebox")
          .frame(maxWidth: .infinity, minHeight: 280)
      } else {
        ForEach(model.archivedRecipeRows) { row in
          ArchivedRecipeRow(model: model, row: row)
            .swipeActions(edge: .leading) {
              Button {
                model.restoreArchivedRecipeButtonTapped(recipeID: row.recipe.id)
              } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
              }
              .tint(.green)
            }
            .swipeActions {
              Button(role: .destructive) {
                model.deleteArchivedRecipeButtonTapped(recipeID: row.recipe.id)
              } label: {
                Label("Delete Permanently", systemImage: "trash")
              }
            }
        }
      }
    }
    .navigationTitle("Archived Recipes")
  }
}

private struct ArchivedRecipeRow: View {
  let model: RecipeLibraryModel
  let row: RecipeListRowData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.recipe.title)
        .font(.headline)
      Text("Archived \(row.recipe.dateModified, format: .dateTime.month(.abbreviated).day().year())")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if let source = row.source?.name ?? row.source?.publicationName {
        Text(source)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contextMenu {
      Button {
        model.restoreArchivedRecipeButtonTapped(recipeID: row.recipe.id)
      } label: {
        Label("Restore", systemImage: "arrow.uturn.backward")
      }
      Button(role: .destructive) {
        model.deleteArchivedRecipeButtonTapped(recipeID: row.recipe.id)
      } label: {
        Label("Delete Permanently", systemImage: "trash")
      }
    }
  }
}

private extension UTType {
  static var paprikaRecipes: UTType {
    UTType(filenameExtension: "paprikarecipes") ?? .data
  }
}

private struct RecipeSortMenu: View {
  let model: RecipeLibraryModel

  var body: some View {
    @Bindable var model = model

    Menu {
      Picker("Sort Recipes", selection: $model.sortOrder) {
        ForEach(RecipeListSort.allCases) { sort in
          Text(sort.title)
            .tag(sort)
        }
      }
    } label: {
      Label("Sort Recipes", systemImage: "arrow.up.arrow.down")
    }
    .disabled(model.isImporting)
  }
}

private struct RecipeFilterView: View {
  let model: RecipeLibraryModel
  @State private var tagSearchText = ""

  private var filteredTagOptions: [String] {
    let query = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return model.tagFilterOptions }
    return model.tagFilterOptions.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section {
        Picker("Library", selection: $model.libraryScope) {
          ForEach(RecipeLibraryScope.allCases) { scope in
            Text(scope.title)
              .tag(scope)
          }
        }
        .pickerStyle(.segmented)
        Toggle("Favorites", isOn: $model.showsFavoritesOnly)
        Toggle("With Photos", isOn: $model.showsPhotosOnly)
      }

      Section {
        if model.categoryFilterOptions.isEmpty {
          Text("No categories yet")
            .foregroundStyle(.secondary)
        } else {
          NavigationLink {
            RecipeCategoryFilterPickerView(model: model)
          } label: {
            StackedFormField(title: "Categories") {
              Text(model.selectedCategoryFilterSummary)
                .foregroundStyle(model.selectedCategoryNames.isEmpty ? .secondary : .primary)
                .lineLimit(3)
            }
          }
        }
      } header: {
        Text("Categories")
      } footer: {
        if !model.selectedCategoryNames.isEmpty {
          Text("Recipes must match all selected categories. Parent categories include descendants.")
        }
      }

      Section {
        if model.tagFilterOptions.isEmpty {
          Text("No tags yet")
            .foregroundStyle(.secondary)
        } else {
          StackedTextField(title: "Find tags", text: $tagSearchText)
            .textInputAutocapitalization(.never)
          if filteredTagOptions.isEmpty {
            Text("No matching tags")
              .foregroundStyle(.secondary)
          } else {
            ForEach(filteredTagOptions, id: \.self) { tagName in
              RecipeFilterSelectionRow(
                title: tagName,
                systemImage: "tag",
                isSelected: model.selectedTagNames.contains(tagName)
              ) {
                model.tagFilterButtonTapped(tagName)
              }
            }
          }
        }
      } header: {
        Text("Tags")
      } footer: {
        if model.selectedTagNames.count > 1 {
          Text("Recipes must match all selected tags.")
        }
      }

      Section("Fields") {
        RecipeOptionalStringPicker(
          title: "Cuisine",
          selection: $model.selectedCuisine,
          options: model.cuisineFilterOptions
        )
        RecipeOptionalStringPicker(
          title: "Course",
          selection: $model.selectedCourse,
          options: model.courseFilterOptions
        )
      }

      Section {
        RecipeStringFilterNavigationRow(
          title: "Sources",
          emptyTitle: "No sources",
          summary: model.selectedSourceFilterSummary,
          systemImage: "book",
          isDefaultSelection: model.selectedSourceNames.isEmpty,
          options: model.sourceFilterOptions
        ) {
          RecipeStringFilterPickerView(
            title: "Sources",
            options: model.sourceFilterOptions,
            popularOptions: model.popularSourceFilterOptions,
            remainingOptions: model.remainingSourceFilterOptions,
            countsByOption: model.sourceFilterCountsByName,
            selectedValues: model.selectedSourceNames,
            systemImage: "book"
          ) { sourceName in
            model.sourceFilterButtonTapped(sourceName)
          }
        }

        RecipeStringFilterNavigationRow(
          title: "Authors",
          emptyTitle: "No authors",
          summary: model.selectedAuthorFilterSummary,
          systemImage: "person.text.rectangle",
          isDefaultSelection: model.selectedAuthorNames.isEmpty,
          options: model.authorFilterOptions
        ) {
          RecipeStringFilterPickerView(
            title: "Authors",
            options: model.authorFilterOptions,
            popularOptions: model.popularAuthorFilterOptions,
            remainingOptions: model.remainingAuthorFilterOptions,
            countsByOption: model.authorFilterCountsByName,
            selectedValues: model.selectedAuthorNames,
            systemImage: "person.text.rectangle"
          ) { authorName in
            model.authorFilterButtonTapped(authorName)
          }
        }
      } header: {
        Text("Source")
      } footer: {
        if !model.selectedSourceNames.isEmpty || !model.selectedAuthorNames.isEmpty {
          Text("Recipes may match any selected source and any selected author.")
        }
      }
    }
    .navigationTitle("Filters")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Clear") {
          model.clearFiltersButtonTapped()
        }
        .disabled(!model.hasActiveFilters)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          model.doneFilteringButtonTapped()
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
