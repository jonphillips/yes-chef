import SwiftUI
import UIKit
import YesChefCore

struct MealCalendarStack: View {
  let model: MealCalendarModel
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    NavigationStack {
      MealCalendarPlannerView(
        model: model,
        showsSelectedDayAgenda: true,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
    }
  }
}

struct MealCalendarWorkspaceView: View {
  let model: MealCalendarModel
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width >= 840 && model.displayMode != .day {
        MealCalendarWideWorkspace(
          model: model,
          agendaWidth: agendaWidth(for: geometry.size.width),
          weekCellMinHeight: weekCellHeight(for: geometry.size.height),
          onMenuSelected: onMenuSelected,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      } else {
        MealCalendarStackedContent(
          model: model,
          showsSelectedDayAgenda: true,
          monthCellMinHeight: 104,
          weekCellMinHeight: 260,
          maxContentWidth: 1120,
          onMenuSelected: onMenuSelected,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )
      }
    }
    .navigationTitle("Meal Calendar")
    .toolbar {
      MealCalendarNavigationToolbar(model: model)
    }
  }

  private func agendaWidth(for workspaceWidth: CGFloat) -> CGFloat {
    let baselineWidth = min(max(workspaceWidth * 0.34, 360), 460)
    return baselineWidth * 0.85
  }

  private func weekCellHeight(for workspaceHeight: CGFloat) -> CGFloat {
    min(max(workspaceHeight - 210, 320), 520)
  }
}

struct MealCalendarPlannerView: View {
  let model: MealCalendarModel
  var showsSelectedDayAgenda: Bool
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    MealCalendarStackedContent(
      model: model,
      showsSelectedDayAgenda: showsSelectedDayAgenda,
      monthCellMinHeight: 86,
      weekCellMinHeight: 240,
      maxContentWidth: 980,
      onMenuSelected: onMenuSelected,
      onRecipeSelected: onRecipeSelected,
      onCookSessionRequested: onCookSessionRequested
    )
    .navigationTitle("Meal Calendar")
    .toolbar {
      MealCalendarNavigationToolbar(model: model)
    }
  }
}

private struct MealCalendarWideWorkspace: View {
  let model: MealCalendarModel
  let agendaWidth: CGFloat
  let weekCellMinHeight: CGFloat
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    HStack(spacing: 0) {
      MealCalendarStackedContent(
        model: model,
        showsSelectedDayAgenda: false,
        monthCellMinHeight: 118,
        weekCellMinHeight: weekCellMinHeight,
        maxContentWidth: nil,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      MealCalendarAgendaRail(
        model: model,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
        .frame(width: agendaWidth)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct MealCalendarStackedContent: View {
  let model: MealCalendarModel
  var showsSelectedDayAgenda: Bool
  var monthCellMinHeight: CGFloat
  var weekCellMinHeight: CGFloat
  var maxContentWidth: CGFloat?
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        MealCalendarToolbar(model: model)

        MealCalendarCalendarBody(
          model: model,
          monthCellMinHeight: monthCellMinHeight,
          weekCellMinHeight: weekCellMinHeight,
          onMenuSelected: onMenuSelected,
          onRecipeSelected: onRecipeSelected,
          onCookSessionRequested: onCookSessionRequested
        )

        if showsSelectedDayAgenda, model.displayMode != .day {
          Divider()
          MealCalendarDayAgendaView(
            model: model,
            showsHeader: true,
            allowsChatWorkspace: false,
            onMenuSelected: onMenuSelected,
            onRecipeSelected: onRecipeSelected,
            onCookSessionRequested: onCookSessionRequested
          )
        }
      }
      .padding()
      .frame(maxWidth: maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct MealCalendarCalendarBody: View {
  let model: MealCalendarModel
  var monthCellMinHeight: CGFloat
  var weekCellMinHeight: CGFloat
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    switch model.displayMode {
    case .month:
      MealCalendarMonthGrid(model: model, cellMinHeight: monthCellMinHeight)
    case .week:
      MealCalendarWeekGrid(model: model, cellMinHeight: weekCellMinHeight)
    case .day:
      MealCalendarDayAgendaView(
        model: model,
        showsHeader: true,
        allowsChatWorkspace: true,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
    }
  }
}

private struct MealCalendarAgendaRail: View {
  let model: MealCalendarModel
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?

  var body: some View {
    ScrollView {
      MealCalendarDayAgendaView(
        model: model,
        showsHeader: true,
        allowsChatWorkspace: false,
        onMenuSelected: onMenuSelected,
        onRecipeSelected: onRecipeSelected,
        onCookSessionRequested: onCookSessionRequested
      )
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.background)
  }
}

private struct MealCalendarNavigationToolbar: ToolbarContent {
  let model: MealCalendarModel

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        model.todayButtonTapped()
      } label: {
        Label("Today", systemImage: "calendar.badge.clock")
      }
      Menu {
        Button {
          model.addItemButtonTapped(kind: .recipe)
        } label: {
          Label("Recipe", systemImage: MealPlanItemKind.recipe.systemImage)
        }
        Button {
          model.addItemButtonTapped(kind: .note)
        } label: {
          Label("Note", systemImage: MealPlanItemKind.note.systemImage)
        }
      } label: {
        Label("Add", systemImage: "plus")
      }
    }
  }
}

struct MealCalendarDayAgendaView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage(ChatWorkspaceDetent.storageKey)
  private var chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
  let model: MealCalendarModel
  var showsHeader: Bool
  var allowsChatWorkspace = true
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?
  @State private var compactChatModel: RecipeChatModel?

  private var occupiedMealSlots: [MealPlanItemSlot] {
    MealPlanItemSlot.allCases.filter { !model.rows(on: model.selectedDate, mealSlot: $0).isEmpty }
  }

  var body: some View {
    Group {
      if isSplitEnabled {
        ChatWorkspaceSplit(
          context: mealPlanChatContext,
          detentRaw: $chatWorkspaceDetentRaw,
          applyActions: { chatModel in model.applyActionCatalog(for: chatModel) }
        ) {
          agendaContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .id(chatContextIdentity)
      } else {
        agendaContent
      }
    }
    .sheet(item: $compactChatModel) { chatModel in
      NavigationStack {
        RecipeChatPanel(
          chatModel: chatModel,
          applyActions: model.applyActionCatalog(for: chatModel)
        )
      }
    }
  }

  private var agendaContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      if showsHeader {
        MealCalendarDayHeader(
          model: model,
          cookSession: cookSessionAction,
          chat: chatButtonTapped
        )
      }

      if model.selectedDayRows.isEmpty {
        ContentUnavailableView(
          "No Meals Scheduled",
          systemImage: "calendar.badge.plus",
          description: Text("Add a recipe or note to \(model.selectedDateShortTitle).")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        VStack(alignment: .leading, spacing: 18) {
          ForEach(occupiedMealSlots, id: \.self) { mealSlot in
            MealPlanSlotSection(
              model: model,
              mealSlot: mealSlot,
              rows: model.rows(on: model.selectedDate, mealSlot: mealSlot),
              onMenuSelected: onMenuSelected,
              onRecipeSelected: onRecipeSelected
            )
          }
        }
      }
    }
  }

  private var mealPlanChatContext: RecipeChatContext {
    .mealPlan(
      MealPlanChatContext(
        title: model.selectedDateTitle,
        subjectDate: model.selectedDate,
        rows: model.selectedDayRows
      )
    )
  }

  private var isSplitEnabled: Bool {
    allowsChatWorkspace
      && UIDevice.current.userInterfaceIdiom == .pad
      && horizontalSizeClass != .compact
  }

  private var chatContextIdentity: String {
    String(model.selectedDate.timeIntervalSinceReferenceDate)
  }

  private var cookSessionPresentation: CookSessionPresentation? {
    CookSessionPresentation(plannerTitle: model.selectedDateTitle, rows: model.selectedDayRows)
  }

  private var cookSessionAction: (() -> Void)? {
    guard cookSessionPresentation != nil else { return nil }
    return cookSessionButtonTapped
  }

  private func cookSessionButtonTapped() {
    guard let cookSessionPresentation else { return }
    onCookSessionRequested?(cookSessionPresentation)
  }

  private func chatButtonTapped() {
    if isSplitEnabled {
      chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
    } else {
      compactChatModel = RecipeChatModel(context: mealPlanChatContext)
    }
  }
}

struct MealPlanItemEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var kind: MealPlanItemKind
  @State private var scheduledDate: Date
  @State private var mealSlot: MealPlanItemSlot
  @State private var selectedRecipeIDs: Set<Recipe.ID>
  @State private var noteTitle = ""
  @State private var notes = ""
  @State private var recipeSearchText = ""

  let model: MealCalendarModel
  private let context: MealPlanItemDraftContext

  init(model: MealCalendarModel, context: MealPlanItemDraftContext) {
    self.model = model
    self.context = context
    let initialKind = context.kind == .reservation ? MealPlanItemKind.note : context.kind
    _kind = State(wrappedValue: initialKind)
    _scheduledDate = State(wrappedValue: context.date)
    _mealSlot = State(wrappedValue: context.mealSlot)
    _selectedRecipeIDs = State(wrappedValue: Set([context.recipeID].compactMap(\.self)))
    _noteTitle = State(wrappedValue: context.title)
    _notes = State(wrappedValue: context.notes)
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
      selectedRecipeIDs.isEmpty
    case .note, .reservation:
      noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var allowsMultipleRecipeSelection: Bool {
    !context.isEditing && !context.locksRecipeSelection
  }

  private var selectedRecipeRow: RecipeListRowData? {
    guard let recipeID = context.recipeID else { return nil }
    return model.availableRecipeRows.first { $0.recipe.id == recipeID }
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
        DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)

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
          if context.locksRecipeSelection, let selectedRecipeRow {
            MealPlanRecipeSelectionRow(
              row: selectedRecipeRow,
              isSelected: true,
              allowsMultipleSelection: false
            )
          } else if context.locksRecipeSelection {
            ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife")
          } else if model.availableRecipeRows.isEmpty {
            ContentUnavailableView("No Recipes", systemImage: "book.closed")
          } else {
            StackedTextField(title: "Find Recipes", text: $recipeSearchText)
              .textInputAutocapitalization(.never)

            if filteredRecipeRows.isEmpty {
              ContentUnavailableView.search(text: recipeSearchText)
            } else {
              ForEach(filteredRecipeRows) { row in
                Button {
                  recipeSelectionButtonTapped(row.recipe.id)
                } label: {
                  MealPlanRecipeSelectionRow(
                    row: row,
                    isSelected: selectedRecipeIDs.contains(row.recipe.id),
                    allowsMultipleSelection: allowsMultipleRecipeSelection
                  )
                }
                .foregroundStyle(.primary)
              }
            }
          }
        }

        Section("Notes") {
          StackedTextEditor(
            title: "Serving Notes",
            text: $notes,
            minHeight: 80
          )
        }
      case .note, .reservation:
        Section("Note") {
          StackedTextField(title: "Title", text: $noteTitle, prompt: "Leftovers, guests, prep reminder")
          StackedTextEditor(
            title: "Details",
            text: $notes,
            minHeight: 120
          )
        }
      }
    }
    .navigationTitle(context.isEditing ? "Edit Meal" : "Add Meal")
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
      if context.locksRecipeSelection {
        guard let recipeID = context.recipeID else { return }
        if model.saveRecipeItemButtonTapped(
          recipeID: recipeID,
          date: scheduledDate,
          mealSlot: mealSlot,
          notes: notes
        ) {
          dismiss()
        }
      } else if context.isEditing {
        guard let selectedRecipeID = selectedRecipeIDs.first else { return }
        if model.saveRecipeItemButtonTapped(
          itemID: context.itemID,
          recipeID: selectedRecipeID,
          date: scheduledDate,
          mealSlot: mealSlot,
          notes: notes
        ) {
          dismiss()
        }
      } else {
        if model.saveRecipeItemsButtonTapped(
          recipeIDs: selectedRecipeIDs,
          date: scheduledDate,
          mealSlot: mealSlot,
          notes: notes
        ) {
          dismiss()
        }
      }
    case .note, .reservation:
      if model.saveNoteItemButtonTapped(
        itemID: context.itemID,
        title: noteTitle,
        notes: notes,
        date: scheduledDate,
        mealSlot: mealSlot
      ) {
        dismiss()
      }
    }
  }

  private func recipeSelectionButtonTapped(_ recipeID: Recipe.ID) {
    if allowsMultipleRecipeSelection {
      if selectedRecipeIDs.contains(recipeID) {
        selectedRecipeIDs.remove(recipeID)
      } else {
        selectedRecipeIDs.insert(recipeID)
      }
    } else {
      selectedRecipeIDs = [recipeID]
    }
  }
}

private struct MealCalendarToolbar: View {
  let model: MealCalendarModel

  var body: some View {
    @Bindable var model = model

    VStack(alignment: .leading, spacing: 12) {
      Picker("Calendar View", selection: $model.displayMode) {
        ForEach(MealCalendarDisplayMode.allCases) { mode in
          Text(mode.title)
            .tag(mode)
        }
      }
      .pickerStyle(.segmented)

      HStack(spacing: 12) {
        Button {
          model.previousPeriodButtonTapped()
        } label: {
          Label("Previous", systemImage: "chevron.left")
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Previous \(model.displayMode.title)")

        Text(model.periodTitle)
          .font(.title2.weight(.semibold))
          .frame(maxWidth: .infinity)
          .lineLimit(1)
          .minimumScaleFactor(0.75)

        Button {
          model.nextPeriodButtonTapped()
        } label: {
          Label("Next", systemImage: "chevron.right")
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Next \(model.displayMode.title)")
      }
    }
  }
}

private struct MealCalendarMonthGrid: View {
  let model: MealCalendarModel
  var cellMinHeight: CGFloat

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(minimum: 36), spacing: 6), count: 7)
  }

  var body: some View {
    VStack(spacing: 8) {
      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(model.weekdaySymbols, id: \.self) { weekday in
          Text(weekday)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }

      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(model.visibleMonthSummaries) { summary in
          MealCalendarMonthCell(
            summary: summary,
            isSelected: model.isSelectedDate(summary.date),
            isToday: model.isToday(summary.date),
            minHeight: cellMinHeight
          ) {
            model.selectDateButtonTapped(summary.date)
          }
        }
      }
    }
  }
}

private struct MealCalendarWeekGrid: View {
  let model: MealCalendarModel
  var cellMinHeight: CGFloat

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 7)
  }

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
      ForEach(model.visibleWeekSummaries) { summary in
          MealCalendarWeekCell(
            summary: summary,
            isSelected: model.isSelectedDate(summary.date),
            isToday: model.isToday(summary.date),
            minHeight: cellMinHeight
          ) {
            model.selectDateButtonTapped(summary.date)
          }
      }
    }
  }
}

private struct MealCalendarMonthCell: View {
  let summary: MealCalendarDaySummary
  let isSelected: Bool
  let isToday: Bool
  let minHeight: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(summary.date, format: .dateTime.day())
            .font(.callout.weight(isToday ? .bold : .medium))
            .foregroundStyle(isToday ? Color.accentColor : Color.primary)
          Spacer(minLength: 0)
        }

        ForEach(summary.rows.prefix(3)) { row in
          MealCalendarChip(row: row)
        }

        if summary.rows.count > 3 {
          Text("+\(summary.rows.count - 3) more")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
      }
      .padding(6)
      .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
      .opacity(summary.isInDisplayedMonth ? 1 : 0.42)
      .background(isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(.rect(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: isSelected ? 1.5 : 0.5)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    let mealCount = summary.rows.count == 1 ? "1 item" : "\(summary.rows.count) items"
    return "\(summary.date.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(mealCount)"
  }
}

private struct MealCalendarWeekCell: View {
  let summary: MealCalendarDaySummary
  let isSelected: Bool
  let isToday: Bool
  let minHeight: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(summary.date, format: .dateTime.weekday(.abbreviated))
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(summary.date, format: .dateTime.day())
              .font(.title3.weight(.bold))
              .foregroundStyle(isToday ? Color.accentColor : Color.primary)
          }
          Spacer(minLength: 0)
        }

        if summary.rows.isEmpty {
          Text("Open")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(summary.rows.prefix(5)) { row in
            MealCalendarChip(row: row, titleLineLimit: 3)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(8)
      .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
      .background(isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(.rect(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: isSelected ? 1.5 : 0.5)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct MealCalendarChip: View {
  let row: MealPlanItemRowData
  var titleLineLimit = 1

  var body: some View {
    Label {
      Text(row.displayTitle)
        .lineLimit(titleLineLimit)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: row.isFromMenu ? "menucard" : row.item.kind.systemImage)
    }
    .font(.caption2.weight(.medium))
    .labelStyle(.titleAndIcon)
    .foregroundStyle(.primary)
    .padding(.horizontal, 5)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      row.isFromMenu
        ? Color(uiColor: .tertiarySystemFill)
        : Color.accentColor.opacity(row.item.kind == .recipe ? 0.12 : 0.08)
    )
    .clipShape(.rect(cornerRadius: 5))
  }
}

private struct MealCalendarDayHeader: View {
  let model: MealCalendarModel
  var cookSession: (() -> Void)?
  var chat: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      // Wide: title and all actions on one row.
      HStack(alignment: .firstTextBaseline) {
        titleBlock
        Spacer()
        cookButton
        chatButton
        addMenu
      }
      // Narrow (agenda rail): title, then "Cook these" on its own line, then Chat + Add.
      VStack(alignment: .leading, spacing: 12) {
        titleBlock
        if cookSession != nil {
          cookButton
            .frame(maxWidth: .infinity)
        }
        HStack {
          chatButton
          addMenu
          Spacer()
        }
      }
    }
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.selectedDateTitle)
        .font(.largeTitle.bold())
      Text(itemCountTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var cookButton: some View {
    if let cookSession {
      Button(action: cookSession) {
        Label("Cook these", systemImage: "flame")
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var chatButton: some View {
    Button {
      chat()
    } label: {
      Label("Chat", systemImage: "sparkles")
    }
    .buttonStyle(.bordered)
  }

  private var addMenu: some View {
    Menu {
      Button {
        model.addItemButtonTapped(kind: .recipe)
      } label: {
        Label("Recipe", systemImage: MealPlanItemKind.recipe.systemImage)
      }
      Button {
        model.addItemButtonTapped(kind: .note)
      } label: {
        Label("Add Note", systemImage: MealPlanItemKind.note.systemImage)
      }
    } label: {
      Label("Add", systemImage: "plus")
    }
    .buttonStyle(.borderedProminent)
  }

  private var itemCountTitle: String {
    switch model.selectedDayRows.count {
    case 0: "No items scheduled"
    case 1: "1 item scheduled"
    default: "\(model.selectedDayRows.count) items scheduled"
    }
  }
}

private extension CookSessionPresentation {
  init?(plannerTitle: String, rows: [MealPlanItemRowData]) {
    let items = rows.compactMap(CookSessionItem.init(mealPlanRow:))
    guard !items.isEmpty else { return nil }
    self.init(title: plannerTitle, items: items)
  }
}

private extension CookSessionItem {
  init?(mealPlanRow row: MealPlanItemRowData) {
    guard row.item.kind == .recipe, let recipeID = row.recipe?.id else { return nil }
    self.init(
      recipeID: recipeID,
      scaleContext: row.menuItem.map { .menuItem($0.id) } ?? .mealPlanItem(row.item.id),
      title: row.displayTitle
    )
  }
}

private struct MealPlanSlotSection: View {
  let model: MealCalendarModel
  let mealSlot: MealPlanItemSlot
  let rows: [MealPlanItemRowData]
  var onMenuSelected: ((CoreMenu.ID) -> Void)?
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(mealSlot.title, systemImage: mealSlot.systemImage)
        .font(.title3.weight(.semibold))

      VStack(spacing: 0) {
        ForEach(rows) { row in
          MealPlanItemRowView(
            row: row,
            editAction: row.isFromMenu ? nil : {
              model.editButtonTapped(itemID: row.item.id)
            },
            deleteAction: row.isFromMenu ? nil : {
              model.deleteButtonTapped(itemID: row.item.id)
            },
            sourceAction: sourceAction(for: row),
            primaryAction: recipeAction(for: row)
          )
          if row.id != rows.last?.id {
            Divider()
              .padding(.leading, 72)
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

  private func recipeAction(for row: MealPlanItemRowData) -> (() -> Void)? {
    guard let recipeID = row.recipe?.id, let onRecipeSelected else { return nil }
    return {
      onRecipeSelected(
        RecipeDetailPresentation(
          recipeID: recipeID,
          scaleContext: scaleContext(for: row)
        )
      )
    }
  }

  private func scaleContext(for row: MealPlanItemRowData) -> ScaleContext {
    if let menuItem = row.menuItem {
      return .menuItem(menuItem.id)
    }
    return .mealPlanItem(row.item.id)
  }

  private func sourceAction(for row: MealPlanItemRowData) -> (() -> Void)? {
    guard let menuID = row.menu?.id, let onMenuSelected else { return nil }
    return {
      onMenuSelected(menuID)
    }
  }
}

private struct MealPlanItemRowView: View {
  let row: MealPlanItemRowData
  let editAction: (() -> Void)?
  let deleteAction: (() -> Void)?
  let sourceAction: (() -> Void)?
  let primaryAction: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      rowContent

      Spacer()

      if editAction != nil || deleteAction != nil {
        Menu {
          if let editAction {
            Button(action: editAction) {
              Label("Edit", systemImage: "pencil")
            }
          }
          if let deleteAction {
            Button(role: .destructive, action: deleteAction) {
              Label("Remove", systemImage: "trash")
            }
          }
        } label: {
          Label("Meal Actions", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
        }
      }
    }
    .padding(12)
  }

  @ViewBuilder private var rowContent: some View {
    if let primaryAction {
      Button(action: primaryAction) {
        rowContentLabel
      }
      .buttonStyle(.plain)
    } else {
      rowContentLabel
    }
  }

  private var rowContentLabel: some View {
    HStack(alignment: .top, spacing: 12) {
      MealPlanItemImage(row: row)
        .frame(width: 56, height: 56)

      VStack(alignment: .leading, spacing: 6) {
        Text(row.displayTitle)
          .font(.headline)
        Label(row.item.kind.title, systemImage: row.item.kind.systemImage)
          .font(.caption)
          .foregroundStyle(.secondary)
        if row.isFromMenu {
          menuSourceLabel
        }
        if let notes = row.displayNotes {
          Text(notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder private var menuSourceLabel: some View {
    if let sourceAction {
      Button(action: sourceAction) {
        Label(row.menu?.title ?? "Menu", systemImage: "menucard")
          .lineLimit(1)
      }
      .buttonStyle(.plain)
      .font(.caption)
      .foregroundStyle(.tint)
    } else {
      Label(row.menu?.title ?? "Menu", systemImage: "menucard")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

private struct MealPlanRecipeSelectionRow: View {
  let row: RecipeListRowData
  let isSelected: Bool
  var allowsMultipleSelection = false

  var body: some View {
    HStack(spacing: 12) {
      RecipeThumbnail(data: row.thumbnailData)
        .frame(width: 44, height: 44)

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
        .accessibilityLabel(isSelected ? "Selected" : selectionAccessibilityLabel)
    }
    .padding(.vertical, 4)
  }

  private var selectionAccessibilityLabel: String {
    allowsMultipleSelection ? "Add recipe to selection" : "Select recipe"
  }
}

private struct MealPlanItemImage: View {
  let row: MealPlanItemRowData

  var body: some View {
    if row.item.kind == .recipe {
      RecipeThumbnail(data: row.thumbnailData)
    } else {
      Image(systemName: row.item.kind.systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quinary)
        .clipShape(.rect(cornerRadius: 8))
    }
  }
}

private struct RecipeThumbnail: View {
  let data: Data?

  var body: some View {
    Group {
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "fork.knife")
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.quinary)
      }
    }
    .clipShape(.rect(cornerRadius: 8))
  }
}
