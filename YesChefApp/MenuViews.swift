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
          Button(role: .destructive) {
            model.deleteMenuButtonTapped(row)
          } label: {
            Label("Delete", systemImage: "trash")
          }
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
          isAskActive: isAskActive,
          askButtonTapped: askButtonTapped,
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
            Label("Browse Recipes", systemImage: "book.closed")
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

  private var cookSessionPresentation: CookSessionPresentation? {
    detailModel.detail.flatMap(CookSessionPresentation.init(menuDetail:))
  }

  private var isAskActive: Bool {
    detailModel.chatModel != nil
  }

  private func askButtonTapped() {
    detailModel.askButtonTapped()
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
      MenuRecipeBrowserPanel(recipeModel: recipeModel, onRecipeSelected: onRecipeSelected)
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
  let itemRows: [MenuItemRowData]
  let handoffSource: HandoffExportSource
  let regenerateHandoffSource: HandoffExportSource
  let handoffTransport: HandoffInAppTransport
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var clearPrepPlan: () -> Void
  var createStep: (PrepPlanStep) -> Void
  var updateStep: (PrepPlanStep, PrepPlanStepRecord.ID) -> Void
  var deleteStep: (PrepPlanStepRecord.ID) -> Void
  var reorderStep: (PrepPlanStepRecord.ID, MenuItemMoveDirection) -> Void
  var isInitiallyExpanded: Bool
  @State private var expandedSessionIDs: Set<MenuPrepPlanSessionBand.ID> = []
  @State private var editor: PrepPlanStepEditorDraft?
  @State private var expansionOverride: Bool?
  @State private var isClearConfirmationPresented = false

  private var sessionBands: [MenuPrepPlanSessionBand] {
    MenuPrepPlanSessionBand.grouping(steps)
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

        Spacer()

        Menu {
          Button("Copy Recipe Capture Request") {
            handoffTransport.copyRecipeCaptureRequest()
          }
          Divider()
          Button("Handoff Prep") {
            Task { await handoffTransport.copyPrompt(for: handoffSource) }
          }
          Button("Handoff to Regenerate") {
            Task { await handoffTransport.copyPrompt(for: regenerateHandoffSource) }
          }
          Button("Paste Prep") {
            Task {
              await handoffTransport.pastedResultsReceived(
                [UIPasteboard.general.string ?? ""],
                source: handoffSource
              )
            }
          }
          .disabled(!UIPasteboard.general.hasStrings)
          Divider()
          Button("Clear Prep Plan", role: .destructive) {
            isClearConfirmationPresented = true
          }
          .disabled(steps.isEmpty)
        } label: {
          Label("Prep Plan Actions", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Prep Plan actions")
      }

      if isExpanded {
        HStack {
          Button {
            editor = PrepPlanStepEditorDraft()
          } label: {
            Label("Add Step", systemImage: "plus")
          }
          .buttonStyle(.bordered)
        }

        if steps.isEmpty {
          ContentUnavailableView(
            "No Prep Plan Yet",
            systemImage: "checklist",
            description: Text("Paste a plan grouped under session headers, then refine it with chat.")
          )
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(sessionBands) { band in
              MenuPrepPlanSessionBandView(
                band: band,
                itemRows: itemRows,
                isExpanded: expandedSessionIDs.contains(band.id),
                onToggle: {
                  if expandedSessionIDs.contains(band.id) {
                    expandedSessionIDs.remove(band.id)
                  } else {
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
      PrepPlanStepEditorSheet(draft: draft, itemRows: itemRows) { savedDraft in
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

private struct MenuPrepPlanSessionBand: Identifiable {
  struct Step: Identifiable {
    let id: PrepPlanStepRecord.ID
    let step: PrepPlanStepRecord
  }

  let id: String
  let session: String
  let steps: [Step]

  var stepCountTitle: String {
    steps.count == 1 ? "1 step" : "\(steps.count) steps"
  }

  private var isFlexible: Bool {
    PrepPlanSessionBand(matching: session) == .flexible
  }

  static func grouping(_ planSteps: [PrepPlanStepRecord]) -> [MenuPrepPlanSessionBand] {
    var unprioritizedBands: [(session: String, steps: [PrepPlanStepRecord])] = []
    for step in planSteps {
      if let lastBandIndex = unprioritizedBands.indices.last,
        unprioritizedBands[lastBandIndex].session == step.session
      {
        unprioritizedBands[lastBandIndex].steps.append(step)
      } else {
        unprioritizedBands.append((session: step.session, steps: [step]))
      }
    }

    let bands = unprioritizedBands.enumerated().map { index, band in
      MenuPrepPlanSessionBand(
        id: "\(index):\(band.session)",
        session: band.session,
        steps: Self.displaySteps(for: band.steps, in: band.session)
      )
    }
    return bands.filter(\.isFlexible) + bands.filter { !$0.isFlexible }
  }

  private static func displaySteps(for steps: [PrepPlanStepRecord], in session: String) -> [Step] {
    steps.map { Step(id: $0.id, step: $0) }
  }
}

private struct MenuPrepPlanSessionBandView: View {
  let band: MenuPrepPlanSessionBand
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

          Text(band.session)
            .font(.headline)

          Spacer()

          Text(band.stepCountTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isExpanded ? "Collapse \(band.session)" : "Expand \(band.session)")
      .accessibilityValue(band.stepCountTitle)

      if isExpanded {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(band.steps) { presentation in
            MenuPrepPlanStepView(
              step: presentation.step,
              itemRows: itemRows,
              onRecipeSelected: onRecipeSelected,
              editStep: editStep,
              deleteStep: deleteStep,
              reorderStep: reorderStep
            )

            if presentation.id != band.steps.last?.id {
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

struct MenuExternalProjectField: View {
  let externalProjectName: String?
  let save: (String) -> Void

  @State private var draft: String

  init(externalProjectName: String?, save: @escaping (String) -> Void) {
    self.externalProjectName = externalProjectName
    self.save = save
    _draft = State(wrappedValue: externalProjectName ?? "")
  }

  private var normalizedDraft: String {
    draft.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var normalizedStoredValue: String {
    (externalProjectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      StackedTextField(
        title: "ChatGPT Project",
        text: $draft,
        prompt: "Emerald Isle Beach"
      )
      HStack {
        Text("Reminder of which ChatGPT project to open for this menu — Shortcuts can't pick it for you.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Save Project") {
          save(draft)
        }
        .buttonStyle(.bordered)
        .disabled(normalizedDraft == normalizedStoredValue)
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
