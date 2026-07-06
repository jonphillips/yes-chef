import SwiftUI
import UIKit
import YesChefCore

struct WorkbenchesStack: View {
  let model: WorkbenchLibraryModel

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.navigationPath) {
      WorkbenchListView(model: model, style: .navigation)
        .navigationDestination(for: Workbench.ID.self) { workbenchID in
          WorkbenchDetailView(workbenchID: workbenchID)
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

  var body: some View {
    if let workbenchID = model.selectedWorkbenchID {
      WorkbenchDetailView(workbenchID: workbenchID)
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
  @State private var compactChatModel: RecipeChatModel?

  init(workbenchID: Workbench.ID) {
    _model = State(wrappedValue: WorkbenchDetailModel(workbenchID: workbenchID))
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
              applyActions: { _ in [] }
            ) {
              WorkbenchReader(model: model, detail: detail)
            }
          } else {
            WorkbenchReader(model: model, detail: detail)
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
        RecipeChatPanel(chatModel: chatModel, applyActions: [])
      }
    }
    .alert("Workbench Error", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var isSplitEnabled: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
  }
}

private struct WorkbenchReader: View {
  let model: WorkbenchDetailModel
  let detail: WorkbenchDetailData

  @State private var notesText = ""

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(detail.workbench.title)
            .font(.title2.weight(.semibold))
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
        Text("Candidates")
      }
    }
    .onAppear {
      notesText = detail.workbench.notes ?? ""
    }
    .onChange(of: detail.workbench.notes) { _, notes in
      notesText = notes ?? ""
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

  var body: some View {
    List(selection: $selection) {
      ForEach(model.availableRecipeRows) { row in
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
