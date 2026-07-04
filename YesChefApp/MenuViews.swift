import SwiftUI
import UIKit
import UniformTypeIdentifiers
import YesChefCore

struct MenusStack: View {
  let model: MenuLibraryModel
  let recipeModel: RecipeLibraryModel
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.navigationPath) {
      MenuListView(model: model, style: .navigation)
        .navigationDestination(for: CoreMenu.ID.self) { menuID in
          MenuDetailView(
            model: model,
            recipeModel: recipeModel,
            menuID: menuID,
            onRecipeSelected: onRecipeSelected
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
          }
        }
      case .selection:
        List(model.menuRows, selection: $model.selectedMenuID) { row in
          MenuRowView(row: row)
            .tag(row.id)
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

  var body: some View {
    if let menuID = model.selectedMenuID {
      MenuDetailView(
        model: model,
        recipeModel: recipeModel,
        menuID: menuID,
        onRecipeSelected: onRecipeSelected
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
  @State private var detailModel: MenuDetailModel
  @State private var isShowingRecipeBrowser = false
  @State private var compactChatModel: RecipeChatModel?

  init(
    model: MenuLibraryModel,
    recipeModel: RecipeLibraryModel,
    menuID: CoreMenu.ID,
    onRecipeSelected: ((RecipeDetailPresentation) -> Void)? = nil
  ) {
    self.model = model
    self.recipeModel = recipeModel
    self.onRecipeSelected = onRecipeSelected
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
      if let menu = detailModel.detail?.menu {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            isShowingRecipeBrowser.toggle()
          } label: {
            Label("Browse Recipes", systemImage: "sidebar.right")
          }
          Button {
            chatButtonTapped()
          } label: {
            Label("Chat", systemImage: "sparkles")
          }
          Button {
            model.addItemButtonTapped(menu: menu)
          } label: {
            Label("Add Dish", systemImage: "plus")
          }
          Button {
            model.placeMenuButtonTapped(menu: menu)
          } label: {
            Label("Place", systemImage: "calendar.badge.plus")
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

  private func chatButtonTapped() {
    guard let detail = detailModel.detail else { return }
    if isSplitEnabled {
      chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
    } else {
      compactChatModel = RecipeChatModel(context: .menu(MenuChatContext(detail: detail)))
    }
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
          placements: detail.placements
        )
      }
      .padding()
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
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

private struct MenuDishList: View {
  let model: MenuLibraryModel
  let menu: CoreMenu
  let detail: MenuDetailData
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Dishes")
        .font(.title2.weight(.semibold))

      ForEach(0..<detail.menu.dayCount, id: \.self) { dayOffset in
        MenuDaySection(
          model: model,
          menu: menu,
          dayNumber: dayOffset + 1,
          dayOffset: dayOffset,
          scheduledDate: scheduledDate(for: dayOffset),
          rows: detail.itemRows.filter { $0.item.dayOffset == dayOffset },
          onRecipeSelected: onRecipeSelected
        )
      }
    }
  }

  private var placedStartDate: Date? {
    detail.placements.count == 1 ? detail.placements[0].startDate : nil
  }

  private func scheduledDate(for dayOffset: Int) -> Date? {
    guard let placedStartDate else { return nil }
    return Calendar.autoupdatingCurrent.date(
      byAdding: .day,
      value: dayOffset,
      to: placedStartDate
    )
  }
}

private struct MenuDaySection: View {
  let model: MenuLibraryModel
  let menu: CoreMenu
  let dayNumber: Int
  let dayOffset: Int
  let scheduledDate: Date?
  let rows: [MenuItemRowData]
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        dayTitle
          .font(.headline)
          .foregroundStyle(.secondary)

        Spacer()

        Button {
          model.addItemButtonTapped(
            menu: menu,
            kind: .recipe,
            dayOffset: dayOffset,
            mealSlot: .dinner
          )
        } label: {
          Label("Add Recipe to Day \(dayNumber)", systemImage: "plus.circle")
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Add recipe to Day \(dayNumber)")
      }

      if rows.isEmpty {
        Text("No dishes")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          ForEach(rows) { row in
            MenuDishRowView(row: row, onRecipeSelected: onRecipeSelected)
            if row.id != rows.last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(.quaternary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .dropDestination(for: MenuDraggedRecipe.self) { recipes, _ -> Bool in
      return model.addRecipesToMenu(
        recipeIDs: recipes.map(\.recipeID),
        menuID: menu.id,
        dayOffset: dayOffset,
        mealSlot: .dinner
      )
    }
    .dropDestination(for: MenuDraggedMenuItem.self) { items, _ in
      let sameMenuItems = items.filter { $0.menuID == menu.id }
      guard !sameMenuItems.isEmpty else { return false }
      return sameMenuItems.allSatisfy { item in
        model.moveMenuItem(itemID: item.itemID, toDayOffset: dayOffset)
      }
    }
  }

  private var dayTitle: Text {
    guard let scheduledDate else {
      return Text("Day \(dayNumber)")
    }

    let weekday = scheduledDate.formatted(.dateTime.weekday(.wide))
    let date = scheduledDate.formatted(.dateTime.month(.wide).day().year())
    return Text("\(weekday) - \(date) (Day \(dayNumber))")
  }
}

private struct MenuDishRowView: View {
  let row: MenuItemRowData
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    Group {
      if let recipeID = row.recipe?.id, let onRecipeSelected {
        Button {
          onRecipeSelected(
            RecipeDetailPresentation(
              recipeID: recipeID,
              scaleContext: .menuItem(row.item.id)
            )
          )
        } label: {
          rowContent
        }
        .buttonStyle(.plain)
        .draggable(
          MenuDraggedMenuItem(
            menuID: row.item.menuID,
            itemID: row.item.id
          )
        )
      } else {
        rowContent
      }
    }
  }

  private var rowContent: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: row.item.kind.systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 5) {
        Text(row.displayTitle)
          .font(.headline)
        Label(row.item.mealSlot.title, systemImage: row.item.mealSlot.systemImage)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let notes = row.displayNotes {
          Text(notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()
    }
    .padding(12)
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

private struct MenuDraggedRecipe: Codable, Transferable {
  var recipeID: Recipe.ID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .yesChefMenuRecipe)
  }
}

private struct MenuDraggedMenuItem: Codable, Transferable {
  var menuID: CoreMenu.ID
  var itemID: MenuItem.ID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .yesChefMenuItem)
  }
}

private extension UTType {
  static let yesChefMenuRecipe = UTType(exportedAs: "com.jon.yeschef.menu-recipe")
  static let yesChefMenuItem = UTType(exportedAs: "com.jon.yeschef.menu-item")
}

private struct MenuPlacementList: View {
  let model: MenuLibraryModel
  let menu: CoreMenu
  let placements: [MenuPlacement]

  var body: some View {
    if !placements.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Calendar")
          .font(.title2.weight(.semibold))

        VStack(spacing: 0) {
          ForEach(placements) { placement in
            HStack(spacing: 12) {
              Label {
                Text(placement.startDate, format: .dateTime.weekday(.wide).month(.wide).day())
              } icon: {
                Image(systemName: "calendar.badge.checkmark")
              }

              Spacer()

              Menu {
                Button {
                  model.editPlacementButtonTapped(menu: menu, placement: placement)
                } label: {
                  Label("Change Start Date", systemImage: "calendar")
                }
                Button(role: .destructive) {
                  model.deletePlacementButtonTapped(menu: menu, placement: placement)
                } label: {
                  Label("Remove from Calendar", systemImage: "trash")
                }
              } label: {
                Label("Placement Actions", systemImage: "ellipsis.circle")
                  .labelStyle(.iconOnly)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            if placement.id != placements.last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(.quaternary)
        }
      }
    }
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
    .navigationTitle("Add Dish")
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
      if model.saveRecipeItemButtonTapped(
        menuID: context.menuID,
        recipeID: selectedRecipeID,
        dayOffset: dayOffset,
        mealSlot: mealSlot,
        notes: notes
      ) {
        dismiss()
      }
    case .note, .reservation:
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

  let model: MenuLibraryModel
  let context: MenuPlacementDraftContext

  init(model: MenuLibraryModel, context: MenuPlacementDraftContext) {
    self.model = model
    self.context = context
    _startDate = State(wrappedValue: context.startDate)
  }

  var body: some View {
    Form {
      Section(context.menuTitle) {
        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
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
          if model.savePlacementButtonTapped(context: context, startDate: startDate) {
            dismiss()
          }
        }
      }
    }
  }
}
