import SwiftUI
import UIKit
import UniformTypeIdentifiers
import YesChefCore

struct MenusStack: View {
  let model: MenuLibraryModel
  let recipeModel: RecipeLibraryModel
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.navigationPath) {
      MenuListView(model: model, style: .navigation)
        .navigationDestination(for: CoreMenu.ID.self) { menuID in
          MenuDetailView(
            model: model,
            recipeModel: recipeModel,
            menuID: menuID,
            onRecipeSelected: onRecipeSelected,
            onCookSessionRequested: onCookSessionRequested
          )
            .id(menuID)
        }
    }
  }
}

struct MenuListView: View {
  let model: MenuLibraryModel
  var style: MenuListStyle

  var body: some View {
    @Bindable var model = model

    Group {
      switch style {
      case .navigation:
        List {
          ForEach(model.menuRows) { row in
            NavigationLink(value: row.id) {
              MenuRowView(row: row)
            }
            .swipeActions {
              Button(role: .destructive) {
                model.deleteMenuButtonTapped(row)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
      case .selection:
        List(model.menuRows, selection: $model.selectedMenuID) { row in
          MenuRowView(row: row)
            .tag(row.id)
            .swipeActions {
              Button(role: .destructive) {
                model.deleteMenuButtonTapped(row)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
    }
    .navigationTitle("Menus")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.addMenuButtonTapped()
        } label: {
          Label("Add Menu", systemImage: "plus")
        }
      }
    }
  }
}

private struct MenuRowView: View {
  let row: MenuRowData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.menu.title)
        .font(.headline)
      HStack(spacing: 10) {
        Label(dayCountTitle, systemImage: "calendar")
        Label(itemCountTitle, systemImage: "fork.knife")
        if row.placementCount > 0 {
          Label("\(row.placementCount)", systemImage: "calendar.badge.checkmark")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var dayCountTitle: String {
    row.menu.dayCount == 1 ? "1 day" : "\(row.menu.dayCount) days"
  }

  private var itemCountTitle: String {
    row.itemCount == 1 ? "1 dish" : "\(row.itemCount) dishes"
  }
}

struct MenuDetailColumn: View {
  let model: MenuLibraryModel
  let recipeModel: RecipeLibraryModel
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?
  var isFocusActive = false
  var focusButtonTapped: (() -> Void)?

  var body: some View {
    if let menuID = model.selectedMenuID {
      MenuDetailView(
        model: model,
        recipeModel: recipeModel,
        menuID: menuID,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested,
        isFocusActive: isFocusActive,
        focusButtonTapped: focusButtonTapped
      )
        .id(menuID)
    } else {
      ContentUnavailableView("Select a Menu", systemImage: "menucard")
    }
  }
}

struct MenuDetailView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage(ChatWorkspaceDetent.storageKey)
  private var chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
  let model: MenuLibraryModel
  let recipeModel: RecipeLibraryModel
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?
  var isFocusActive = false
  var focusButtonTapped: (() -> Void)?
  @State private var detailModel: MenuDetailModel
  @State private var isShowingRecipeBrowser = false
  @State private var compactChatModel: RecipeChatModel?

  init(
    model: MenuLibraryModel,
    recipeModel: RecipeLibraryModel,
    menuID: CoreMenu.ID,
    onRecipeSelected: ((RecipeDetailPresentation) -> Void)? = nil,
    onCookSessionRequested: ((CookSessionPresentation) -> Void)? = nil,
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil
  ) {
    self.model = model
    self.recipeModel = recipeModel
    self.onRecipeSelected = onRecipeSelected
    self.onCookSessionRequested = onCookSessionRequested
    self.isFocusActive = isFocusActive
    self.focusButtonTapped = focusButtonTapped
    _detailModel = State(wrappedValue: MenuDetailModel(menuID: menuID))
  }

  var body: some View {
    Group {
      if let detail = detailModel.detail {
        Group {
          if isSplitEnabled {
            ChatWorkspaceSplit(
              context: .menu(MenuChatContext(detail: detail)),
              detentRaw: $chatWorkspaceDetentRaw,
              applyActions: { chatModel in detailModel.applyActionCatalog(for: chatModel) }
            ) {
              MenuDetailReader(
                model: model,
                detailModel: detailModel,
                detail: detail,
                onRecipeSelected: onRecipeSelected,
                regeneratePrepPlan: chatButtonTapped
              )
            }
          } else {
            MenuDetailReader(
              model: model,
              detailModel: detailModel,
              detail: detail,
              onRecipeSelected: onRecipeSelected,
              regeneratePrepPlan: chatButtonTapped
            )
          }
        }
        .navigationTitle(detail.menu.title)
      } else {
        ContentUnavailableView("Menu Not Found", systemImage: "menucard")
      }
    }
    .toolbar {
      if detailModel.detail != nil {
        ToolbarItemGroup(placement: .primaryAction) {
          if horizontalSizeClass != .compact, let focusButtonTapped {
            Button {
              focusButtonTapped()
            } label: {
              Label(
                "Focus",
                systemImage: isFocusActive ? "rectangle.expand" : "arrow.up.left.and.arrow.down.right"
              )
            }
          }
          if let cookSessionPresentation {
            Button {
              onCookSessionRequested?(cookSessionPresentation)
            } label: {
              Label("Cook these", systemImage: "flame")
            }
          }
          Button {
            isShowingRecipeBrowser.toggle()
          } label: {
            Label("Browse Recipes", systemImage: "sidebar.right")
          }
          if !isSplitEnabled {
            Button {
              chatButtonTapped()
            } label: {
              Label("Chat", systemImage: "sparkles")
            }
          }
        }
      }
    }
    .inspector(isPresented: $isShowingRecipeBrowser) {
      if detailModel.detail != nil {
        MenuRecipeBrowserPanel(
          recipeModel: recipeModel,
          onRecipeSelected: onRecipeSelected
        )
        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
      } else {
        ContentUnavailableView("Recipes", systemImage: "book.closed")
      }
    }
    .sheet(item: $compactChatModel) { chatModel in
      NavigationStack {
        RecipeChatPanel(
          chatModel: chatModel,
          applyActions: detailModel.applyActionCatalog(for: chatModel)
        )
      }
    }
  }

  private var isSplitEnabled: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
  }

  private var cookSessionPresentation: CookSessionPresentation? {
    detailModel.detail.flatMap(CookSessionPresentation.init(menuDetail:))
  }

  private func chatButtonTapped() {
    guard let detail = detailModel.detail else { return }
    if isSplitEnabled {
      chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
    } else {
      compactChatModel = RecipeChatModel(context: .menu(MenuChatContext(detail: detail)))
    }
  }
}

private extension CookSessionPresentation {
  init?(menuDetail detail: MenuDetailData) {
    let items = detail.itemRows.compactMap(CookSessionItem.init(menuItemRow:))
    guard !items.isEmpty else { return nil }
    self.init(title: detail.menu.title, items: items)
  }
}

private extension CookSessionItem {
  init?(menuItemRow row: MenuItemRowData) {
    guard row.item.kind == .recipe, let recipeID = row.recipe?.id else { return nil }
    self.init(
      recipeID: recipeID,
      scaleContext: .menuItem(row.item.id),
      title: row.displayTitle
    )
  }
}

private struct MenuDetailReader: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let detail: MenuDetailData
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var regeneratePrepPlan: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        MenuDetailHeader(detail: detail)
        MenuPrepPlanSection(
          menu: detail.menu,
          itemRows: detail.itemRows,
          clearPrepPlan: {
            model.clearPrepPlanButtonTapped(menuID: detailModel.menuID)
          },
          regeneratePrepPlan: regeneratePrepPlan
        )
        MenuDishList(
          model: model,
          menu: detail.menu,
          detail: detail,
          onRecipeSelected: onRecipeSelected
        )
        MenuPlacementList(
          model: model,
          menu: detail.menu,
          minimumDayCount: max((detail.itemRows.map(\.item.dayOffset).max() ?? 0) + 1, 1),
          placements: detail.placements
        )
      }
      .padding()
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .swipeActionsContainer()
  }
}

private struct MenuPrepPlanSection: View {
  let menu: CoreMenu
  let itemRows: [MenuItemRowData]
  var clearPrepPlan: () -> Void
  var regeneratePrepPlan: () -> Void

  private var steps: [PrepPlanStep] {
    MenuPrepPlanCoding.decode(menu.prepPlan)
  }

  private var dishTitlesByID: [MenuItem.ID: String] {
    Dictionary(uniqueKeysWithValues: itemRows.map { ($0.id, $0.displayTitle) })
  }

  var body: some View {
    if !steps.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("Prep Plan")
            .font(.title2.weight(.semibold))

          Spacer()

          Button {
            regeneratePrepPlan()
          } label: {
            Label("Regenerate", systemImage: "sparkles")
          }
          .buttonStyle(.bordered)

          Button(role: .destructive) {
            clearPrepPlan()
          } label: {
            Label("Clear", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
        }

        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "checklist")
                .font(.headline)
                .foregroundStyle(.secondary)

              VStack(alignment: .leading, spacing: 4) {
                Text(step.when)
                  .font(.headline)
                Text(step.task)
                if let sourceDish = step.sourceDish, let title = dishTitlesByID[sourceDish] {
                  Label(title, systemImage: "fork.knife")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              Spacer(minLength: 8)
            }
            .padding(.vertical, 12)

            if index < steps.count - 1 {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct MenuDetailHeader: View {
  let detail: MenuDetailData

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Label(dayCountTitle, systemImage: "calendar")
        Label(itemCountTitle, systemImage: "fork.knife")
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)

      if let notes = detail.menu.notes {
        Text(notes)
          .font(.body)
      }
    }
  }

  private var dayCountTitle: String {
    detail.menu.dayCount == 1 ? "1 day" : "\(detail.menu.dayCount) days"
  }

  private var itemCountTitle: String {
    detail.itemRows.count == 1 ? "1 dish" : "\(detail.itemRows.count) dishes"
  }
}

private struct MenuRecipeBrowserPanel: View {
  let recipeModel: RecipeLibraryModel
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    @Bindable var recipeModel = recipeModel

    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Recipes")
            .font(.headline)

          Spacer()

          Button {
            recipeModel.filterButtonTapped()
          } label: {
            Label(
              "Filter Recipes",
              systemImage: recipeModel.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.iconOnly)
          }
          .accessibilityLabel("Filter Recipes")
        }

        TextField("Search recipes", text: $recipeModel.searchText)
          .textFieldStyle(.roundedBorder)
          .textInputAutocapitalization(.never)
      }
      .padding()

      RecipeListStatusBar(model: recipeModel)

      List {
        if recipeModel.visibleRecipeRows.isEmpty {
          ContentUnavailableView.search(text: recipeModel.searchText)
        } else {
          ForEach(recipeModel.visibleRecipeRows) { row in
            Button {
              onRecipeSelected?(RecipeDetailPresentation(recipeID: row.recipe.id))
            } label: {
              RecipeListRow(
                row: row,
                options: RecipeListViewOptions(
                  density: .compact,
                  showsSourceMetadata: true,
                  showsCategoryMetadata: true
                )
              )
            }
            .buttonStyle(.plain)
            .draggable(MenuDraggedRecipe(recipeID: row.recipe.id))
          }
        }
      }
      .listStyle(.plain)
    }
    .background(.background)
  }
}

struct MenuEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var notes = ""
  @State private var dayCount = 1

  let model: MenuLibraryModel

  private var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section("Menu") {
        StackedTextField(title: "Title", text: $title, prompt: "Weekend menu")
        Stepper("Days: \(dayCount)", value: $dayCount, in: 1...14)
        StackedTextEditor(title: "Notes", text: $notes, minHeight: 100)
      }
    }
    .navigationTitle("Add Menu")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveMenuButtonTapped(title: title, notes: notes, dayCount: dayCount) {
            dismiss()
          }
        }
        .disabled(isSaveDisabled)
      }
    }
  }
}

struct MenuItemEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var kind = MealPlanItemKind.recipe
  @State private var dayOffset = 0
  @State private var mealSlot = MealPlanItemSlot.dinner
  @State private var selectedRecipeID: Recipe.ID?
  @State private var noteTitle = ""
  @State private var notes = ""
  @State private var recipeSearchText = ""

  let model: MenuLibraryModel
  let context: MenuItemDraftContext

  init(model: MenuLibraryModel, context: MenuItemDraftContext) {
    self.model = model
    self.context = context
    _kind = State(wrappedValue: context.kind == .reservation ? .note : context.kind)
    _dayOffset = State(wrappedValue: context.dayOffset)
    _mealSlot = State(wrappedValue: context.mealSlot)
    _selectedRecipeID = State(wrappedValue: context.recipeID)
    _noteTitle = State(wrappedValue: context.noteTitle)
    _notes = State(wrappedValue: context.notes)
  }

  private var dayOffsets: [Int] {
    Array(0..<max(context.dayCount, 1))
  }

  private var filteredRecipeRows: [RecipeListRowData] {
    let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return model.availableRecipeRows }
    return model.availableRecipeRows.filter { row in
      row.recipe.title.localizedCaseInsensitiveContains(query)
        || (row.recipe.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        || (row.recipe.summary?.localizedCaseInsensitiveContains(query) ?? false)
        || row.tagNames.contains { $0.localizedCaseInsensitiveContains(query) }
        || row.categoryNames.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  private var isSaveDisabled: Bool {
    switch kind {
    case .recipe:
      selectedRecipeID == nil
    case .note, .reservation:
      noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var body: some View {
    Form {
      Section("What") {
        Picker("Type", selection: $kind) {
          Text(MealPlanItemKind.recipe.title)
            .tag(MealPlanItemKind.recipe)
          Text(MealPlanItemKind.note.title)
            .tag(MealPlanItemKind.note)
        }
        .pickerStyle(.segmented)
      }

      Section("When") {
        Picker("Day", selection: $dayOffset) {
          ForEach(dayOffsets, id: \.self) { dayOffset in
            Text("Day \(dayOffset + 1)")
              .tag(dayOffset)
          }
        }

        Picker("Meal", selection: $mealSlot) {
          ForEach(MealPlanItemSlot.allCases, id: \.self) { mealSlot in
            Label(mealSlot.title, systemImage: mealSlot.systemImage)
              .tag(mealSlot)
          }
        }
      }

      switch kind {
      case .recipe:
        Section("Recipe") {
          StackedTextField(title: "Find Recipes", text: $recipeSearchText)
            .textInputAutocapitalization(.never)

          if model.availableRecipeRows.isEmpty {
            ContentUnavailableView("No Recipes", systemImage: "book.closed")
          } else if filteredRecipeRows.isEmpty {
            ContentUnavailableView.search(text: recipeSearchText)
          } else {
            ForEach(filteredRecipeRows) { row in
              Button {
                selectedRecipeID = row.recipe.id
              } label: {
                MenuRecipeSelectionRow(
                  row: row,
                  isSelected: selectedRecipeID == row.recipe.id
                )
              }
              .foregroundStyle(.primary)
            }
          }
        }

        Section("Notes") {
          StackedTextEditor(title: "Serving Notes", text: $notes, minHeight: 80)
        }
      case .note, .reservation:
        Section("Note") {
          StackedTextField(title: "Title", text: $noteTitle, prompt: "Prep reminder")
          StackedTextEditor(title: "Details", text: $notes, minHeight: 120)
        }
      }
    }
    .navigationTitle(context.isEditing ? "Edit Dish" : "Add Dish")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          saveButtonTapped()
        }
        .disabled(isSaveDisabled)
      }
    }
  }

  private func saveButtonTapped() {
    switch kind {
    case .recipe:
      guard let selectedRecipeID else { return }
      if let itemID = context.itemID {
        if model.updateRecipeItemButtonTapped(
          itemID: itemID,
          recipeID: selectedRecipeID,
          dayOffset: dayOffset,
          mealSlot: mealSlot,
          notes: notes
        ) {
          dismiss()
        }
      } else {
        if model.saveRecipeItemButtonTapped(
          menuID: context.menuID,
          recipeID: selectedRecipeID,
          dayOffset: dayOffset,
          mealSlot: mealSlot,
          notes: notes
        ) {
          dismiss()
        }
      }
    case .note, .reservation:
      if let itemID = context.itemID {
        if model.updateNoteItemButtonTapped(
          itemID: itemID,
          title: noteTitle,
          notes: notes,
          dayOffset: dayOffset,
          mealSlot: mealSlot
        ) {
          dismiss()
        }
      } else {
        if model.saveNoteItemButtonTapped(
          menuID: context.menuID,
          title: noteTitle,
          notes: notes,
          dayOffset: dayOffset,
          mealSlot: mealSlot
        ) {
          dismiss()
        }
      }
    }
  }
}

private struct MenuRecipeSelectionRow: View {
  let row: RecipeListRowData
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "book.closed")
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 4) {
        Text(row.recipe.title)
          .font(.headline)
        if let subtitle = row.recipe.subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else if !row.categoryNames.isEmpty {
          Text(row.categoryNames.joined(separator: ", "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Spacer()

      Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
        .foregroundStyle(.tint)
    }
    .padding(.vertical, 4)
  }
}

struct MenuPlacementEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var startDate: Date
  @State private var dayCount: Int

  let model: MenuLibraryModel
  let context: MenuPlacementDraftContext

  init(model: MenuLibraryModel, context: MenuPlacementDraftContext) {
    self.model = model
    self.context = context
    _startDate = State(wrappedValue: context.startDate)
    _dayCount = State(wrappedValue: context.dayCount)
  }

  var body: some View {
    Form {
      Section(context.menuTitle) {
        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
        Stepper("Days: \(dayCount)", value: $dayCount, in: context.minimumDayCount...14)
      }
    }
    .navigationTitle(context.isEditing ? "Edit Placement" : "Place Menu")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          var updatedContext = context
          updatedContext.dayCount = dayCount
          if model.savePlacementButtonTapped(context: updatedContext, startDate: startDate) {
            dismiss()
          }
        }
      }
    }
  }
}
