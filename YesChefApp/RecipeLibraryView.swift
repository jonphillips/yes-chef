import SwiftUI
import SwiftUINavigation
import UIKit
import UniformTypeIdentifiers
import YesChefCore

struct AppContainer: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var recipeModel = RecipeLibraryModel()
  @State private var mealCalendarModel = MealCalendarModel()
  @State private var menuModel = MenuLibraryModel()
  @State private var groceryModel = GroceryLibraryModel()
  @State private var selectedSection: AppSection? = .recipes
  @State private var selectedSettingsPane: SettingsPane? = .categories
  @State private var presentedRecipeID: Recipe.ID?

  var body: some View {
    @Bindable var recipeModel = recipeModel
    @Bindable var mealCalendarModel = mealCalendarModel
    @Bindable var menuModel = menuModel
    @Bindable var groceryModel = groceryModel

    AppMainLayout(
      horizontalSizeClass: horizontalSizeClass,
      recipeModel: recipeModel,
      mealCalendarModel: mealCalendarModel,
      menuModel: menuModel,
      groceryModel: groceryModel,
      selectedSection: $selectedSection,
      selectedSettingsPane: $selectedSettingsPane,
      onRecipeSelected: { recipeID in
        presentedRecipeID = recipeID
      }
    )
    .fullScreenCover(item: $presentedRecipeID, id: \.self) { recipeID in
      RecipeFullScreenCover(
        recipeID: recipeID,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel
      )
    }
    .sheet(item: $mealCalendarModel.destination.itemEditor, id: \.self) { context in
      NavigationStack {
        MealPlanItemEditorView(model: mealCalendarModel, context: context)
      }
    }
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
      mealCalendarModel: mealCalendarModel
    )
    .sheet(isPresented: $recipeModel.destination.addRecipe) {
      NavigationStack {
        RecipeEditorView(recipeID: nil)
      }
    }
    .sheet(isPresented: $recipeModel.destination.filterRecipes) {
      NavigationStack {
        RecipeFilterView(model: recipeModel)
      }
    }
    .sheet(item: $recipeModel.destination.editRecipe, id: \.self) { (recipeID: Recipe.ID) in
      NavigationStack {
        RecipeEditorView(recipeID: recipeID)
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
    .alert("Import Complete", item: $recipeModel.destination.importSummary) { _ in
      Button("OK") {}
    } message: { summary in
      Text(summary.message)
    }
    .alert("Backup Supplement Complete", item: $recipeModel.destination.backupSupplementSummary) { _ in
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
  }

}

private struct RecipeFullScreenCover: View {
  @Environment(\.dismiss) private var dismiss
  let recipeID: Recipe.ID
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel

  var body: some View {
    NavigationStack {
      RecipeDetailView(
        recipeID: recipeID,
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
  }
}

private struct GroceryDestinationsModifier: ViewModifier {
  let groceryModel: GroceryLibraryModel
  let mealCalendarModel: MealCalendarModel

  func body(content: Content) -> some View {
    @Bindable var groceryModel = groceryModel

    content
      .sheet(isPresented: $groceryModel.destination.addList) {
        NavigationStack {
          GroceryListEditorView(model: groceryModel)
        }
      }
      .sheet(item: $groceryModel.destination.editList, id: \.self) { listID in
        NavigationStack {
          GroceryListEditorView(model: groceryModel, listID: listID)
        }
      }
      .sheet(isPresented: $groceryModel.destination.addCustomItem) {
        NavigationStack {
          GroceryItemEditorView(model: groceryModel)
        }
      }
      .sheet(isPresented: $groceryModel.destination.addPantryItem) {
        NavigationStack {
          PantryItemEditorView(model: groceryModel)
        }
      }
      .sheet(item: $groceryModel.destination.editPantryItem, id: \.self) { itemID in
        NavigationStack {
          PantryItemEditorView(model: groceryModel, itemID: itemID)
        }
      }
      .sheet(item: $groceryModel.destination.selectIngredients, id: \.self) { context in
        NavigationStack {
          GroceryIngredientSelectionView(
            model: groceryModel,
            context: context,
            choices: groceryModel.ingredientChoices(
              for: context,
              mealRows: mealCalendarModel.itemRows
            ),
            mealRows: mealCalendarModel.itemRows,
            pantryStaples: groceryModel.pantryStapleNames
          )
        }
      }
      .confirmationDialog(
        "Clear Purchased?",
        item: $groceryModel.destination.clearPurchased,
        titleVisibility: .visible
      ) { listID in
        Button("Clear Purchased", role: .destructive) {
          groceryModel.confirmClearPurchasedButtonTapped(listID: listID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { listID in
        Text("Remove purchased items from \(groceryModel.title(forList: listID))?")
      }
      .confirmationDialog(
        "Clear Grocery List?",
        item: $groceryModel.destination.clearAll,
        titleVisibility: .visible
      ) { listID in
        Button("Clear All", role: .destructive) {
          groceryModel.confirmClearAllButtonTapped(listID: listID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { listID in
        Text("Remove every item from \(groceryModel.title(forList: listID))?")
      }
      .confirmationDialog(
        "Delete Grocery List?",
        item: $groceryModel.destination.deleteList,
        titleVisibility: .visible
      ) { listID in
        Button("Delete List", role: .destructive) {
          groceryModel.confirmDeleteListButtonTapped(listID: listID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { listID in
        Text("Delete \(groceryModel.title(forList: listID)) and its grocery items?")
      }
  }
}

private extension View {
  func groceryDestinations(
    groceryModel: GroceryLibraryModel,
    mealCalendarModel: MealCalendarModel
  ) -> some View {
    modifier(
      GroceryDestinationsModifier(
        groceryModel: groceryModel,
        mealCalendarModel: mealCalendarModel
      )
    )
  }
}

private struct AppMainLayout: View {
  let horizontalSizeClass: UserInterfaceSizeClass?
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel
  @Binding var selectedSection: AppSection?
  @Binding var selectedSettingsPane: SettingsPane?
  var onRecipeSelected: (Recipe.ID) -> Void

  var body: some View {
    if horizontalSizeClass == .compact {
      AppCompactTabView(
        selection: $selectedSection,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        menuModel: menuModel,
        groceryModel: groceryModel,
        onMenuSelected: openMenuFromCalendar,
        onRecipeSelected: onRecipeSelected
      )
    } else if selectedSection == .mealCalendar {
      NavigationSplitView {
        AppSidebar(selection: $selectedSection)
      } detail: {
        MealCalendarWorkspaceView(
          model: mealCalendarModel,
          onMenuSelected: openMenuFromCalendar,
          onRecipeSelected: onRecipeSelected
        )
      }
    } else {
      NavigationSplitView {
        AppSidebar(selection: $selectedSection)
      } content: {
      switch selectedSection ?? .recipes {
        case .recipes:
          RecipeListView(model: recipeModel, style: .selection)
        case .mealCalendar:
          MealCalendarWorkspaceView(
            model: mealCalendarModel,
            onMenuSelected: openMenuFromCalendar,
            onRecipeSelected: onRecipeSelected
          )
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
        switch selectedSection ?? .recipes {
        case .recipes:
          RecipeDetailColumn(
            model: recipeModel,
            mealCalendarModel: mealCalendarModel,
            groceryModel: groceryModel
          )
        case .mealCalendar:
          EmptyView()
        case .groceries:
          GroceryDetailColumn(
            model: groceryModel,
            mealCalendarModel: mealCalendarModel
          )
        case .menus:
          MenuDetailColumn(
            model: menuModel,
            recipeModel: recipeModel,
            onRecipeSelected: onRecipeSelected
          )
        case .settings:
          SettingsDetailPane(
            selectedPane: selectedSettingsPane,
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

private struct AppCompactTabView: View {
  @Binding var selection: AppSection?
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel
  let onMenuSelected: (CoreMenu.ID) -> Void
  let onRecipeSelected: (Recipe.ID) -> Void

  var body: some View {
    TabView(selection: $selection) {
      RecipesStack(
        model: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel
      )
        .tabItem { AppSection.recipes.label }
        .tag(AppSection.recipes as AppSection?)
      MealCalendarStack(
        model: mealCalendarModel,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected
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
        onRecipeSelected: onRecipeSelected
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

  var body: some View {
    if let recipe = model.selectedRecipe {
      RecipeDetailView(
        recipeID: recipe.id,
        libraryModel: model,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel
      )
        .id(recipe.id)
    } else {
      ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
    }
  }
}

private struct SettingsStack: View {
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel

  var body: some View {
    NavigationStack {
      SettingsView(model: model, groceryModel: groceryModel)
    }
  }
}

private struct SettingsView: View {
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel
  private let selectedPane: Binding<SettingsPane?>?

  init(
    model: RecipeLibraryModel,
    groceryModel: GroceryLibraryModel,
    selectedPane: Binding<SettingsPane?>? = nil
  ) {
    self.model = model
    self.groceryModel = groceryModel
    self.selectedPane = selectedPane
  }

  var body: some View {
    Form {
      Section("Library") {
        categoryRow
        pantryRow
      }

      Section("Import & Export") {
        Button {
          model.importPaprikaExportButtonTapped()
        } label: {
          Label("Import Paprika HTML Export", systemImage: "square.and.arrow.down")
        }
        .disabled(model.isImporting)

        Button {
          model.supplementPaprikaBackupButtonTapped()
        } label: {
          Label("Supplement Paprika Backup", systemImage: "calendar.badge.clock")
        }
        .disabled(model.isImporting)
      }
    }
    .navigationTitle("Settings")
  }

  @ViewBuilder private var categoryRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .categories
      } label: {
        SettingsPane.categories.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        CategoryManagementView()
      } label: {
        SettingsPane.categories.label
      }
    }
  }

  @ViewBuilder private var pantryRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .pantry
      } label: {
        SettingsPane.pantry.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        PantrySettingsView(model: groceryModel)
      } label: {
        SettingsPane.pantry.label
      }
    }
  }
}

private struct SettingsDetailPane: View {
  let selectedPane: SettingsPane?
  let groceryModel: GroceryLibraryModel

  var body: some View {
    switch selectedPane {
    case .categories:
      NavigationStack {
        CategoryManagementView()
      }
    case .pantry:
      NavigationStack {
        PantrySettingsView(model: groceryModel)
      }
    case nil:
      ContentUnavailableView("Settings", systemImage: AppSection.settings.systemImage)
    }
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
                Label("Delete", systemImage: "trash")
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

private struct RecipeCategoryFilterPickerView: View {
  let model: RecipeLibraryModel
  @State private var searchText = ""

  private var rootNodes: [RecipeCategoryFilterNode] {
    RecipeCategoryFilterNode.tree(from: model.categoryFilterOptions)
  }

  private var matchingNodes: [RecipeCategoryFilterNode] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }
    return rootNodes
      .flatMap(\.flattened)
      .filter { $0.path.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    let availabilityByName = model.categoryFilterAvailabilityByName

    Group {
      if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        RecipeCategoryFilterLevelView(
          model: model,
          title: "Categories",
          parentNode: nil,
          nodes: rootNodes,
          availabilityByName: availabilityByName
        )
      } else {
        List {
          if matchingNodes.isEmpty {
            ContentUnavailableView("No Matching Categories", systemImage: "folder")
          } else {
            ForEach(matchingNodes) { node in
              let availability = availabilityByName[node.path] ?? .empty(categoryName: node.path)
              RecipeFilterSelectionRow(
                title: node.path,
                systemImage: "folder",
                detail: availability.countText,
                isSelected: availability.isSelected,
                isEnabled: availability.isEnabled
              ) {
                model.categoryFilterButtonTapped(node.path)
              }
            }
          }
        }
        .navigationTitle("Categories")
      }
    }
    .searchable(text: $searchText, prompt: "Search categories")
  }
}

private struct RecipeCategoryFilterLevelView: View {
  let model: RecipeLibraryModel
  let title: String
  let parentNode: RecipeCategoryFilterNode?
  let nodes: [RecipeCategoryFilterNode]
  let availabilityByName: [String: RecipeCategoryFilterAvailability]

  var body: some View {
    List {
      if let parentNode {
        Section {
          let availability = availabilityByName[parentNode.path] ?? .empty(categoryName: parentNode.path)
          RecipeFilterSelectionRow(
            title: "All \(parentNode.title)",
            systemImage: "folder.fill",
            detail: availability.countText,
            isSelected: availability.isSelected,
            isEnabled: availability.isEnabled
          ) {
            model.categoryFilterButtonTapped(parentNode.path)
          }
        } footer: {
          Text("Parent filters include recipes in descendant categories. Disabled categories would leave no recipes with the current filters.")
        }
      }

      Section(parentNode == nil ? "Top Level" : "Subcategories") {
        ForEach(nodes) { node in
          RecipeCategoryFilterNodeRow(
            model: model,
            node: node,
            availabilityByName: availabilityByName
          )
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RecipeCategoryFilterNodeRow: View {
  let model: RecipeLibraryModel
  let node: RecipeCategoryFilterNode
  let availabilityByName: [String: RecipeCategoryFilterAvailability]

  var body: some View {
    if node.children.isEmpty {
      RecipeFilterSelectionRow(
        title: node.title,
        systemImage: "folder",
        detail: availability.countText,
        isSelected: availability.isSelected,
        isEnabled: availability.isEnabled
      ) {
        model.categoryFilterButtonTapped(node.path)
      }
    } else {
      NavigationLink {
        RecipeCategoryFilterLevelView(
          model: model,
          title: node.title,
          parentNode: node,
          nodes: node.children,
          availabilityByName: availabilityByName
        )
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "folder.fill")
            .foregroundStyle(.secondary)
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 2) {
            Text(node.title)
            if let summary {
              Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .disabled(!isNavigable)
      .opacity(isNavigable ? 1 : 0.55)
    }
  }

  private var availability: RecipeCategoryFilterAvailability {
    availabilityByName[node.path] ?? .empty(categoryName: node.path)
  }

  private var descendantAvailabilities: [RecipeCategoryFilterAvailability] {
    node.flattened.map { availabilityByName[$0.path] ?? .empty(categoryName: $0.path) }
  }

  private var selectedPathCount: Int {
    descendantAvailabilities.filter(\.isSelected).count
  }

  private var possiblePathCount: Int {
    descendantAvailabilities.filter { !$0.isSelected && $0.matchingRecipeCount > 0 }.count
  }

  private var isNavigable: Bool {
    selectedPathCount > 0 || possiblePathCount > 0
  }

  private var summary: String? {
    switch (selectedPathCount, possiblePathCount) {
    case (0, 0):
      "No matches"
    case (0, let possible):
      "\(possible) possible"
    case (let selected, 0):
      "\(selected) selected"
    case let (selected, possible):
      "\(selected) selected · \(possible) possible"
    }
  }
}

private struct RecipeCategoryFilterNode: Identifiable, Equatable {
  let title: String
  let path: String
  let children: [RecipeCategoryFilterNode]

  var id: String { path }

  var flattened: [RecipeCategoryFilterNode] {
    [self] + children.flatMap(\.flattened)
  }

  static func tree(from categoryPaths: [String]) -> [RecipeCategoryFilterNode] {
    let parsedPaths = categoryPaths
      .map(pathComponents)
      .filter { !$0.isEmpty }
    return nodes(parentComponents: [], parsedPaths: parsedPaths)
  }

  private static func nodes(
    parentComponents: [String],
    parsedPaths: [[String]]
  ) -> [RecipeCategoryFilterNode] {
    let depth = parentComponents.count
    let childTitles: Set<String> = Set(
      parsedPaths.compactMap { components in
        guard components.count > depth,
              hasPrefix(parentComponents, in: components) else { return nil }
        return components[depth]
      }
    )

    return childTitles
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      .map { title in
        let components = parentComponents + [title]
        let childPaths = parsedPaths.filter { hasPrefix(components, in: $0) }
        return RecipeCategoryFilterNode(
          title: title,
          path: components.joined(separator: " > "),
          children: nodes(parentComponents: components, parsedPaths: childPaths)
        )
      }
  }

  private static func pathComponents(_ path: String) -> [String] {
    path
      .split(separator: ">")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func hasPrefix(_ prefix: [String], in components: [String]) -> Bool {
    guard prefix.count <= components.count else { return false }
    return zip(prefix, components).allSatisfy { pair in
      pair.0 == pair.1
    }
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.seedSampleDataIfNeeded()
  }
  AppContainer()
}
