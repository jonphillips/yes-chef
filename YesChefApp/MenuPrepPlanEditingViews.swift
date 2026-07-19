import SwiftUI
import YesChefCore

struct MenuPrepPlanStepView: View {
  let step: PrepPlanStepRecord
  let itemRows: [MenuItemRowData]
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var editStep: (PrepPlanStepRecord) -> Void
  var deleteStep: (PrepPlanStepRecord.ID) -> Void
  var reorderStep: (PrepPlanStepRecord.ID, MenuItemMoveDirection) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checklist")
        .font(.headline)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 4) {
        Text(step.task)
        if let serves = step.serves { servesLabel(serves) }
      }
      Spacer(minLength: 8)
    }
    .padding(.vertical, 12)
    .contextMenu {
      Button("Edit", systemImage: "pencil") { editStep(step) }
      Button("Move Earlier", systemImage: "arrow.up") { reorderStep(step.id, .earlier) }
      Button("Move Later", systemImage: "arrow.down") { reorderStep(step.id, .later) }
      Button("Delete", systemImage: "trash", role: .destructive) { deleteStep(step.id) }
    }
  }

  @ViewBuilder private func servesLabel(_ serves: String) -> some View {
    if let recipePresentation {
      Button { onRecipeSelected?(recipePresentation) } label: {
        Label(serves, systemImage: "fork.knife").recipeChip()
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open recipe for \(serves)")
    } else if step.sourceDish == nil {
      Text(serves).font(.caption).foregroundStyle(.secondary)
    } else {
      Label(serves, systemImage: "fork.knife")
        .font(.caption).foregroundStyle(.secondary).recipeChip()
    }
  }

  private var recipePresentation: RecipeDetailPresentation? {
    guard let sourceDish = step.sourceDish,
          let row = itemRows.first(where: { $0.id == sourceDish }),
          let recipeID = row.recipe?.id,
          onRecipeSelected != nil else { return nil }
    return RecipeDetailPresentation(recipeID: recipeID, scaleContext: .menuItem(row.id))
  }
}

struct PrepPlanStepEditorDraft: Identifiable {
  let stepID: PrepPlanStepRecord.ID?
  var sessionBand: PrepPlanSessionBand
  var customSession: String
  var task: String
  var serves: String
  var id: String { stepID?.uuidString ?? "new" }

  init() { stepID = nil; sessionBand = .flexible; customSession = ""; task = ""; serves = "" }
  init(step: PrepPlanStepRecord) {
    stepID = step.id
    sessionBand = PrepPlanSessionBand.allCases.first(where: { $0.title == step.session }) ?? .other
    customSession = step.session; task = step.task; serves = step.serves ?? ""
  }
  var step: PrepPlanStep {
    PrepPlanStep(session: sessionBand == .other ? customSession : sessionBand.title, task: task,
      serves: serves.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : serves)
  }
}

struct PrepPlanStepEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: PrepPlanStepEditorDraft
  let save: (PrepPlanStepEditorDraft) -> Void
  init(draft: PrepPlanStepEditorDraft, save: @escaping (PrepPlanStepEditorDraft) -> Void) {
    _draft = State(initialValue: draft); self.save = save
  }
  var body: some View {
    NavigationStack {
      Form {
        VStack(alignment: .leading) { Text("Session"); Picker("Session", selection: $draft.sessionBand) {
          ForEach(PrepPlanSessionBand.allCases) { Text($0.title).tag($0) }
        }.labelsHidden() }
        if draft.sessionBand == .other { VStack(alignment: .leading) { Text("Other session"); TextField("e.g. Wednesday evening", text: $draft.customSession) } }
        VStack(alignment: .leading) { Text("Task"); TextField("e.g. Salt the chicken", text: $draft.task, axis: .vertical).lineLimit(2...4) }
        VStack(alignment: .leading) { Text("Serves"); TextField("Optional meal or day", text: $draft.serves) }
      }
      .navigationTitle(draft.stepID == nil ? "Add Prep Step" : "Edit Prep Step")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save(draft); dismiss() }.disabled(!canSave) }
      }
    }
  }
  private var canSave: Bool { !draft.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.sessionBand != .other || !draft.customSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
}

struct LearningsSection: View {
  let learnings: [Learning]
  var updateLearning: (Learning, String) -> Void
  var deleteLearning: (Learning.ID) -> Void
  var reorderLearnings: ([Learning.ID], LearningReorderDestination) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Learnings").font(.title2.weight(.semibold))
      if learnings.isEmpty {
        ContentUnavailableView("No Learnings Yet", systemImage: "lightbulb", description: Text("Useful ideas returned from an AI handoff appear here."))
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(learnings) { learning in
            LearningRow(learning: learning, update: updateLearning, delete: deleteLearning)
            if learning.id != learnings.last?.id { Divider() }
          }
          .reorderable()
        }
        .reorderContainer(for: Learning.self) { difference in
          switch difference.destination.position {
          case let .before(id):
            reorderLearnings(difference.sources, .before(id))
          case .end:
            reorderLearnings(difference.sources, .end)
          }
        }
      }
    }
  }
}

struct LearningRow: View {
  let learning: Learning
  var update: (Learning, String) -> Void
  var delete: (Learning.ID) -> Void
  @State private var isEditing = false
  @State private var draft = ""
  var body: some View {
    Group {
      if isEditing { VStack(alignment: .leading, spacing: 8) {
        TextField("Learning", text: $draft, axis: .vertical).lineLimit(2...6)
        HStack { Button("Cancel") { draft = learning.text; isEditing = false }; Spacer(); Button("Save") { update(learning, draft); isEditing = false }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
      } } else { Button { draft = learning.text; isEditing = true } label: { Text(learning.text).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).accessibilityLabel("Edit learning: \(learning.text)") }
    }
    .padding(.vertical, 12)
    .swipeActions { Button(role: .destructive) { delete(learning.id) } label: { Label("Delete", systemImage: "trash") } }
  }
}
