import LLMClientKit
import SwiftUI
import YesChefCore

struct WorkbenchListView: View {
  enum Style {
    case navigation
    case selection
  }

  let model: WorkbenchLibraryModel
  var style: Style
  @State private var selectedFilter: WorkbenchListFilter = .active
  @State private var completedSearchText = ""

  var body: some View {
    @Bindable var model = model

    Group {
      switch style {
      case .navigation:
        List {
          ForEach(workbenchRows(for: model)) { row in
            NavigationLink(value: row.id) {
              WorkbenchRowView(row: row)
            }
            .workbenchSwipeActions(row, model: model)
          }
        }
      case .selection:
        List(workbenchRows(for: model), selection: $model.selectedWorkbenchID) { row in
          WorkbenchRowView(row: row)
            .tag(row.id)
            .workbenchSwipeActions(row, model: model)
        }
      }
    }
    .navigationTitle("Workbenches")
    .safeAreaInset(edge: .top) {
      VStack(spacing: 8) {
        Picker("Workbench status", selection: $selectedFilter) {
          Text("Active").tag(WorkbenchListFilter.active)
          Text("Completed").tag(WorkbenchListFilter.completed)
        }
        .pickerStyle(.segmented)
      }
      .padding(.horizontal)
      .padding(.top, 8)
      .padding(.bottom, 4)
      .background(.bar)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.addWorkbenchButtonTapped()
        } label: {
          Label("Add Workbench", systemImage: "plus")
        }
      }
    }
    .completedWorkbenchSearch(isEnabled: selectedFilter == .completed, text: $completedSearchText)
  }

  private func workbenchRows(for model: WorkbenchLibraryModel) -> [WorkbenchRowData] {
    let rows = model.workbenchList.rows(for: selectedFilter)
    guard selectedFilter == .completed else { return rows }
    let query = completedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return rows }
    return rows.filter {
      $0.workbench.title.localizedCaseInsensitiveContains(query)
        || ($0.workbench.notes?.localizedCaseInsensitiveContains(query) ?? false)
    }
  }
}

private extension View {
  func workbenchSwipeActions(_ row: WorkbenchRowData, model: WorkbenchLibraryModel) -> some View {
    swipeActions {
      if row.workbench.dateCompleted == nil {
        Button {
          model.markWorkbenchCompletedButtonTapped(row)
        } label: {
          Label("Mark Completed", systemImage: "checkmark.circle")
        }
        .tint(.green)
      } else {
        Button {
          model.markWorkbenchActiveButtonTapped(row)
        } label: {
          Label("Mark Active", systemImage: "arrow.uturn.backward.circle")
        }
        .tint(.blue)
      }
      Button(role: .destructive) {
        model.deleteWorkbenchButtonTapped(row)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }
}

private struct WorkbenchRowView: View {
  let row: WorkbenchRowData

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.workbench.title)
        .font(.headline)
      HStack(spacing: 10) {
        Label(candidateCountTitle, systemImage: "list.bullet.rectangle")
        Text(row.workbench.dateModified, format: .dateTime.month(.abbreviated).day().year())
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private var candidateCountTitle: String {
    row.candidateCount == 1 ? "1 candidate" : "\(row.candidateCount) candidates"
  }
}

struct WorkbenchDetailColumn: View {
  let model: WorkbenchLibraryModel
  var onRecipeSelected: (RecipeDetailPresentation) -> Void = { _ in }
  var isFocusActive = false
  var focusButtonTapped: (() -> Void)?

  var body: some View {
    if let workbenchID = model.selectedWorkbenchID {
      WorkbenchDetailView(
        workbenchID: workbenchID,
        onRecipeSelected: onRecipeSelected,
        isFocusActive: isFocusActive,
        focusButtonTapped: focusButtonTapped
      )
        .id(workbenchID)
    } else {
      ContentUnavailableView("Select a Workbench", systemImage: "hammer")
    }
  }
}

struct WorkbenchDetailView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var model: WorkbenchDetailModel
  @State private var compareTier: ModelTier = .onDevice
  @State private var handoffTransport: HandoffInAppTransport
  @State private var toastCenter: AppToastCenter
  let isFocusActive: Bool
  let focusButtonTapped: (() -> Void)?

  init(
    workbenchID: Workbench.ID,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void = { _ in },
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil
  ) {
    let toastCenter = AppToastCenter()
    _toastCenter = State(wrappedValue: toastCenter)
    _handoffTransport = State(wrappedValue: HandoffInAppTransport(toastCenter: toastCenter))
    _model = State(
      wrappedValue: WorkbenchDetailModel(
        workbenchID: workbenchID,
        openRecipe: { recipeID in
          onRecipeSelected(RecipeDetailPresentation(recipeID: recipeID, workbenchID: workbenchID))
        },
        toastCenter: toastCenter
      )
    )
    self.isFocusActive = isFocusActive
    self.focusButtonTapped = focusButtonTapped
  }

  var body: some View {
    @Bindable var model = model

    Group {
      if let detail = model.detail {
        Group {
          if isSplitEnabled, let chatContext = model.chatContext {
            ChatWorkspaceSplit(
              context: .workbench(chatContext),
              detentIdentity: .workbenchDetail,
              activeTierChanged: { compareTier = $0 },
              applyActions: { chatModel in
                model.applyActionCatalog(for: chatModel)
              }
            ) {
              WorkbenchReader(
                model: model,
                detail: detail,
                handoffTransport: handoffTransport,
                compareButtonTapped: {
                  await openCompare(detail: detail)
                }
              )
            }
          } else {
            WorkbenchReader(
              model: model,
              detail: detail,
              handoffTransport: handoffTransport,
              compareButtonTapped: {
                await openCompare(detail: detail)
              }
            )
          }
        }
        .navigationTitle(detail.workbench.title)
      } else {
        ContentUnavailableView("Workbench Not Found", systemImage: "hammer")
      }
    }
    // Keyed on both inputs: the split turning on (a size-class change on iPad) needs the first load, and
    // every workbench write bumps `dateModified`, which is what keeps `ChatWorkspaceSplit`'s live
    // `onChange(of: context)` firing without a standing full-extract fetch.
    .task(id: isSplitEnabled ? model.detail?.workbench.dateModified : nil) {
      if isSplitEnabled {
        _ = await model.loadChatContext()
      }
    }
    .toolbar {
      if model.detail != nil {
        ToolbarItemGroup(placement: .topBarLeading) {
          if horizontalSizeClass != .compact, let focusButtonTapped {
            FocusToolbarButton(isActive: isFocusActive, action: focusButtonTapped)
          }
        }
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            model.addCandidatesButtonTapped()
          } label: {
            Label("Add Candidates", systemImage: "plus")
          }
          if !isSplitEnabled {
            Button {
              model.chatButtonTapped()
            } label: {
              Label("Chat", systemImage: "sparkles")
            }
          }
        }
      }
    }
    .sheet(isPresented: $model.destination.addCandidates) {
      NavigationStack {
        WorkbenchCandidatePickerView(model: model)
      }
    }
    .sheet(isPresented: $model.destination.candidatePhotoPicker) {
      NavigationStack {
        WorkbenchCandidatePhotoPickerView(model: model)
      }
    }
    .sheet(item: $model.destination.chat) { chatModel in
      NavigationStack {
        RecipeChatPanel(
          chatModel: chatModel,
          surface: .workbenchCompactSheet(
            content: .init(applyActions: model.applyActionCatalog(for: chatModel)),
            onDismiss: { model.destination = nil }
          )
        )
      }
    }
    .sheet(item: $model.destination.logEntryEditor) { editorState in
      NavigationStack {
        WorkbenchLogEntryEditorView(model: model, editorState: editorState)
      }
    }
    .sheet(item: $model.destination.referenceEditor) { editorState in
      NavigationStack {
        WorkbenchReferenceEditorView(model: model, editorState: editorState)
      }
    }
    .alert("Workbench Error", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .handoffTransportAlert(handoffTransport)
    .confirmationDialog(
      "Move all candidates to Reference?",
      isPresented: $model.destination.moveCandidatesToReference,
      titleVisibility: .visible
    ) {
      Button("Move to Reference") {
        model.confirmMoveAllCandidatesToReferenceButtonTapped()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This places the candidate recipes in Reference and removes them from this workbench.")
    }
    .confirmationDialog(
      model.workingRecipeIsPromoted ? "Remove Working Recipe?" : "Delete Working Recipe?",
      isPresented: $model.isConfirmingRemoveWorkingRecipe,
      titleVisibility: .visible
    ) {
      Button(
        model.workingRecipeIsPromoted ? "Remove from Workbench" : "Delete Draft",
        role: .destructive
      ) {
        model.confirmRemoveWorkingRecipe()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        model.workingRecipeIsPromoted
          ? "This detaches the recipe from this workbench so you can draft a new one. The recipe stays in your library."
          : "This deletes the draft working recipe so you can draft a new one. This can't be undone."
      )
    }
    // Full-screen focus cover on regular-width iPad (no third pane — the chat split owns the detail);
    // a sheet on compact iPhone. Same responsive Compare view either way.
    .fullScreenCover(
      isPresented: isRegularWidth ? $model.isShowingCompare : .constant(false)
    ) {
      compareCover
    }
    .sheet(
      isPresented: isRegularWidth ? .constant(false) : $model.isShowingCompare
    ) {
      compareCover
    }
    // The workbench is itself presented as a sheet, so it needs its own toast host — an overlay
    // mounted by a presenting view does not draw over the sheet it presents.
    .overlay(alignment: .top) {
      AppToastOverlay(toastCenter: toastCenter)
        .ignoresSafeArea(.keyboard)
    }
    .sensoryFeedback(.success, trigger: toastCenter.feedbackTrigger)
  }

  @ViewBuilder private var compareCover: some View {
    if let detail = model.detail {
      if isRegularWidth, let chatContext = model.chatContext {
        ChatWorkspaceSplit(
          context: .workbench(chatContext),
          detentIdentity: .workbenchCompare,
          activeTierChanged: { compareTier = $0 },
          applyActions: { chatModel in
            model.applyActionCatalog(for: chatModel)
          }
        ) {
          WorkbenchCompareView(
            detail: detail,
            alignmentModel: model.compareAlignmentModel,
            tier: compareTier
          )
        }
      } else {
        WorkbenchCompareView(
          detail: detail,
          alignmentModel: model.compareAlignmentModel,
          tier: compareTier,
          compactChatContext: model.chatContext.map { .workbench($0) },
          compactChatActiveTierChanged: { compareTier = $0 },
          compactApplyActions: { chatModel in
            model.applyActionCatalog(for: chatModel)
          }
        )
      }
    }
  }

  private func openCompare(detail: WorkbenchDetailData) async {
    await model.compareAlignmentModel.prefetchDiskIfNeeded(
      working: detail.draftRecipeDetail,
      candidates: detail.candidateRows.compactMap(\.recipeDetail)
    )
    _ = await model.loadChatContext()
    model.compareButtonTapped()
  }

  private var isRegularWidth: Bool {
    horizontalSizeClass != .compact
  }

  private var isSplitEnabled: Bool {
    WideLayout.isEnabled(horizontalSizeClass: horizontalSizeClass)
  }
}

private struct WorkbenchReader: View {
  private enum FocusedField: Hashable {
    case title
    case notes
  }

  let model: WorkbenchDetailModel
  let detail: WorkbenchDetailData
  let handoffTransport: HandoffInAppTransport
  let compareButtonTapped: () async -> Void

  @State private var titleText = ""
  @State private var notesText = ""
  @State private var lastGoodTitle = ""
  @State private var lastSavedNotes: String?
  @State private var titleSaveTask: Task<Void, Never>?
  @State private var notesSaveTask: Task<Void, Never>?
  @FocusState private var focusedField: FocusedField?

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          StackedFormField(title: "Title") {
            TextField("Title", text: $titleText)
              .focused($focusedField, equals: .title)
          }
            .font(.title2.weight(.semibold))
          StackedFormField(title: "Notes") {
            TextEditor(text: $notesText)
              .focused($focusedField, equals: .notes)
              .frame(minHeight: 80)
              .overlay(alignment: .topLeading) {
                if notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text("Notes")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                }
              }
          }
        }
        .padding(.vertical, 4)
      }

      Section {
        if let draftRecipe = detail.draftRecipeDetail?.recipe {
          WorkingRecipeRow(
            recipe: draftRecipe,
            open: {
              model.openWorkingRecipeButtonTapped()
            },
            promote: {
              model.promoteWorkingRecipeButtonTapped()
            },
            remove: {
              model.removeWorkingRecipeButtonTapped()
            },
            choosePhoto: model.candidatePhotoPickerButtonTapped,
            canChoosePhoto: !model.candidatePhotoChoices.isEmpty
          )
        } else {
          ContentUnavailableView("No Working Recipe", systemImage: "doc.badge.plus")
            .frame(maxWidth: .infinity, minHeight: 160)
        }
      } header: {
        Text("Working Recipe")
      }

      Section {
        if detail.logEntries.isEmpty {
          ContentUnavailableView("No Log Entries", systemImage: "text.badge.plus")
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
          ForEach(detail.logEntries) { entry in
            Button {
              model.editLogEntryButtonTapped(entry)
            } label: {
              WorkbenchLogEntryRow(entry: entry)
            }
            .buttonStyle(.plain)
          }
          .onDelete { offsets in
            for offset in offsets {
              guard detail.logEntries.indices.contains(offset) else { continue }
              model.deleteLogEntryButtonTapped(entryID: detail.logEntries[offset].id)
            }
          }
        }
      } header: {
        HStack {
          Text("Workbench Log")
          Spacer()
          Button {
            model.addLogEntryButtonTapped()
          } label: {
            Label("Add Log Entry", systemImage: "plus")
              .labelStyle(.iconOnly)
          }
          .accessibilityLabel(Text("Add log entry"))
        }
      } footer: {
        VStack(alignment: .leading, spacing: 8) {
          Text("Develop experiments externally, then review each proposed hypothesis, change, and rationale before it reaches the workbench log.")
          HandoffCopyPasteControls(
            source: .workbench(detail.workbench.id, task: .experiments),
            transport: handoffTransport
          )
          .buttonStyle(.bordered)
        }
      }

      Section {
        if model.referenceRows.isEmpty {
          ContentUnavailableView("No Reference Material", systemImage: "doc.text.magnifyingglass")
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
          ForEach(model.referenceRows) { reference in
            WorkbenchReferenceRow(model: model, reference: reference)
          }
          .onDelete { offsets in
            for offset in offsets {
              guard model.referenceRows.indices.contains(offset) else { continue }
              model.deleteReferenceButtonTapped(referenceID: model.referenceRows[offset].id)
            }
          }
        }
      } header: {
        HStack {
          Text("Reference Material")
          Spacer()
          Button {
            model.addReferenceButtonTapped()
          } label: {
            Label("Add Reference", systemImage: "plus")
              .labelStyle(.iconOnly)
          }
          .accessibilityLabel(Text("Add reference material"))
        }
      } footer: {
        Text("Reference extracts are untrusted source data for the workbench discussion, never instructions.")
      }

      Section {
        if detail.candidateRows.isEmpty {
          ContentUnavailableView("No Candidates", systemImage: "list.bullet.rectangle")
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
          ForEach(detail.candidateRows) { row in
            WorkbenchCandidateRow(model: model, row: row)
          }
          .onDelete { offsets in
            for offset in offsets {
              guard detail.candidateRows.indices.contains(offset) else { continue }
              model.deleteCandidateButtonTapped(candidateID: detail.candidateRows[offset].id)
            }
          }
        }
      } header: {
        HStack {
          Text("Candidates")
          Spacer()
          if !detail.candidateRows.isEmpty {
            Button {
              model.moveAllCandidatesToReferenceButtonTapped()
            } label: {
              Label("Move to Reference", systemImage: "books.vertical")
            }
          }
          Button {
            Task {
              await compareButtonTapped()
            }
          } label: {
            Label("Compare", systemImage: "square.split.2x2")
          }
          .disabled(!model.canCompare)
        }
      } footer: {
        VStack(alignment: .leading, spacing: 8) {
          Text("Discuss a candidate comparison externally, then review what returns before it reaches the workbench log.")
          HandoffCopyPasteControls(
            source: .workbench(detail.workbench.id, task: .compare),
            transport: handoffTransport
          )
          .buttonStyle(.bordered)
        }
      }
    }
    .onAppear {
      titleText = detail.workbench.title
      notesText = detail.workbench.notes ?? ""
      lastGoodTitle = detail.workbench.title
      lastSavedNotes = detail.workbench.notes
    }
    .onChange(of: detail.workbench.title) { _, title in
      if focusedField != .title { titleText = title }
      lastGoodTitle = title
    }
    .onChange(of: detail.workbench.notes) { _, notes in
      if focusedField != .notes { notesText = notes ?? "" }
      lastSavedNotes = notes
    }
    .onChange(of: titleText) {
      scheduleTitleSave()
    }
    .onChange(of: notesText) {
      scheduleNotesSave()
    }
    .onChange(of: focusedField) { oldField, newField in
      if oldField == .title, newField != .title { commitTitleOnBlur() }
      if oldField == .notes, newField != .notes { commitNotesOnBlur() }
    }
    .onDisappear {
      titleSaveTask?.cancel()
      notesSaveTask?.cancel()
      commitTitleOnBlur()
      commitNotesOnBlur()
    }
  }

  private func scheduleTitleSave() {
    titleSaveTask?.cancel()
    titleSaveTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
      guard !Task.isCancelled else { return }
      persistTitleDraft()
    }
  }

  private func scheduleNotesSave() {
    notesSaveTask?.cancel()
    notesSaveTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
      guard !Task.isCancelled else { return }
      persistNotesDraft()
    }
  }

  private func persistTitleDraft() {
    guard let title = WorkbenchInlineEditor.titleToPersist(draft: titleText), title != lastGoodTitle else { return }
    if model.saveTitleButtonTapped(title) {
      lastGoodTitle = title
    }
  }

  private func commitTitleOnBlur() {
    let title = WorkbenchInlineEditor.titleForCommit(draft: titleText, lastGoodTitle: lastGoodTitle)
    guard title != lastGoodTitle else {
      titleText = title
      return
    }
    titleText = title
    if model.saveTitleButtonTapped(title) {
      lastGoodTitle = title
    }
  }

  private func persistNotesDraft() {
    let notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedNotes = notes.isEmpty ? nil : notes
    guard normalizedNotes != lastSavedNotes else { return }
    if model.saveNotesButtonTapped(notesText) { lastSavedNotes = normalizedNotes }
  }

  private func commitNotesOnBlur() {
    notesText = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
    persistNotesDraft()
  }
}

private struct WorkbenchLogEntryRow: View {
  let entry: WorkbenchLogEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(entry.kind.title, systemImage: entry.kind.systemImage)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text(entry.dateCreated, format: .dateTime.month(.abbreviated).day().year().hour().minute())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let hypothesis = entry.hypothesis,
         let change = entry.change,
         let rationale = entry.rationale
      {
        WorkbenchExperimentFields(
          hypothesis: hypothesis,
          change: change,
          rationale: rationale
        )
      } else {
        Text(entry.body)
          .font(.body)
          .foregroundStyle(.primary)
      }
      if let outcome = entry.outcome {
        VStack(alignment: .leading, spacing: 3) {
          Text("Outcome")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Text(outcome)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

private struct WorkbenchExperimentFields: View {
  let hypothesis: String
  let change: String
  let rationale: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      field("Hypothesis", text: hypothesis)
      field("Change", text: change)
      field("Rationale", text: rationale)
    }
  }

  private func field(_ title: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Text(text)
        .font(.body)
        .foregroundStyle(.primary)
    }
  }
}

private struct WorkingRecipeRow: View {
  let recipe: Recipe
  let open: () -> Void
  let promote: () -> Void
  let remove: () -> Void
  let choosePhoto: () -> Void
  let canChoosePhoto: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(recipe.title)
          .font(.headline)
        if let summary = recipe.summary {
          Text(summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
        if recipe.libraryPlacement == .reference {
          Label("Reference", systemImage: "books.vertical")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if canChoosePhoto {
        Button {
          choosePhoto()
        } label: {
          Label("Choose Candidate Photo", systemImage: "photo.badge.checkmark")
        }
        .buttonStyle(.bordered)
      }
      HStack {
        Button {
          open()
        } label: {
          Label("Open", systemImage: "doc.text")
        }
        .buttonStyle(.bordered)

        if recipe.libraryPlacement != .main {
          Button {
            promote()
          } label: {
            Label("Promote to Library", systemImage: "arrow.up.forward.app")
          }
          .buttonStyle(.borderedProminent)
        }

        Spacer(minLength: 8)

        Button(role: .destructive) {
          remove()
        } label: {
          Label("Remove", systemImage: "trash")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel(Text("Remove working recipe"))
      }
    }
    .padding(.vertical, 4)
  }
}

private struct WorkbenchLogEntryEditorView: View {
  @Environment(\.dismiss) private var dismiss
  let model: WorkbenchDetailModel
  @State private var editorState: WorkbenchLogEntryEditorState

  init(model: WorkbenchDetailModel, editorState: WorkbenchLogEntryEditorState) {
    self.model = model
    _editorState = State(wrappedValue: editorState)
  }

  var body: some View {
    Form {
      Section {
        Picker("Kind", selection: $editorState.kind) {
          ForEach(WorkbenchLogEntryKind.allCases, id: \.self) { kind in
            Text(kind.title).tag(kind)
          }
        }
        .pickerStyle(.menu)

        if editorState.kind == .experiment {
          StackedFormField(title: "Hypothesis") {
            TextField("Hypothesis", text: $editorState.hypothesis, axis: .vertical)
          }

          StackedFormField(title: "Change") {
            TextField("Change", text: $editorState.change, axis: .vertical)
          }

          StackedFormField(title: "Rationale") {
            TextField("Rationale", text: $editorState.rationale, axis: .vertical)
          }

          if !editorState.body.isEmpty {
            StackedFormField(title: "Legacy notes") {
              TextEditor(text: $editorState.body)
                .frame(minHeight: 140)
            }
          }
        } else {
          StackedFormField(title: "Body") {
            TextEditor(text: $editorState.body)
              .frame(minHeight: 140)
          }
        }

        StackedFormField(title: "Outcome") {
          TextEditor(text: $editorState.outcome)
            .frame(minHeight: 90)
        }
      }
    }
    .navigationTitle(editorState.entryID == nil ? "New Log Entry" : "Edit Log Entry")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveLogEntryButtonTapped(editorState) {
            dismiss()
          }
        }
        .disabled(!editorState.canSave)
      }
    }
  }
}

private extension WorkbenchLogEntryEditorState {
  var canSave: Bool {
    if kind == .experiment {
      return [hypothesis, change, rationale].allSatisfy {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      } || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private struct WorkbenchCandidateRow: View {
  let model: WorkbenchDetailModel
  let row: WorkbenchCandidateRowData

  @State private var annotation = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        guard let recipeID = row.recipeDetail?.recipe.id else { return }
        model.openCandidateButtonTapped(recipeID: recipeID)
      } label: {
        HStack(alignment: .top, spacing: 12) {
          if let photo = candidatePhoto {
            RecipePhotoImage(
              photoID: photo.id,
              checksum: photo.checksum,
              variant: .thumbnail,
              thumbnailData: photo.thumbnailData
            )
            .frame(width: 72, height: 72)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(Text("Photo for \(row.displayTitle)"))
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(row.displayTitle)
              .font(.headline)
            Label(sourceDisplayName, systemImage: "book")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          if row.recipeDetail != nil {
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .disabled(row.recipeDetail == nil)
      .accessibilityHint(row.recipeDetail == nil ? "" : "Opens this candidate recipe")
      if let recipe = row.recipeDetail?.recipe {
        HStack(spacing: 10) {
          if let totalTimeMinutes = recipe.totalTimeMinutes {
            Label("\(totalTimeMinutes) min", systemImage: "clock")
          }
          if let servingsText = recipe.servingsText {
            Label(servingsText, systemImage: "person.2")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("Recipe unavailable")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      TextField("Annotation", text: $annotation, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...5)
        .onSubmit {
          model.updateAnnotation(candidateID: row.id, annotation: annotation)
        }
      Button {
        model.updateAnnotation(candidateID: row.id, annotation: annotation)
      } label: {
        Label("Save Annotation", systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(.vertical, 4)
    .onAppear {
      annotation = row.candidate.annotation ?? ""
    }
    .onChange(of: row.candidate.annotation) { _, value in
      annotation = value ?? ""
    }
  }

  private var candidatePhoto: RecipeDetailPhoto? {
    guard let detail = row.recipeDetail else { return nil }
    return RecipePhotoCover.coverPhoto(
      coverPhotoID: detail.recipe.coverPhotoID,
      from: detail.photos.filter(\.isDisplayable)
    )
  }

  private var sourceDisplayName: String {
    row.recipeDetail?.source?.workbenchDisplayName ?? "No source recorded"
  }
}

struct WorkbenchEditorView: View {
  @Environment(\.dismiss) private var dismiss
  let model: WorkbenchLibraryModel
  @State private var title = ""
  @State private var notes = ""

  var body: some View {
    Form {
      Section {
        StackedTextField(title: "Title", text: $title)
        StackedFormField(title: "Notes") {
          TextEditor(text: $notes)
            .frame(minHeight: 100)
        }
      }
    }
    .navigationTitle("New Workbench")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveWorkbenchButtonTapped(title: title, notes: notes) {
            dismiss()
          }
        }
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }
}

private extension WorkbenchLogEntryKind {
  var systemImage: String {
    switch self {
    case .rationale: "lightbulb"
    case .experiment: "flask"
    case .fork: "arrow.triangle.branch"
    case .observation: "eye"
    case .note: "note.text"
    }
  }
}
