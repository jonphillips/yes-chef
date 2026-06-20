import SwiftUI
import YesChefCore

struct MenusStack: View {
  let model: MenuLibraryModel

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.navigationPath) {
      MenuListView(model: model, style: .navigation)
        .navigationDestination(for: CoreMenu.ID.self) { menuID in
          MenuDetailView(model: model, menuID: menuID)
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

  var body: some View {
    if let menuID = model.selectedMenuID {
      MenuDetailView(model: model, menuID: menuID)
        .id(menuID)
    } else {
      ContentUnavailableView("Select a Menu", systemImage: "menucard")
    }
  }
}

struct MenuDetailView: View {
  let model: MenuLibraryModel
  @State private var detailModel: MenuDetailModel

  init(model: MenuLibraryModel, menuID: CoreMenu.ID) {
    self.model = model
    _detailModel = State(wrappedValue: MenuDetailModel(menuID: menuID))
  }

  var body: some View {
    Group {
      if let detail = detailModel.detail {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            MenuDetailHeader(detail: detail)
            MenuDishList(detail: detail)
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
        .navigationTitle(detail.menu.title)
      } else {
        ContentUnavailableView("Menu Not Found", systemImage: "menucard")
      }
    }
    .toolbar {
      if let menu = detailModel.detail?.menu {
        ToolbarItemGroup(placement: .primaryAction) {
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
  }
}

private struct MenuDetailHeader: View {
  let detail: MenuDetailData

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(detail.menu.title)
        .font(.largeTitle.bold())
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
  let detail: MenuDetailData

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Dishes")
        .font(.title2.weight(.semibold))

      if detail.itemRows.isEmpty {
        ContentUnavailableView("No Dishes", systemImage: "fork.knife")
          .frame(maxWidth: .infinity, minHeight: 180)
      } else {
        ForEach(0..<detail.menu.dayCount, id: \.self) { dayOffset in
          MenuDaySection(
            dayNumber: dayOffset + 1,
            scheduledDate: scheduledDate(for: dayOffset),
            rows: detail.itemRows.filter { $0.item.dayOffset == dayOffset }
          )
        }
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
  let dayNumber: Int
  let scheduledDate: Date?
  let rows: [MenuItemRowData]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      dayTitle
        .font(.headline)
        .foregroundStyle(.secondary)

      if rows.isEmpty {
        Text("No dishes")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        VStack(spacing: 0) {
          ForEach(rows) { row in
            MenuDishRowView(row: row)
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

  var body: some View {
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
