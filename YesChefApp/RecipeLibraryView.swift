import Dependencies
import SwiftUI
import SwiftUINavigation
import UIKit
import UniformTypeIdentifiers
import WebExtractorKit
import WebKit
import YesChefCore

struct AppContainer: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Dependency(\.handoffReviewCoordinator) private var handoffReviewCoordinator
  @State private var toastCenter: AppToastCenter
  @State private var recipeModel = RecipeLibraryModel()
  @State private var powerBrowserModel = PowerBrowserModel()
  @State private var createRecipeModel = CreateRecipeModel()
  @State private var workbenchModel = WorkbenchLibraryModel()
  @State private var browserModel = BrowserModel()
  @State private var mealCalendarModel: MealCalendarModel
  @State private var menuModel: MenuLibraryModel
  @State private var groceryModel: GroceryLibraryModel
  @State private var selectedSection: AppSection? = .recipes
  @State private var selectedSettingsPane: SettingsPane? = .categories
  @State private var presentedRecipe: RecipeDetailPresentation?
  @State private var presentedCookSession: CookSessionPresentation?

  init() {
    let toastCenter = AppToastCenter()
    let mealCalendarModel = MealCalendarModel(toastCenter: toastCenter)
    let groceryModel = GroceryLibraryModel(toastCenter: toastCenter)
    // Push a day's recipes into the grocery list from the Meal Calendar without either model
    // holding the other (item 2). The immediate add toasts on its own.
    mealCalendarModel.onAddDayToGroceries = { [weak groceryModel] rows in
      groceryModel?.addMealRowsImmediately(rows)
    }
    _toastCenter = State(wrappedValue: toastCenter)
    _mealCalendarModel = State(wrappedValue: mealCalendarModel)
    _menuModel = State(wrappedValue: MenuLibraryModel(toastCenter: toastCenter))
    _groceryModel = State(wrappedValue: groceryModel)
  }

  var body: some View {
    @Bindable var recipeModel = recipeModel
    @Bindable var workbenchModel = workbenchModel
    @Bindable var mealCalendarModel = mealCalendarModel
    @Bindable var menuModel = menuModel
    @Bindable var groceryModel = groceryModel
    @Bindable var handoffReviewCoordinator = handoffReviewCoordinator

    AppMainLayout(
      horizontalSizeClass: horizontalSizeClass,
      recipeModel: recipeModel,
      powerBrowserModel: powerBrowserModel,
      workbenchModel: workbenchModel,
      browserModel: browserModel,
      mealCalendarModel: mealCalendarModel,
      menuModel: menuModel,
      groceryModel: groceryModel,
      createRecipeModel: createRecipeModel,
      selectedSection: $selectedSection,
      selectedSettingsPane: $selectedSettingsPane,
      onBrowserCapture: browserCaptureButtonTapped,
      onRecipeSelected: { presentation in
        presentedRecipe = presentation
      },
      onCookSessionRequested: { presentation in
        presentedCookSession = presentation
      },
      onRecipeCreated: recipeCreated
    )
    .fullScreenCover(item: $presentedRecipe) { presentation in
      RecipeFullScreenCover(
        presentation: presentation,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        toastCenter: toastCenter,
        onRecipeSelected: { presentedRecipe = $0 }
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
    .sheet(item: $recipeModel.destination.workbench) { presentation in
      NavigationStack {
        WorkbenchDetailView(
          workbenchID: presentation.workbenchID,
          onRecipeSelected: { recipePresentation in
            presentedRecipe = recipePresentation
          }
        )
      }
    }
    .sheet(isPresented: $workbenchModel.destination.addWorkbench) {
      NavigationStack {
        WorkbenchEditorView(model: workbenchModel)
      }
    }
    .sheet(
      item: $handoffReviewCoordinator.review,
      id: \.handoffID,
      onDismiss: {
        handoffReviewCoordinator.presentPendingAdjustmentReviewAfterReviewDismissal()
      }
    ) { review in
      HandoffReviewSheet(coordinator: handoffReviewCoordinator, review: review)
    }
    .sheet(item: $handoffReviewCoordinator.adjustmentReview) { review in
      RecipeAdjustmentReviewView(
        review: review,
        overwrite: { handoffReviewCoordinator.overwriteAdjustmentButtonTapped($0) },
        keepAsVariation: { handoffReviewCoordinator.keepAdjustmentAsVariationButtonTapped($0, name: $1) },
        saveVariation: { handoffReviewCoordinator.saveScopedVariationButtonTapped($0) }
      )
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
      "Delete Menu?",
      item: $menuModel.destination.deleteMenu,
      titleVisibility: .visible
    ) { context in
      Button("Delete Menu", role: .destructive) {
        menuModel.confirmDeleteMenuButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { context in
      Text(deleteMenuMessage(context))
    }
    .confirmationDialog(
      "Delete Workbench?",
      item: $workbenchModel.destination.deleteWorkbench,
      titleVisibility: .visible
    ) { context in
      Button("Delete Workbench", role: .destructive) {
        workbenchModel.confirmDeleteWorkbenchButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { context in
      Text(deleteWorkbenchMessage(context))
    }
    .confirmationDialog(
      "Remove Dish?",
      item: $menuModel.destination.deleteItem,
      titleVisibility: .visible
    ) { context in
      Button("Remove Dish", role: .destructive) {
        menuModel.confirmDeleteMenuItemButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { context in
      Text("Remove \(context.title) from this menu?")
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
    .alert("Workbenches Error", isPresented: $workbenchModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(workbenchModel.errorMessage ?? "")
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
      workbenchModel: workbenchModel,
      browserModel: browserModel,
      mealCalendarModel: mealCalendarModel,
      menuModel: menuModel,
      groceryModel: groceryModel
    )
  }

  /// A Create Recipe save lands the cook on the recipe they just made (Jon's call): select it in the
  /// library and switch to Recipes. The Create Recipe session is finished, so its in-memory model is
  /// replaced with a fresh one for the next visit.
  @MainActor private func recipeCreated(_ recipeID: Recipe.ID) {
    recipeModel.selectedRecipeID = recipeID
    createRecipeModel = CreateRecipeModel()
    selectedSection = .recipes
  }

  @MainActor private func browserCaptureButtonTapped(page: WebPage) async {
    let outcome = await browserModel.captureButtonTapped(page: page) { html, url in
      await recipeModel.captureModel.ingestBrowserCapture(html: html, sourceURL: url)
    }
    if outcome == .extracted {
      let readerFeedbackComments = browserModel.takeReaderFeedbackDraft()
      recipeModel.captureModel.stageReaderFeedback(tips: [], comments: readerFeedbackComments)
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
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    NavigationStack {
      RecipeDetailView(
        recipeID: presentation.recipeID,
        scaleContext: presentation.scaleContext,
        workbenchID: presentation.workbenchID,
        libraryModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        onRecipeSelected: onRecipeSelected
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

struct RecipeListView: View {
  @AppStorage("RecipeList.rowDensity") private var rowDensityRawValue = RecipeListRowDensity.rich.rawValue
  @AppStorage("RecipeList.showsSourceMetadata") private var showsSourceMetadata = true
  @AppStorage("RecipeList.showsCategoryMetadata") private var showsCategoryMetadata = true

  let model: RecipeLibraryModel

  var body: some View {
    @Bindable var model = model
    let viewOptions = RecipeListViewOptions(
      density: RecipeListRowDensity(rawValue: rowDensityRawValue) ?? .rich,
      showsSourceMetadata: showsSourceMetadata,
      showsCategoryMetadata: showsCategoryMetadata
    )

    Group {
      if model.isSelectingWorkbenchRecipes {
        List(selection: $model.selectedWorkbenchRecipeIDs) {
          ForEach(model.visibleRecipeRows) { row in
            RecipeListRow(row: row, options: viewOptions)
              .tag(row.recipe.id)
          }
        }
        .environment(\.editMode, .constant(.active))
      } else {
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
    .toolbar(removing: .sidebarToggle)
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
        RecipeSortMenu(model: model)
        RecipeListViewOptionsMenu(
          rowDensityRawValue: $rowDensityRawValue,
          showsSourceMetadata: $showsSourceMetadata,
          showsCategoryMetadata: $showsCategoryMetadata
        )
        if model.isSelectingWorkbenchRecipes {
          Button {
            model.cancelWorkbenchSelectionButtonTapped()
          } label: {
            Label("Cancel", systemImage: "xmark")
          }
          Button {
            model.workbenchTheseButtonTapped()
          } label: {
            Label("Workbench These", systemImage: "hammer")
          }
          .disabled(model.selectedWorkbenchRecipeIDs.isEmpty)
        } else {
          Button {
            model.workbenchSelectionButtonTapped()
          } label: {
            Label("Workbench These", systemImage: "checklist")
          }
          .disabled(model.isImporting)
        }
      }
    }
  }
}

struct ArchivedRecipesView: View {
  let model: RecipeLibraryModel

  var body: some View {
    // The empty state is an `.overlay`, never a branch *inside* the List. Deleting the last row
    // would otherwise swap the List's single child from a ForEach to a ContentUnavailableView in one
    // update, and SwiftUI's collection-view coordinator raises an invalid-batch-update exception —
    // a hard crash *after* the delete already committed. Keep the ForEach unconditional so the List
    // only ever goes from 1 row to 0.
    List {
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
            Button {
              model.deleteArchivedRecipeButtonTapped(recipeID: row.recipe.id)
            } label: {
              Label("Delete Permanently", systemImage: "trash")
            }
            .tint(.red)
          }
      }
    }
    .overlay {
      if model.archivedRecipeRows.isEmpty {
        ContentUnavailableView("No Archived Recipes", systemImage: "archivebox")
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
