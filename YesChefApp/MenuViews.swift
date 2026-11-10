import LLMHandoffUI
import SwiftUI
import UniformTypeIdentifiers
import YesChefCore

struct MenuListView: View {
  let model: MenuLibraryModel

  var body: some View {
    @Bindable var model = model

    List(model.menuRows, selection: $model.selectedMenuID) { row in
      MenuRowView(row: row)
        .tag(row.id)
        .swipeActions {
          // The row remains until confirmation; a destructive role can cause an invalid List update.
          Button {
            model.deleteMenuButtonTapped(row)
          } label: {
            Label("Delete", systemImage: "trash")
          }
          .tint(.red)
        }
    }
    .navigationTitle("Menus")
    .toolbar(removing: .sidebarToggle)
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
  let model: MenuLibraryModel
  let recipeModel: RecipeLibraryModel
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var onCookSessionRequested: ((CookSessionPresentation) -> Void)?
  var isFocusActive = false
  var focusButtonTapped: (() -> Void)?
  @State private var detailModel: MenuDetailModel
  @State private var handoffTransport: HandoffInAppTransport

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
    _detailModel = State(wrappedValue: MenuDetailModel(menuID: menuID, toastCenter: model.toastCenter))
    _handoffTransport = State(wrappedValue: HandoffInAppTransport(toastCenter: model.toastCenter))
  }

  var body: some View {
    @Bindable var detailModel = detailModel

    Group {
      if let detail = detailModel.detail {
        MenuDetailReader(
          model: model,
          detailModel: detailModel,
          detail: detail,
          handoffTransport: handoffTransport,
          onRecipeSelected: onRecipeSelected,
          regeneratePrepPlan: regeneratePrepPlan
        )
        .navigationTitle(detail.menu.title)
      } else {
        ContentUnavailableView("Menu Not Found", systemImage: "menucard")
      }
    }
    .overlay(alignment: .trailing) {
      if usesToolOverlay, let tool = detailModel.tool {
        // Keep the menu interactive beneath the panel so recipes can later be
        // dragged from Browse Recipes into a meal. The toolbar toggles dismiss it.
        menuToolContent(
          tool,
          onRecipeSelected: { presentation in
            detailModel.dismissTool()
            onRecipeSelected?(presentation)
          }
        )
        .frame(width: MenuToolOverlayMetrics.idealWidth)
        .frame(maxHeight: .infinity)
        .background(.background)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(width: 1)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.snappy(duration: 0.22), value: detailModel.tool?.id)
    .toolbar {
      if detailModel.detail != nil {
        ToolbarItemGroup(placement: .topBarLeading) {
          if horizontalSizeClass != .compact, let focusButtonTapped {
            FocusToolbarButton(isActive: isFocusActive, action: focusButtonTapped)
          }
        }
        ToolbarItemGroup(placement: .primaryAction) {
          if let cookSessionPresentation {
            Button {
              onCookSessionRequested?(cookSessionPresentation)
            } label: {
              Label("Cook these", systemImage: "flame")
            }
          }
          Button {
            detailModel.recipeBrowserButtonTapped()
          } label: {
            Label("Add Recipes", image: "custom.richtext.page.badge.plus")
          }
          Button {
            if let detail = detailModel.detail { model.editMenuButtonTapped(menu: detail.menu, detail: detail) }
          } label: {
            Label("Edit", systemImage: "square.and.pencil")
          }
          HandoffMenu(
            paste: {
              let results = UIPasteboard.general.string.map { [$0] } ?? []
              Task { await handoffTransport.pastedResultsReceived(results, source: .menu(detailModel.menuID)) }
            },
            isAskActive: isAskActiveBinding
          ) {
            Button("Menu") { Task { await handoffTransport.copyPrompt(for: .menu(detailModel.menuID)) } }
            Button("Fresh prep plan") {
              Task { await handoffTransport.copyPrompt(for: .menu(detailModel.menuID, prepPlanIntent: .regenerate)) }
            }
            Button("Recipe capture request") { handoffTransport.copyRecipeCaptureRequest() }
          }
        }
      }
    }
    .sheet(item: compactTool) { tool in
      NavigationStack {
        menuToolContent(
          tool,
          onRecipeSelected: { presentation in
            detailModel.dismissTool()
            onRecipeSelected?(presentation)
          }
        )
      }
    }
    .sheet(item: $detailModel.noteRecipeReview) { review in
      ChatApplyReviewSheet(
        item: detailModel.reviewItem(for: review),
        isCommitting: detailModel.isPromotingNoteRecipe,
        commit: { approvedText, usingSecondaryCommit in
          do {
            try await detailModel.reviewItem(for: review).commit(
              approvedText,
              usingSecondaryCommit: usingSecondaryCommit
            )
          } catch {
            detailModel.errorMessage = RecipeChatErrorText.describe(error)
            detailModel.isShowingError = true
          }
        },
        discard: detailModel.discardNoteRecipeReview
      )
    }
    .confirmationDialog(
      "Replace the menu note with this recipe?",
      item: $detailModel.noteReplacementOffer,
      titleVisibility: .visible
    ) { offer in
      Button("Replace Note") {
        detailModel.replacePromotedNote(offer)
      }
      Button("Keep Note", role: .cancel) {}
    } message: { offer in
      Text("\(offer.recipeTitle) is now in your library. Replacing keeps this menu item's day and meal; the original note text is saved in the recipe's notes.")
    }
    .alert("Could Not Save Prep Plan", isPresented: $detailModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(detailModel.errorMessage ?? "")
    }
    .alert("Prep Plan", item: $detailModel.information) { _ in
      Button("OK", role: .cancel) {}
    } message: { information in
      Text(information.message)
    }
    .handoffTransportAlert(handoffTransport)
  }

  private var usesToolOverlay: Bool {
    WideLayout.isEnabled(horizontalSizeClass: horizontalSizeClass)
  }

  private var isAskActiveBinding: Binding<Bool> {
    Binding(
      get: { detailModel.chatModel != nil },
      set: { active in
        guard active != (detailModel.chatModel != nil) else { return }
        detailModel.askButtonTapped()
      }
    )
  }

  private var cookSessionPresentation: CookSessionPresentation? {
    detailModel.detail.flatMap(CookSessionPresentation.init(menuDetail:))
  }

  private func regeneratePrepPlan() {
    detailModel.regeneratePrepPlan()
  }

  @ViewBuilder
  private func menuToolContent(
    _ tool: MenuDetailInspector,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void
  ) -> some View {
    switch tool {
    case .recipeBrowser:
      MenuRecipeBrowserPanel(recipeModel: recipeModel, isTinted: usesToolOverlay, onRecipeSelected: onRecipeSelected)
    case let .chat(chatModel):
      RecipeChatPanel(
        chatModel: chatModel,
        surface: .menuTool(
          content: .init(
            applyActions: detailModel.applyActionCatalog(for: chatModel),
            finalization: .menu(
              menuID: detailModel.menuID,
              prepPlanIntent: detailModel.prepPlanHandoffIntent,
              onFinalized: detailModel.onboardPrepPlanFinalized
            ),
            focusesInputOnAppear: detailModel.activeChatStarterID == nil
          ),
          starters: detailModel.chatStarters,
          activeStarterID: detailModel.activeChatStarterID,
          selectStarter: detailModel.selectChatStarter,
          onDismiss: detailModel.dismissTool
        )
      )
    }
  }

  private var compactTool: Binding<MenuDetailInspector?> {
    Binding(
      get: { usesToolOverlay ? nil : detailModel.tool },
      set: { tool in
        guard !usesToolOverlay else { return }
        detailModel.tool = tool
      }
    )
  }
}

private enum MenuToolOverlayMetrics {
  // Retains the previous inspector's ideal width while changing only its
  // presentation from a pushing column to a floating tool.
  static let idealWidth: CGFloat = 380
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
    guard row.item.kind == .recipe, let recipe = row.recipe, !recipe.archived else { return nil }
    self.init(
      recipeID: recipe.id,
      scaleContext: .menuItem(row.item.id),
      title: row.displayTitle
    )
  }
}

struct MenuPrepPlanSection: View {
  let steps: [PrepPlanStepRecord]
  let dayCount: Int
  let placementStartDate: Date?
  let today: Date
  let itemRows: [MenuItemRowData]
  var regeneratePrepPlan: () -> Void
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var clearPrepPlan: () -> Void
  var createStep: (PrepPlanStep) -> Void
  var updateStep: (PrepPlanStep, PrepPlanStepRecord.ID) -> Void
  var deleteStep: (PrepPlanStepRecord.ID) -> Void
  var reorderStep: (PrepPlanStepRecord.ID, MenuItemMoveDirection) -> Void
  var isInitiallyExpanded: Bool
  @State private var expandedSessionIDs: Set<MenuPrepPlanBand.ID> = []
  @State private var editor: PrepPlanStepEditorDraft?
  @State private var expansionOverride: Bool?
  @State private var isClearConfirmationPresented = false

  private var sessionBands: [MenuPrepPlanBand] {
    MenuPrepPlanBanding.bands(
      steps: steps,
      dayCount: dayCount,
      placementStartDate: placementStartDate,
      today: today
    )
  }

  private var isExpanded: Bool {
    expansionOverride ?? isInitiallyExpanded
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Button {
          expansionOverride = !isExpanded
        } label: {
          HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(width: 12)
            Text("Prep Plan")
              .font(.title2.weight(.semibold))
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse Prep Plan" : "Expand Prep Plan")

        Button {
          editor = PrepPlanStepEditorDraft()
        } label: {
          Label("Add Step", systemImage: "plus").labelStyle(.iconOnly)
        }
        .accessibilityLabel("Add Step")
        .buttonStyle(.borderless)

        Spacer()

        Menu {
          Button("Rebuild with Yes Chef…", systemImage: "arrow.clockwise", action: regeneratePrepPlan)
            .disabled(steps.isEmpty)
          Divider()
          Button("Clear Prep Plan", role: .destructive) {
            isClearConfirmationPresented = true
          }
        } label: {
          Label("Prep Plan Actions", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Prep Plan actions")
      }

      if isExpanded {
        if steps.isEmpty {
          Text("No steps yet.")
            .foregroundStyle(.tertiary)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(sessionBands) { band in
              MenuPrepPlanSessionBandView(
                band: band,
                itemRows: itemRows,
                isExpanded: expandedSessionIDs.contains(band.id) || (band.isToday && !expandedSessionIDs.contains("collapsed:\(band.id)")),
                onToggle: {
                  let isExpanded = expandedSessionIDs.contains(band.id)
                    || (band.isToday && !expandedSessionIDs.contains("collapsed:\(band.id)"))
                  if isExpanded {
                    expandedSessionIDs.remove(band.id)
                    if band.isToday { expandedSessionIDs.insert("collapsed:\(band.id)") }
                  } else {
                    expandedSessionIDs.remove("collapsed:\(band.id)")
                    expandedSessionIDs.insert(band.id)
                  }
                },
                onRecipeSelected: onRecipeSelected,
                editStep: { editor = PrepPlanStepEditorDraft(step: $0) },
                deleteStep: deleteStep,
                reorderStep: reorderStep
              )
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .sheet(item: $editor) { draft in
      PrepPlanStepEditorSheet(
        draft: draft,
        itemRows: itemRows,
        dayCount: dayCount,
        placementStartDate: placementStartDate
      ) { savedDraft in
        if let id = savedDraft.stepID {
          updateStep(savedDraft.step, id)
        } else {
          createStep(savedDraft.step)
        }
      }
    }
    .confirmationDialog("Clear Prep Plan?", isPresented: $isClearConfirmationPresented) {
      Button("Clear Prep Plan", role: .destructive) {
        clearPrepPlan()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently removes every step in this prep plan.")
    }
  }

}

private struct MenuPrepPlanSessionBandView: View {
  let band: MenuPrepPlanBand
  let itemRows: [MenuItemRowData]
  let isExpanded: Bool
  var onToggle: () -> Void
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var editStep: (PrepPlanStepRecord) -> Void
  var deleteStep: (PrepPlanStepRecord.ID) -> Void
  var reorderStep: (PrepPlanStepRecord.ID, MenuItemMoveDirection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: onToggle) {
        HStack(spacing: 8) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 12)

          Text(band.title)
            .font(.headline)

          Spacer()

          Text(band.stepCountTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isExpanded ? "Collapse \(band.title)" : "Expand \(band.title)")
      .accessibilityValue(band.stepCountTitle)

      if isExpanded {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(band.steps, id: \.step.id) { presentation in
            if let sessionLabel = presentation.sessionLabel {
              Text(sessionLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            MenuPrepPlanStepView(
              step: presentation.step,
              itemRows: itemRows,
              onRecipeSelected: onRecipeSelected,
              editStep: editStep,
              deleteStep: deleteStep,
              reorderStep: reorderStep
            )

            if presentation.step.id != band.steps.last?.step.id {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
      }
    }
    .padding(.vertical, 8)
  }
}

struct MenuDetailHeader: View {
  let detail: MenuDetailData

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(metadata)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if let notes = detail.menu.notes {
        Text(notes)
          .font(.body)
      }
    }
  }

  private var metadata: String {
    var parts: [String] = []
    if detail.placements.count == 1, let placement = detail.placements.first,
      let endDate = MenuPlacementDay.date(for: detail.menu.dayCount - 1, from: placement)
    {
      let start = placement.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
      let end = endDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
      parts.append("\(start) – \(end)")
    } else if detail.placements.count > 1 {
      parts.append("On the calendar \(detail.placements.count) times")
    }
    parts.append(dayCountTitle)
    parts.append(itemCountTitle)
    return parts.joined(separator: " · ")
  }

  private var dayCountTitle: String {
    detail.menu.dayCount == 1 ? "1 day" : "\(detail.menu.dayCount) days"
  }

  private var itemCountTitle: String {
    detail.itemRows.count == 1 ? "1 dish" : "\(detail.itemRows.count) dishes"
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
      RecipeSearchMatcher.matches(
        query: query,
        in: [row.recipe.title, row.recipe.subtitle, row.recipe.summary]
          .compactMap(\.self) + row.categoryNames
      )
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

struct MenuEditView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: MenuEditDraftContext
  let model: MenuLibraryModel

  init(model: MenuLibraryModel, context: MenuEditDraftContext) {
    self.model = model
    _draft = State(initialValue: context)
  }

  private var canSave: Bool {
    !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section("Menu") {
        StackedTextField(title: "Title", text: $draft.title)
        StackedTextEditor(title: "Notes", text: $draft.notes, minHeight: 100)
      }
      Section("Days") {
        Stepper("Days: \(draft.dayCount)", value: $draft.dayCount, in: draft.minimumDayCount...14)
      }
      Section("Calendar") {
        ForEach($draft.placements) { $placement in
          DatePicker("Start Date", selection: $placement.startDate, displayedComponents: .date)
            .swipeActions(edge: .trailing) {
              if placement.placementID != nil {
                Button(role: .destructive) { remove(placement) } label: {
                  Label("Remove from Calendar", systemImage: "trash")
                }
              }
            }
            .contextMenu {
              if placement.placementID != nil {
                Button(role: .destructive) { remove(placement) } label: {
                  Label("Remove from Calendar", systemImage: "trash")
                }
              }
            }
        }
        Button("Place on Calendar…") {
          draft.placements.append(MenuEditPlacementDraft(startDate: Calendar.autoupdatingCurrent.startOfDay(for: .now)))
        }
        if let bringInOffer = draft.bringInOffer {
          Button {
            // Close the editor before handing control to the existing Bring In confirmation.
            dismiss()
            model.bringInButtonTapped(menuID: draft.menuID, menuTitle: draft.title, offer: bringInOffer)
          } label: {
            Label("Bring In Calendar Items…", image: "custom.menucard.arrow.in")
          }
        }
      }
    }
    .navigationTitle("Edit Menu")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveMenuEditsButtonTapped(context: draft) { dismiss() }
        }
        .disabled(!canSave)
      }
    }
  }

  private func remove(_ placement: MenuEditPlacementDraft) {
    // Removal deliberately abandons unsaved edits, then presents the existing confirmation.
    dismiss()
    model.deletePlacementButtonTapped(menuTitle: draft.title, placement: placement)
  }
}
