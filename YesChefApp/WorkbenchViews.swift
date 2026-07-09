import LLMClientKit
import SwiftUI
import UIKit
import YesChefCore

struct WorkbenchesStack: View {
  let model: WorkbenchLibraryModel
  var onRecipeSelected: (RecipeDetailPresentation) -> Void = { _ in }

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.navigationPath) {
      WorkbenchListView(model: model, style: .navigation)
        .navigationDestination(for: Workbench.ID.self) { workbenchID in
          WorkbenchDetailView(workbenchID: workbenchID, onRecipeSelected: onRecipeSelected)
            .id(workbenchID)
        }
    }
  }
}

struct WorkbenchListView: View {
  enum Style {
    case navigation
    case selection
  }

  let model: WorkbenchLibraryModel
  var style: Style

  var body: some View {
    @Bindable var model = model

    Group {
      switch style {
      case .navigation:
        List {
          ForEach(model.workbenchRows) { row in
            NavigationLink(value: row.id) {
              WorkbenchRowView(row: row)
            }
            .swipeActions {
              Button(role: .destructive) {
                model.deleteWorkbenchButtonTapped(row)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
      case .selection:
        List(model.workbenchRows, selection: $model.selectedWorkbenchID) { row in
          WorkbenchRowView(row: row)
            .tag(row.id)
            .swipeActions {
              Button(role: .destructive) {
                model.deleteWorkbenchButtonTapped(row)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
    }
    .navigationTitle("Workbenches")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.addWorkbenchButtonTapped()
        } label: {
          Label("Add Workbench", systemImage: "plus")
        }
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
  @AppStorage(ChatWorkspaceDetent.storageKey) private var chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
  @State private var model: WorkbenchDetailModel
  @State private var compareTier: ModelTier = .onDevice
  let isFocusActive: Bool
  let focusButtonTapped: (() -> Void)?

  init(
    workbenchID: Workbench.ID,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void = { _ in },
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil
  ) {
    _model = State(
      wrappedValue: WorkbenchDetailModel(
        workbenchID: workbenchID,
        openRecipe: { recipeID in onRecipeSelected(RecipeDetailPresentation(recipeID: recipeID)) }
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
          if isSplitEnabled {
            ChatWorkspaceSplit(
              context: .workbench(WorkbenchChatContext(detail: detail)),
              detentRaw: $chatWorkspaceDetentRaw,
              activeTierChanged: { compareTier = $0 },
              applyActions: { chatModel in
                model.applyActionCatalog(for: chatModel)
              }
            ) {
              WorkbenchReader(
                model: model,
                detail: detail,
                compareButtonTapped: {
                  await openCompare(detail: detail)
                }
              )
            }
          } else {
            WorkbenchReader(
              model: model,
              detail: detail,
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
    .toolbar {
      if model.detail != nil {
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
    .sheet(item: $model.destination.chat) { chatModel in
      NavigationStack {
        RecipeChatPanel(
          chatModel: chatModel,
          applyActions: model.applyActionCatalog(for: chatModel)
        )
      }
    }
    .sheet(item: $model.destination.logEntryEditor) { editorState in
      NavigationStack {
        WorkbenchLogEntryEditorView(model: model, editorState: editorState)
      }
    }
    .alert("Workbench Error", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
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
  }

  @ViewBuilder private var compareCover: some View {
    if let detail = model.detail {
      if isRegularWidth {
        ChatWorkspaceSplit(
          context: .workbench(WorkbenchChatContext(detail: detail)),
          detentRaw: $chatWorkspaceDetentRaw,
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
          compactChatContext: .workbench(WorkbenchChatContext(detail: detail)),
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
    model.compareButtonTapped()
  }

  private var isRegularWidth: Bool {
    horizontalSizeClass != .compact
  }

  private var isSplitEnabled: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
  }
}

private struct WorkbenchReader: View {
  let model: WorkbenchDetailModel
  let detail: WorkbenchDetailData
  let compareButtonTapped: () async -> Void

  @State private var titleText = ""
  @State private var notesText = ""

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          StackedTextField(title: "Title", text: $titleText)
            .font(.title2.weight(.semibold))
          Button {
            model.saveTitleButtonTapped(titleText)
          } label: {
            Label("Save Title", systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.bordered)
          .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          TextEditor(text: $notesText)
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
          Button {
            model.saveNotesButtonTapped(notesText)
          } label: {
            Label("Save Notes", systemImage: "square.and.arrow.down")
          }
          .buttonStyle(.bordered)
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
            }
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
          Button {
            Task {
              await compareButtonTapped()
            }
          } label: {
            Label("Compare", systemImage: "square.split.2x2")
          }
          .disabled(!model.canCompare)
        }
      }
    }
    .onAppear {
      titleText = detail.workbench.title
      notesText = detail.workbench.notes ?? ""
    }
    .onChange(of: detail.workbench.title) { _, title in
      titleText = title
    }
    .onChange(of: detail.workbench.notes) { _, notes in
      notesText = notes ?? ""
    }
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
      Text(entry.body)
        .font(.body)
        .foregroundStyle(.primary)
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

private struct WorkingRecipeRow: View {
  let recipe: Recipe
  let open: () -> Void
  let promote: () -> Void
  let remove: () -> Void

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

        StackedFormField(title: "Body") {
          TextEditor(text: $editorState.body)
            .frame(minHeight: 140)
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
        .disabled(editorState.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }
}

private struct WorkbenchCandidateRow: View {
  let model: WorkbenchDetailModel
  let row: WorkbenchCandidateRowData

  @State private var annotation = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(row.displayTitle)
        .font(.headline)
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
}

private struct WorkbenchCandidatePickerView: View {
  @Environment(\.dismiss) private var dismiss
  let model: WorkbenchDetailModel
  @State private var selection: Set<Recipe.ID> = []
  @State private var searchText = ""

  var body: some View {
    List(selection: $selection) {
      ForEach(filteredRecipeRows) { row in
        RecipeListRow(
          row: row,
          options: RecipeListViewOptions(
            density: .compact,
            showsSourceMetadata: true,
            showsCategoryMetadata: false
          )
        )
        .tag(row.recipe.id)
        .disabled(model.existingCandidateRecipeIDs.contains(row.recipe.id))
      }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle("Add Candidates")
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search recipes"
    )
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Add") {
          if model.addCandidatesButtonTapped(recipeIDs: selection) {
            dismiss()
          }
        }
        .disabled(selection.isEmpty)
      }
    }
  }

  private var filteredRecipeRows: [RecipeListRowData] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return model.availableRecipeRows }
    return model.availableRecipeRows.filter { row in
      RecipeSearchMatcher.matches(query: query, in: row.recipe.title, row.recipe.subtitle)
    }
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
