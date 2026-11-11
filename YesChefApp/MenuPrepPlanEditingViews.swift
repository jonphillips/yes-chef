import SwiftUI
import YesChefCore

struct MenuPrepPlanStepView: View {
  let step: PrepPlanStepRecord
  var isDone = false
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
        if let makeAheadWindow = step.makeAheadWindow {
          Label(makeAheadWindow, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(step.task)
          .foregroundStyle(isDone ? .secondary : .primary)
        if let dishChipLabel { servesLabel(dishChipLabel) }
      }
      Spacer(minLength: 8)
      if isDone {
        Image(systemName: "checkmark")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityLabel("Done")
      }
    }
    .padding(.vertical, 12)
    .opacity(isDone ? 0.55 : 1)
    .contextMenu {
      Button { editStep(step) } label: { Label("Edit", symbol: .editRow) }
      Button("Move Earlier", systemImage: "arrow.up") { reorderStep(step.id, .earlier) }
      Button("Move Later", systemImage: "arrow.down") { reorderStep(step.id, .later) }
      Button(role: .destructive) { deleteStep(step.id) } label: { Label("Delete", symbol: .delete) }
    }
  }

  @ViewBuilder private func servesLabel(_ serves: String) -> some View {
    if let recipePresentation {
      Button { onRecipeSelected?(recipePresentation) } label: {
        Label(serves, symbol: .dish).recipeChip()
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open recipe for \(serves)")
    } else if step.sourceDish == nil {
      Text(serves).font(.caption).foregroundStyle(.secondary)
    } else {
      Label(serves, symbol: .dish)
        .font(.caption).foregroundStyle(.secondary).recipeChip()
    }
  }

  /// The text shown on the dish chip. Prefers the free-text `serves` (which AI
  /// steps populate); for hand-authored steps that only linked a dish, falls
  /// back to the linked dish's title so the link is visible on the row.
  private var dishChipLabel: String? {
    if let serves = step.serves?.trimmingCharacters(in: .whitespacesAndNewlines),
       !serves.isEmpty {
      return serves
    }
    if let sourceDish = step.sourceDish,
       let row = itemRows.first(where: { $0.id == sourceDish }) {
      return row.displayTitle
    }
    return nil
  }

  private var recipePresentation: RecipeDetailPresentation? {
    guard let sourceDish = step.sourceDish,
          let row = itemRows.first(where: { $0.id == sourceDish }),
          let recipeID = row.recipe?.id,
          onRecipeSelected != nil else { return nil }
    return RecipeDetailPresentation(
      recipeID: recipeID,
      scaleContext: .menuItem(row.id),
      includingArchivedRecipe: true
    )
  }
}

struct PrepPlanStepEditorDraft: Identifiable {
  let stepID: PrepPlanStepRecord.ID?
  var sessionBand: PrepPlanSessionBand
  var customSession: String
  var task: String
  var makeAheadWindow: String
  var timeOfDay: Int?
  var serves: String
  var sourceDish: MenuItem.ID?
  var workDayOffset: Int?
  var id: String { stepID?.uuidString ?? "new" }

  init() {
    stepID = nil
    sessionBand = .flexible
    customSession = ""
    task = ""
    makeAheadWindow = ""
    timeOfDay = nil
    serves = ""
    sourceDish = nil
    workDayOffset = nil
  }

  init(step: PrepPlanStepRecord) {
    stepID = step.id
    sessionBand = PrepPlanSessionBand.allCases.first(where: { $0.title == step.session }) ?? .other
    customSession = step.session
    task = step.task
    makeAheadWindow = step.makeAheadWindow ?? ""
    timeOfDay = step.timeOfDay
    serves = step.serves ?? ""
    sourceDish = step.sourceDish
    workDayOffset = step.workDayOffset
  }

  var step: PrepPlanStep {
    PrepPlanStep(
      session: sessionBand == .other ? customSession : sessionBand.title,
      task: task,
      serves: serves.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : serves,
      makeAheadWindow: makeAheadWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : makeAheadWindow,
      timeOfDay: workDayOffset == nil ? nil : timeOfDay,
      sourceDish: sourceDish,
      workDayOffset: workDayOffset
    )
  }
}

struct PrepPlanStepEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: PrepPlanStepEditorDraft
  private let itemRows: [MenuItemRowData]
  private let suggestedSourceDish: MenuItem.ID?
  private let dayCount: Int
  private let placementStartDate: Date?
  let save: (PrepPlanStepEditorDraft) -> Void

  init(
    draft: PrepPlanStepEditorDraft,
    itemRows: [MenuItemRowData],
    dayCount: Int,
    placementStartDate: Date?,
    save: @escaping (PrepPlanStepEditorDraft) -> Void
  ) {
    let suggestion = draft.sourceDish == nil
      ? PrepPlanDishMatcher.suggestedSourceDish(
        serves: draft.serves,
        among: itemRows.map { PrepPlanDishMatchCandidate(id: $0.id, title: $0.displayTitle) }
      )
      : nil
    var initialDraft = draft
    initialDraft.sourceDish = suggestion ?? initialDraft.sourceDish
    _draft = State(initialValue: initialDraft)
    self.itemRows = itemRows
    self.dayCount = dayCount
    self.placementStartDate = placementStartDate
    suggestedSourceDish = suggestion
    self.save = save
  }

  var body: some View {
    NavigationStack {
      Form {
        VStack(alignment: .leading) { Text("Session"); Picker("Session", selection: $draft.sessionBand) {
          ForEach(PrepPlanSessionBand.allCases) { Text($0.title).tag($0) }
        }.labelsHidden() }
        if dayCount > 1 {
          VStack(alignment: .leading) {
            Text("Day")
            Picker("Day", selection: $draft.workDayOffset) {
              Text("Flexible").tag(Int?.none)
              ForEach(-7..<dayCount, id: \.self) { offset in
                Text(workDayTitle(offset)).tag(Optional(offset))
              }
            }.labelsHidden()
              .onChange(of: draft.workDayOffset) { _, value in if value == nil { draft.timeOfDay = nil } }
          }
        }
        if draft.sessionBand == .other { VStack(alignment: .leading) { Text("Other session"); TextField("e.g. Wednesday evening", text: $draft.customSession) } }
        VStack(alignment: .leading) { Text("Task"); TextField("e.g. Salt the chicken", text: $draft.task, axis: .vertical).lineLimit(2...4) }
        VStack(alignment: .leading) { Text("Make-ahead window"); TextField("e.g. Up to 3 days ahead", text: $draft.makeAheadWindow) }
        if dayCount > 1, draft.workDayOffset != nil {
          Toggle("Time", isOn: Binding(
            get: { draft.timeOfDay != nil },
            set: { draft.timeOfDay = $0 ? (draft.timeOfDay ?? 9 * 60) : nil }
          ))
          if let timeOfDay = draft.timeOfDay {
            DatePicker("Time", selection: Binding(
              get: { Calendar.current.date(bySettingHour: timeOfDay / 60, minute: timeOfDay % 60, second: 0, of: Date()) ?? Date() },
              set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                if let hour = components.hour, let minute = components.minute { draft.timeOfDay = hour * 60 + minute }
              }
            ), displayedComponents: .hourAndMinute)
          }
        }
        VStack(alignment: .leading) { Text("Serves"); TextField("Optional meal or day", text: $draft.serves) }
        VStack(alignment: .leading, spacing: 4) {
          Picker("Dish", selection: $draft.sourceDish) {
            Text("No dish").tag(MenuItem.ID?.none)
            ForEach(itemRows) { row in
              Text(row.displayTitle).tag(Optional(row.id))
            }
          }
          if draft.sourceDish == suggestedSourceDish, suggestedSourceDish != nil {
            Text("Matched from ‘Serves’. Save to link.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(draft.stepID == nil ? "Add Prep Step" : "Edit Prep Step")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save(draft); dismiss() }.disabled(!canSave) }
      }
    }
  }

  private var canSave: Bool {
    !draft.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (draft.sessionBand != .other
        || !draft.customSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func workDayTitle(_ offset: Int) -> String {
    let dayNumber = offset + 1
    let dayTitle = dayNumber <= 0
      ? "\(-offset) \(-offset == 1 ? "day" : "days") before Day 1"
      : "Day \(dayNumber)"
    guard let placementStartDate,
      let date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: offset, to: placementStartDate)
    else { return dayTitle }
    return "\(dayTitle) · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
  }
}

struct LearningsSection: View {
  let learnings: [Learning]
  var showsTitle = true
  var showsEmptyPlaceholder = true
  var addLearning: ((String) -> LearningCreationResult)? = nil
  var updateLearning: (Learning, String) -> Void
  var deleteLearning: (Learning.ID) -> Void
  var reorderLearnings: ([Learning.ID], LearningReorderDestination) -> Void

  var body: some View {
    EditableRowsSection(
      title: showsTitle ? "Learnings" : "",
      titleFont: .title2.weight(.semibold),
      editorLabel: "Learning",
      items: learnings,
      itemText: \.text,
      addItem: addLearning.map { addLearning in
        { text in
          switch addLearning(text) {
          case .added, .duplicate:
            true
          case .failed:
            false
          }
        }
      },
      addButtonLabel: "Add Learning",
      addButtonIconOnly: true,
      updateItem: updateLearning,
      deleteItem: { deleteLearning($0.id) },
      reorderItems: { sourceIDs, destinationID in
        reorderLearnings(
          sourceIDs,
          destinationID.map(LearningReorderDestination.before) ?? .end
        )
      }
    ) {
      if showsEmptyPlaceholder {
        Text("None yet.")
          .foregroundStyle(.tertiary)
      } else {
        EmptyView()
      }
    } itemContent: { learning in
      Text(learning.text)
    } badge: { learning in
      if learning.provenance == .inApp {
        Label("Hand-authored", symbol: .editRow)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
