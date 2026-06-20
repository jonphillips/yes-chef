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
          }
        }
      case .selection:
        List(model.listRows, selection: $model.selectedListID) { row in
          GroceryListRowView(row: row)
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
              ContentUnavailableView("No Grocery Items", systemImage: "basket")
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
              Label("Add Item", systemImage: "basket.badge.plus")
            }

            GrocerySourceMenu(
              model: model,
              selectedMealRows: selectedMealRows,
              selectedDate: mealCalendarModel.selectedDate
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
        ContentUnavailableView("Groceries", systemImage: "basket")
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

private struct GroceryItemsSection: View {
  let title: String
  let rows: [GroceryItemRowData]
  let model: GroceryLibraryModel

  var body: some View {
    if !rows.isEmpty {
      Section(title) {
        ForEach(rows) { row in
          GroceryItemRowView(row: row) {
            model.togglePurchasedButtonTapped(itemID: row.id)
          }
          .swipeActions {
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
              GrocerySourceLabel(source: source)
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
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

private struct GrocerySourceLabel: View {
  let source: GroceryItemSource

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(source.sourceTitle ?? source.origin.title)
        if let detailText {
          Text(detailText)
        }
      }
    } icon: {
      Image(systemName: source.origin.systemImage)
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

private struct GroceryListRowView: View {
  let row: GroceryListRowData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.list.title)
        .font(.headline)
      HStack(spacing: 10) {
        Label(itemCountTitle, systemImage: "basket")
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
    .navigationTitle("Add Grocery List")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveListButtonTapped(title: title, remindersListName: remindersListName) {
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
    .navigationTitle("Add Grocery Item")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveCustomItemButtonTapped(
            title: title,
            quantityText: quantityText,
            unit: unit,
            aisle: aisle,
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

private extension String {
  var nonEmptyGroceryViewText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
