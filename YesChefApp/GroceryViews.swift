import SwiftUI
import YesChefCore

struct GroceriesStack: View {
  let model: GroceryLibraryModel
  let mealCalendarModel: MealCalendarModel

  var body: some View {
    NavigationStack {
      GroceryDetailView(
        model: model,
        mealCalendarModel: mealCalendarModel,
        showsListPicker: true
      )
    }
  }
}

struct GroceryListView: View {
  enum Style {
    case navigation
    case selection
  }

  let model: GroceryLibraryModel
  var style: Style

  var body: some View {
    @Bindable var model = model

    Group {
      switch style {
      case .navigation:
        List {
          ForEach(model.listRows) { row in
            GroceryListRowView(row: row)
              .groceryListManagementActions(row: row, model: model)
          }
        }
      case .selection:
        List(model.listRows, selection: $model.selectedListID) { row in
          GroceryListRowView(row: row)
            .groceryListManagementActions(row: row, model: model)
            .tag(row.id)
        }
      }
    }
    .navigationTitle("Groceries")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.addListButtonTapped()
        } label: {
          Label("Add List", systemImage: "plus")
        }
      }
    }
    .task {
      model.ensureDefaultListIfNeeded()
    }
  }
}

struct GroceryDetailColumn: View {
  let model: GroceryLibraryModel
  let mealCalendarModel: MealCalendarModel

  var body: some View {
    GroceryDetailView(
      model: model,
      mealCalendarModel: mealCalendarModel,
      showsListPicker: false
    )
  }
}

struct GroceryDetailView: View {
  let model: GroceryLibraryModel
  let mealCalendarModel: MealCalendarModel
  var showsListPicker: Bool

  private var selectedMealRows: [MealPlanItemRowData] {
    mealCalendarModel.selectedDayRows.filter { $0.item.kind == .recipe && $0.item.recipeID != nil }
  }

  private var unpurchasedRows: [GroceryItemRowData] {
    model.selectedItemRows.filter { !$0.item.isPurchased }
  }

  private var purchasedRows: [GroceryItemRowData] {
    model.selectedItemRows.filter(\.item.isPurchased)
  }

  var body: some View {
    @Bindable var model = model

    Group {
      if let selectedList = model.selectedListRow {
        List {
          if showsListPicker {
            Section {
              Picker("List", selection: $model.selectedListID) {
                ForEach(model.listRows) { row in
                  Text(row.list.title)
                    .tag(row.id as CoreGroceryList.ID?)
                }
              }
            }
          }

          if model.selectedItemRows.isEmpty {
            Section {
              ContentUnavailableView("No Grocery Items", systemImage: "cart")
                .frame(maxWidth: .infinity, minHeight: 220)
            }
          } else {
            GroceryItemsSection(
              title: "To Buy",
              rows: unpurchasedRows,
              model: model
            )

            if !purchasedRows.isEmpty {
              GroceryItemsSection(
                title: "Purchased",
                rows: purchasedRows,
                model: model
              )
            }
          }
        }
        .navigationTitle(selectedList.list.title)
        .toolbar {
          ToolbarItemGroup(placement: .primaryAction) {
            Button {
              model.addCustomItemButtonTapped()
            } label: {
              Label("Add Item", systemImage: "cart.badge.plus")
            }

            GrocerySourceMenu(
              model: model,
              selectedMealRows: selectedMealRows,
              selectedDate: mealCalendarModel.selectedDate
            )

            GroceryListActionsMenu(
              row: selectedList,
              shareText: model.selectedListShareText,
              purchasedItemCount: purchasedRows.count,
              totalItemCount: model.selectedItemRows.count,
              listCount: model.listRows.count,
              model: model
            )

            if showsListPicker {
              Button {
                model.addListButtonTapped()
              } label: {
                Label("Add List", systemImage: "plus")
              }
            }
          }
        }
      } else {
        ContentUnavailableView("Groceries", systemImage: "cart")
          .navigationTitle("Groceries")
          .toolbar {
            ToolbarItem(placement: .primaryAction) {
              Button {
                model.addListButtonTapped()
              } label: {
                Label("Add List", systemImage: "plus")
              }
            }
          }
      }
    }
    .task {
      model.ensureDefaultListIfNeeded()
    }
  }
}

private struct GrocerySourceMenu: View {
  let model: GroceryLibraryModel
  let selectedMealRows: [MealPlanItemRowData]
  let selectedDate: Date

  var body: some View {
    Menu {
      Button {
        model.addSelectedMealRowsButtonTapped(selectedMealRows)
      } label: {
        Label(selectedDate.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
      }
      .disabled(selectedMealRows.isEmpty)

      if !model.availableMenuRows.isEmpty {
        Section("Menus") {
          ForEach(model.availableMenuRows) { row in
            Button {
              model.addMenuButtonTapped(menuID: row.menu.id)
            } label: {
              Label(row.menu.title, systemImage: "menucard")
            }
          }
        }
      }
    } label: {
      Label("Add Ingredients", systemImage: "text.badge.plus")
    }
  }
}

private struct GroceryListActionsMenu: View {
  let row: GroceryListRowData
  var shareText: String
  var purchasedItemCount: Int
  var totalItemCount: Int
  var listCount: Int
  let model: GroceryLibraryModel

  var body: some View {
    Menu {
      ShareLink(item: shareText, subject: Text(row.list.title)) {
        Label("Share List", systemImage: "square.and.arrow.up")
      }

      Button {
        model.editListButtonTapped(listID: row.id)
      } label: {
        Label("Edit List", systemImage: "pencil")
      }

      if !row.list.isDefault {
        Button {
          model.setPrimaryListButtonTapped(listID: row.id)
        } label: {
          Label("Make Primary", systemImage: "star")
        }
      }

      Section("Clear") {
        Button(role: .destructive) {
          model.clearPurchasedButtonTapped(listID: row.id)
        } label: {
          Label("Clear Purchased", systemImage: "checkmark.circle")
        }
        .disabled(purchasedItemCount == 0)

        Button(role: .destructive) {
          model.clearAllButtonTapped(listID: row.id)
        } label: {
          Label("Clear All", systemImage: "trash")
        }
        .disabled(totalItemCount == 0)
      }

      if listCount > 1 {
        Section {
          Button(role: .destructive) {
            model.deleteListButtonTapped(listID: row.id)
          } label: {
            Label("Delete List", systemImage: "trash")
          }
        }
      }
    } label: {
      Label("List Actions", systemImage: "ellipsis.circle")
    }
  }
}

private struct GroceryItemsSection: View {
  let title: String
  let rows: [GroceryItemRowData]
  let model: GroceryLibraryModel

  var body: some View {
    if !rows.isEmpty {
      Section(title) {
        ForEach(rows) { row in
          GroceryItemRowView(
            row: row,
            togglePurchased: {
              model.togglePurchasedButtonTapped(itemID: row.id)
            },
            deleteItem: {
              model.deleteButtonTapped(itemID: row.id)
            },
            editItem: {
              model.editItemButtonTapped(itemID: row.id)
            },
            deleteSource: { sourceID in
              model.deleteSourceButtonTapped(sourceID: sourceID)
            },
            deleteContribution: { sourceID in
              model.deleteContributionButtonTapped(sourceID: sourceID)
            },
            addToPantry: {
              model.addToPantryButtonTapped(itemID: row.id)
            }
          )
          .swipeActions(edge: .leading) {
            Button {
              model.addToPantryButtonTapped(itemID: row.id)
            } label: {
              Label("Add to Pantry", systemImage: "archivebox")
            }
            .tint(.green)
          }
          .swipeActions {
            Button {
              model.editItemButtonTapped(itemID: row.id)
            } label: {
              Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
              model.deleteButtonTapped(itemID: row.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
  }
}

private struct GroceryItemRowView: View {
  let row: GroceryItemRowData
  var togglePurchased: () -> Void
  var deleteItem: () -> Void
  var editItem: () -> Void
  var deleteSource: (GroceryItemSource.ID) -> Void
  var deleteContribution: (GroceryItemSource.ID) -> Void
  var addToPantry: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button {
        togglePurchased()
      } label: {
        Image(systemName: row.item.isPurchased ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .frame(width: 32, height: 32)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(row.item.isPurchased ? "Mark unpurchased" : "Mark purchased")

      VStack(alignment: .leading, spacing: 6) {
        Text(row.item.title)
          .font(.headline)
          .strikethrough(row.item.isPurchased)
          .foregroundStyle(row.item.isPurchased ? .secondary : .primary)

        if let detailText {
          Text(detailText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if !row.sources.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(row.sources) { source in
              GrocerySourceLabel(source: source) {
                deleteSource(source.id)
              } deleteContribution: {
                deleteContribution(source.id)
              }
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      GroceryItemActionsMenu(
        row: row,
        addToPantry: addToPantry,
        editItem: editItem,
        deleteItem: deleteItem,
        deleteContribution: deleteContribution
      )
    }
    .padding(.vertical, 4)
  }

  private var detailText: String? {
    [
      row.item.quantityText,
      row.item.unit,
      row.item.aisle.map { "· \($0)" },
      row.item.notes.map { "· \($0)" },
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .nonEmptyGroceryViewText
  }
}

private struct GroceryItemActionsMenu: View {
  let row: GroceryItemRowData
  var addToPantry: () -> Void
  var editItem: () -> Void
  var deleteItem: () -> Void
  var deleteContribution: (GroceryItemSource.ID) -> Void

  var body: some View {
    Menu {
      Button {
        editItem()
      } label: {
        Label("Edit Item", systemImage: "pencil")
      }

      Button {
        addToPantry()
      } label: {
        Label("Add to Pantry", systemImage: "archivebox")
      }

      if !removableContributions.isEmpty {
        Section("Remove Contribution") {
          ForEach(removableContributions) { contribution in
            Button(role: .destructive) {
              if let sourceID = contribution.representativeSourceID {
                deleteContribution(sourceID)
              }
            } label: {
              Label(contribution.actionTitle, systemImage: contribution.systemImage)
            }
          }
        }
      }

      Button(role: .destructive) {
        deleteItem()
      } label: {
        Label("Delete Item", systemImage: "trash")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .imageScale(.large)
        .frame(width: 32, height: 32)
    }
    .buttonStyle(.borderless)
    .menuStyle(.button)
    .accessibilityLabel("Grocery Item Actions")
  }

  private var removableContributions: [GrocerySourceContribution] {
    row.sourceContributions
      .filter { $0.removalTitle != nil && $0.representativeSourceID != nil }
  }
}

private struct GrocerySourceLabel: View {
  let source: GroceryItemSource
  var deleteSource: () -> Void
  var deleteContribution: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: source.origin.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 2) {
        Text(source.sourceTitle ?? source.origin.title)
        if let detailText {
          Text(detailText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Menu {
        if let contributionRemovalTitle = source.contributionRemovalTitle {
          Button(role: .destructive) {
            deleteContribution()
          } label: {
            Label(contributionRemovalTitle, systemImage: "minus.square")
          }
        }

        Button(role: .destructive) {
          deleteSource()
        } label: {
          Label("Remove Source", systemImage: "minus.circle")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .imageScale(.medium)
      }
      .buttonStyle(.borderless)
      .menuStyle(.button)
      .accessibilityLabel("Source Actions")
    }
  }

  private var detailText: String? {
    var parts: [String] = []
    if let sourceSubtitle = source.sourceSubtitle,
       sourceSubtitle != source.sourceTitle {
      parts.append(sourceSubtitle)
    }
    if let scheduledDate = source.scheduledDate {
      parts.append(scheduledDate.formatted(.dateTime.month(.abbreviated).day()))
    }
    if let mealSlot = source.mealSlot,
       source.origin != .calendarItem || source.sourceSubtitle == nil {
      parts.append(mealSlot.title)
    }
    return parts.joined(separator: " · ").nonEmptyGroceryViewText
  }
}

private extension GrocerySourceContribution {
  var actionTitle: String {
    guard let source = representativeSource else {
      return removalTitle ?? "Remove Contribution"
    }

    switch source.origin {
    case .custom:
      return removalTitle ?? "Remove Source"
    case .recipe:
      return source.sourceTitle.map { "Remove \($0) Recipe Items" } ?? "Remove Recipe Items"
    case .calendarItem:
      return source.sourceTitle.map { "Remove \($0) Calendar Items" } ?? "Remove Calendar Items"
    case .menu:
      if let dish = source.sourceSubtitle, let menu = source.sourceTitle {
        return "Remove \(dish) from \(menu)"
      }
      return source.sourceTitle.map { "Remove \($0) Menu Dish Items" } ?? "Remove Menu Dish Items"
    case .menuPlacement:
      if let dish = source.sourceSubtitle, let menu = source.sourceTitle {
        return "Remove \(dish) from Placed \(menu)"
      }
      return source.sourceTitle.map { "Remove Placed \($0) Items" } ?? "Remove Placed Dish Items"
    }
  }

  var systemImage: String {
    representativeSource?.origin.systemImage ?? "minus.square"
  }
}

struct PantrySettingsView: View {
  let model: GroceryLibraryModel

  var body: some View {
    List {
      if model.pantryItems.isEmpty {
        Section {
          ContentUnavailableView("No Pantry Items", systemImage: "archivebox")
            .frame(maxWidth: .infinity, minHeight: 220)
        }
      } else {
        Section("Pantry Items") {
          ForEach(model.pantryItems) { item in
            Button {
              model.editPantryItemButtonTapped(itemID: item.id)
            } label: {
              PantryItemRowView(item: item)
            }
            .buttonStyle(.plain)
            .swipeActions {
              Button(role: .destructive) {
                model.deletePantryItemButtonTapped(itemID: item.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
      }
    }
    .navigationTitle("Pantry")
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          model.addPantryItemButtonTapped()
        } label: {
          Label("Add Pantry Item", systemImage: "plus")
        }

        Button {
          model.resetPantryButtonTapped()
        } label: {
          Label("Reset", systemImage: "arrow.counterclockwise")
        }
      }
    }
  }
}

private struct PantryItemRowView: View {
  let item: PantryItem

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(item.title)
        .font(.headline)

      if let notes = item.notes?.nonEmptyGroceryViewText {
        Text(notes)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

enum GroceryPantryStorage {
  static let storageKey = "GroceryPantry.items"
  static let defaultText = GroceryPantryAssumptions.defaultStaples.joined(separator: "\n")

  static func items(from text: String) -> [String] {
    var seen: Set<String> = []
    return text
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { item in
        let key = item.folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: Locale(identifier: "en_US_POSIX")
        )
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
      }
  }
}

private extension View {
  func groceryListManagementActions(
    row: GroceryListRowData,
    model: GroceryLibraryModel
  ) -> some View {
    self
      .swipeActions(edge: .leading) {
        if !row.list.isDefault {
          Button {
            model.setPrimaryListButtonTapped(listID: row.id)
          } label: {
            Label("Make Primary", systemImage: "star")
          }
          .tint(.blue)
        }
      }
      .swipeActions {
        Button {
          model.editListButtonTapped(listID: row.id)
        } label: {
          Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)

        if model.listRows.count > 1 {
          Button(role: .destructive) {
            model.deleteListButtonTapped(listID: row.id)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
  }
}

private struct GroceryListRowView: View {
  let row: GroceryListRowData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.list.title)
        .font(.headline)
      HStack(spacing: 10) {
        if row.list.isDefault {
          Label("Primary", systemImage: "star.fill")
        }
        Label(itemCountTitle, systemImage: "cart")
        if row.remainingItemCount > 0 {
          Label("\(row.remainingItemCount)", systemImage: "circle")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var itemCountTitle: String {
    row.itemCount == 1 ? "1 item" : "\(row.itemCount) items"
  }
}

struct GroceryListEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var remindersListName = ""

  let model: GroceryLibraryModel
  let listID: CoreGroceryList.ID?

  init(model: GroceryLibraryModel, listID: CoreGroceryList.ID? = nil) {
    self.model = model
    self.listID = listID
    let list = listID.flatMap { id in
      model.listRows.first { $0.id == id }?.list
    }
    _title = State(initialValue: list?.title ?? "")
    _remindersListName = State(initialValue: list?.remindersListName ?? "")
  }

  private var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section("List") {
        StackedTextField(title: "Title", text: $title, prompt: "Market run")
        StackedTextField(title: "Reminders List", text: $remindersListName, prompt: "Groceries")
      }
    }
    .navigationTitle(listID == nil ? "Add Grocery List" : "Edit Grocery List")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveListButtonTapped(
            listID: listID,
            title: title,
            remindersListName: remindersListName
          ) {
            dismiss()
          }
        }
        .disabled(isSaveDisabled)
      }
    }
  }
}

struct PantryItemEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var notes = ""

  let model: GroceryLibraryModel
  let itemID: PantryItem.ID?

  init(model: GroceryLibraryModel, itemID: PantryItem.ID? = nil) {
    self.model = model
    self.itemID = itemID
    let item = itemID.flatMap { id in
      model.pantryItems.first { $0.id == id }
    }
    _title = State(initialValue: item?.title ?? "")
    _notes = State(initialValue: item?.notes ?? "")
  }

  private var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section("Pantry Item") {
        StackedTextField(title: "Name", text: $title, prompt: "Sugar")
        StackedTextEditor(title: "Notes", text: $notes, minHeight: 90)
      }
    }
    .navigationTitle(itemID == nil ? "Add Pantry Item" : "Edit Pantry Item")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.savePantryItemButtonTapped(
            itemID: itemID,
            title: title,
            notes: notes
          ) {
            dismiss()
          }
        }
        .disabled(isSaveDisabled)
      }
    }
  }
}

struct GroceryItemEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var quantityText = ""
  @State private var unit = ""
  @State private var aisle = ""
  @State private var notes = ""

  let model: GroceryLibraryModel
  let itemID: GroceryItem.ID?

  init(model: GroceryLibraryModel, itemID: GroceryItem.ID? = nil) {
    self.model = model
    self.itemID = itemID
    let item = itemID.flatMap { id in
      model.itemRows.first { $0.id == id }?.item
    }
    _title = State(initialValue: item?.title ?? "")
    _quantityText = State(initialValue: item?.quantityText ?? "")
    _unit = State(initialValue: item?.unit ?? "")
    _aisle = State(initialValue: item?.aisle ?? "")
    _notes = State(initialValue: item?.notes ?? "")
  }

  private var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section("Item") {
        StackedTextField(title: "Name", text: $title, prompt: "Milk")
        StackedTextField(title: "Quantity", text: $quantityText, prompt: "2")
        StackedTextField(title: "Unit", text: $unit, prompt: "cups")
        StackedTextField(title: "Aisle", text: $aisle, prompt: "Dairy")
        StackedTextEditor(title: "Notes", text: $notes, minHeight: 90)
      }
    }
    .navigationTitle(itemID == nil ? "Add Grocery Item" : "Edit Grocery Item")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          let didSave = if let itemID {
            model.saveItemButtonTapped(
              itemID: itemID,
              title: title,
              quantityText: quantityText,
              unit: unit,
              aisle: aisle,
              notes: notes
            )
          } else {
            model.saveCustomItemButtonTapped(
              title: title,
              quantityText: quantityText,
              unit: unit,
              aisle: aisle,
              notes: notes
            )
          }
          if didSave {
            dismiss()
          }
        }
        .disabled(isSaveDisabled)
      }
    }
  }
}

struct GroceryIngredientSelectionView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selectedIngredientLineIDs: Set<IngredientLine.ID>

  let model: GroceryLibraryModel
  let context: GroceryIngredientSelectionContext
  let choices: [GroceryIngredientChoice]
  let mealRows: [MealPlanItemRowData]
  let pantryStaples: [String]

  init(
    model: GroceryLibraryModel,
    context: GroceryIngredientSelectionContext,
    choices: [GroceryIngredientChoice],
    mealRows: [MealPlanItemRowData],
    pantryStaples: [String]
  ) {
    self.model = model
    self.context = context
    self.choices = choices
    self.mealRows = mealRows
    self.pantryStaples = pantryStaples
    _selectedIngredientLineIDs = State(
      initialValue: Set(
        choices
          .filter { !$0.isAssumedPantryStaple(pantryStaples: pantryStaples) }
          .map(\.line.id)
      )
    )
  }

  private var isAddDisabled: Bool {
    selectedIngredientLineIDs.isEmpty
  }

  var body: some View {
    List {
      if choices.isEmpty {
        Section {
          ContentUnavailableView("No Shoppable Ingredients", systemImage: "cart")
            .frame(maxWidth: .infinity, minHeight: 220)
        }
      } else {
        if !regularChoices.isEmpty {
          GroceryIngredientChoiceSection(
            title: "Ingredients",
            choices: regularChoices,
            selectedIngredientLineIDs: $selectedIngredientLineIDs,
            showsRecipeTitle: showsRecipeTitle
          )
        }

        if !pantryStapleChoices.isEmpty {
          GroceryIngredientChoiceSection(
            title: "Skipped Pantry Staples",
            choices: pantryStapleChoices,
            selectedIngredientLineIDs: $selectedIngredientLineIDs,
            showsRecipeTitle: showsRecipeTitle
          )
        }
      }
    }
    .navigationTitle(context.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Add") {
          if model.confirmIngredientSelectionButtonTapped(
            context: context,
            selectedIngredientLineIDs: selectedIngredientLineIDs,
            mealRows: mealRows
          ) {
            dismiss()
          }
        }
        .disabled(isAddDisabled)
      }
      if !choices.isEmpty {
        ToolbarItem(placement: .secondaryAction) {
          Button(selectionToggleTitle) {
            selectionToggleButtonTapped()
          }
        }
      }
    }
  }

  private var showsRecipeTitle: Bool {
    Set(choices.map(\.recipe.id)).count > 1
  }

  private var regularChoices: [GroceryIngredientChoice] {
    choices.filter { !$0.isAssumedPantryStaple(pantryStaples: pantryStaples) }
  }

  private var pantryStapleChoices: [GroceryIngredientChoice] {
    choices.filter { $0.isAssumedPantryStaple(pantryStaples: pantryStaples) }
  }

  private var selectionToggleTitle: String {
    selectedIngredientLineIDs.count == choices.count ? "Clear" : "All"
  }

  private func selectionToggleButtonTapped() {
    if selectedIngredientLineIDs.count == choices.count {
      selectedIngredientLineIDs.removeAll()
    } else {
      selectedIngredientLineIDs = Set(choices.map(\.line.id))
    }
  }
}

private struct GroceryIngredientChoiceSection: View {
  let title: String
  let choices: [GroceryIngredientChoice]
  @Binding var selectedIngredientLineIDs: Set<IngredientLine.ID>
  var showsRecipeTitle: Bool

  var body: some View {
    Section(title) {
      ForEach(choices) { choice in
        Button {
          toggle(choice.line.id)
        } label: {
          GroceryIngredientChoiceRow(
            choice: choice,
            isSelected: selectedIngredientLineIDs.contains(choice.line.id),
            showsRecipeTitle: showsRecipeTitle
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func toggle(_ lineID: IngredientLine.ID) {
    if selectedIngredientLineIDs.contains(lineID) {
      selectedIngredientLineIDs.remove(lineID)
    } else {
      selectedIngredientLineIDs.insert(lineID)
    }
  }
}

private struct GroceryIngredientChoiceRow: View {
  let choice: GroceryIngredientChoice
  var isSelected: Bool
  var showsRecipeTitle: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(choice.line.originalText)
          .foregroundStyle(.primary)

        if let detailText {
          Text(detailText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var detailText: String? {
    var parts: [String] = []
    if showsRecipeTitle {
      parts.append(choice.recipe.title)
    }
    if let sectionName = choice.section.name?.nonEmptyGroceryViewText {
      parts.append(sectionName)
    }
    if let item = choice.line.item?.nonEmptyGroceryViewText,
       item != choice.line.originalText {
      parts.append(item)
    }
    return parts.joined(separator: " · ").nonEmptyGroceryViewText
  }
}

private extension String {
  var nonEmptyGroceryViewText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
