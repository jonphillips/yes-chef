import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class ChatPrepPlanReviewModel: Identifiable {
  nonisolated let id = UUID()
  let row: ChatAccessInbox.PrepPlanRow
  let plan: ChatPrepPlanImport.Plan
  var keptIndices: Set<Int>
  var errorMessage: String?
  init(row: ChatAccessInbox.PrepPlanRow, plan: ChatPrepPlanImport.Plan) {
    self.row = row; self.plan = plan
    keptIndices = Set(plan.dishes.flatMap(\.1).enumerated().compactMap { index, entry in if case .new = entry { index } else { nil } })
  }
  func setKept(_ kept: Bool, at index: Int) { if kept { keptIndices.insert(index) } else { keptIndices.remove(index) } }
}

@MainActor
struct ChatPrepPlanReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: ChatPrepPlanReviewModel
  let isApplying: Bool
  let apply: @MainActor () async -> Void

  var body: some View {
    NavigationStack {
      Form {
        if model.plan.planChangedSinceStage != false {
          Section { Text(model.plan.planChangedSinceStage == true ? "This plan changed since Chat read it." : "Chat couldn't see the current plan.").font(.subheadline) }.attentionCard()
        }
        ForEach(Array(model.plan.dishes.enumerated()), id: \.element.0.id) { dishIndex, dish in
          Section("\(dish.0.title) · Day \(dish.0.dayOffset + 1)") {
            let baseIndex = model.plan.dishes.prefix(dishIndex).reduce(0) { $0 + $1.1.count }
            let new = dish.1.enumerated().compactMap { offset, entry -> (Int, ChatPrepPlanImport.Entry)? in
              guard case .new = entry else { return nil }
              return (baseIndex + offset, entry)
            }
            if !new.isEmpty {
              Text("New").font(.caption).foregroundStyle(.secondary)
              ForEach(new, id: \.0) { index, entry in
                if case let .new(_, step) = entry {
                  Toggle(isOn: Binding(get: { model.keptIndices.contains(index) }, set: { model.setKept($0, at: index) })) {
                    stepRow(workDay: step.workDayOffset, session: step.session, task: step.task)
                  }
                }
              }
            }
            let kept = dish.1.compactMap { if case let .kept(_, step) = $0 { step } else { nil } }
            if !kept.isEmpty { Text("Kept").font(.caption).foregroundStyle(.secondary) }
            ForEach(kept) { step in stepRow(workDay: step.workDayOffset, session: step.session, task: step.task) }
            let removed = dish.1.compactMap { if case let .removed(_, step, byName) = $0 { (step, byName) } else { nil } }
            if !removed.isEmpty { Text("Removed").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(removed.enumerated()), id: \.offset) { _, item in
              let (step, byName) = item
              VStack(alignment: .leading) { stepRow(workDay: step.workDayOffset, session: step.session, task: step.task); if byName { Text("Matched by name").font(.caption).foregroundStyle(.secondary) } }
            }
          }
        }
        if let error = model.errorMessage { Section { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) } }
      }
      .navigationTitle(model.plan.menuTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Apply") { Task { await apply() } }.disabled(isApplying) }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func stepRow(workDay: Int?, session: String, task: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      let day = workDay.map { offset in
        model.plan.startDate.flatMap { Calendar.current.date(byAdding: .day, value: offset, to: $0) }
          .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Day \(offset + 1)"
      }
      Text(day.map { "\($0) · \(session)" } ?? session).font(.subheadline)
      Text(task).foregroundStyle(.secondary)
    }
  }
}

@Observable
@MainActor
final class ChatMenuReviewModel: Identifiable {
  nonisolated let id = UUID()
  let row: ChatAccessInbox.MenuRow
  var title: String
  let dayCount: Int
  var items: [ChatMenuImport.ResolvedItem]
  var errorMessage: String?

  init(row: ChatAccessInbox.MenuRow, title: String, dayCount: Int, items: [ChatMenuImport.ResolvedItem]) {
    self.row = row
    self.title = title
    self.dayCount = dayCount
    self.items = items
  }

  var canCreate: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && items.contains(where: \.isKept)
  }

  func setKept(_ kept: Bool, at index: Int) {
    guard items.indices.contains(index) else { return }
    items[index].isKept = kept
  }
}

@MainActor
struct ChatMenuReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: ChatMenuReviewModel
  let isCreating: Bool
  let create: @MainActor () async -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Menu title", text: $model.title)
            .accessibilityLabel("Menu title")
          if model.dayCount > 1 {
            LabeledContent("Days", value: "\(model.dayCount)")
          }
          if let errorMessage = model.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.footnote)
              .foregroundStyle(.orange)
          }
        }

        ForEach(0..<model.dayCount, id: \.self) { day in
          ForEach(MealPlanItemSlot.allCases, id: \.self) { slot in
            let indexed = model.items.enumerated().filter { $0.element.item.dayOffset == day && $0.element.item.slot == slot }
            if !indexed.isEmpty {
              Section("Day \(day + 1) · \(slot.title)") {
                ForEach(indexed, id: \.offset) { index, resolved in
                  itemRow(resolved, index: index)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Review Menu")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create Menu") { Task { await create() } }
            .disabled(!model.canCreate || isCreating)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private func itemRow(_ resolved: ChatMenuImport.ResolvedItem, index: Int) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Toggle("Keep \(resolved.item.title)", isOn: Binding(
        get: { model.items[index].isKept },
        set: { model.setKept($0, at: index) }
      ))
      .labelsHidden()
      VStack(alignment: .leading, spacing: 4) {
        Text(resolved.item.title).font(.headline)
        Text(badge(for: resolved.resolution))
          .font(.caption)
          .foregroundStyle(resolved.resolution == .recipeMissing ? .orange : .secondary)
        if let note = resolved.item.note, !note.isEmpty {
          Text(note).font(.subheadline).foregroundStyle(.secondary)
        }
        if let scale = resolved.item.scale, scale != 1 {
          Text("Scale · \(scale.formatted())×").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .contain)
  }

  private func badge(for resolution: ChatMenuImport.Resolution) -> String {
    switch resolution {
    case .libraryRecipe: "In your library"
    case .newDish: "New dish"
    case .recipeMissing: "Not on this device, adding as a note"
    }
  }
}

@Observable
@MainActor
final class ChatMenuDayReviewModel: Identifiable {
  nonisolated let id = UUID()
  let row: ChatAccessInbox.MenuDayRow
  let plan: ChatMenuDayImport.Plan
  var keptIndices: Set<Int>
  var errorMessage: String?

  init(row: ChatAccessInbox.MenuDayRow, plan: ChatMenuDayImport.Plan) {
    self.row = row
    self.plan = plan
    self.keptIndices = Set(plan.entries.indices)
  }

  var canApply: Bool { true }

  func setKept(_ kept: Bool, at index: Int) {
    if kept { keptIndices.insert(index) } else { keptIndices.remove(index) }
  }

  var removedRows: [MenuItem] {
    plan.removedRows(keeping: keptIndices)
  }
}

@MainActor
struct ChatMenuDayReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: ChatMenuDayReviewModel
  let isApplying: Bool
  let apply: @MainActor () async -> Void

  var body: some View {
    NavigationStack {
      Form {
        if model.plan.dayChangedSinceStage {
          Section { Text("This day changed since Chat read it.").font(.subheadline) }
            .attentionCard()
        }
        ForEach(MealPlanItemSlot.allCases, id: \.self) { slot in
          let indexed = model.plan.entries.enumerated().filter { $0.element.slot == slot }
          if !indexed.isEmpty {
            Section(slot.title) {
              ForEach(indexed, id: \.offset) { index, entry in itemRow(entry, index: index) }
            }
          }
        }
        if !model.removedRows.isEmpty {
          Section("Removed") {
            ForEach(Array(model.removedRows.enumerated()), id: \.offset) { _, item in
              VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text(item.mealSlot.title).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        if let error = model.errorMessage {
          Section { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
        }
      }
      .navigationTitle("\(model.plan.menuTitle) · \(model.row.dayTitle)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") { Task { await apply() } }.disabled(isApplying)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private func itemRow(_ entry: ChatMenuDayImport.Entry, index: Int) -> some View {
    let title = entry.title
    HStack(alignment: .top, spacing: 12) {
      Toggle("Keep \(title)", isOn: Binding(get: { model.keptIndices.contains(index) }, set: { model.setKept($0, at: index) }))
        .labelsHidden()
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(status(for: entry)).font(.caption).foregroundStyle(statusColor(for: entry))
        if let note = entry.note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
        ForEach(Array(changes(for: entry).enumerated()), id: \.offset) { _, change in
          Text(change).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func status(for entry: ChatMenuDayImport.Entry) -> String {
    switch entry {
    case let .kept(_, resolution): resolutionLabel(resolution, prefix: "Kept")
    case let .changed(_, _, resolution): resolutionLabel(resolution, prefix: "Changed")
    case let .new(_, resolution): resolutionLabel(resolution, prefix: "New")
    }
  }

  private func resolutionLabel(_ resolution: ChatMenuDayImport.Resolution, prefix: String) -> String {
    switch resolution {
    case .libraryRecipe: "\(prefix) · In your library"
    case .newDish: "\(prefix) · New dish"
    case .recipeMissing: "\(prefix) · Recipe missing on this device, adding as a note"
    }
  }

  private func statusColor(for entry: ChatMenuDayImport.Entry) -> Color {
    if case .new(_, .recipeMissing) = entry { return .orange }
    return .secondary
  }

  private func changes(for entry: ChatMenuDayImport.Entry) -> [String] {
    guard case let .changed(_, changes, _) = entry else { return [] }
    return changes.map { change in
      switch change {
      case let .slot(from, to): "Slot \(from.title) → \(to.title)"
      case let .note(note): note.map { "Note · \($0)" } ?? "Note removed"
      case let .scale(from, to): "Scale \(from.formatted())× → \(to.formatted())×"
      }
    }
  }
}

private extension ChatMenuDayImport.Entry {
  var slot: MealPlanItemSlot {
    switch self {
    case let .kept(row, _): row.mealSlot
    case let .changed(row, changes, _):
      changes.compactMap { if case let .slot(_, to) = $0 { to } else { nil } }.first ?? row.mealSlot
    case let .new(item, _): item.slot
    }
  }

  var title: String {
    switch self {
    case let .kept(row, _), let .changed(row, _, _): row.title
    case let .new(item, _): item.title
    }
  }

  var note: String? {
    switch self {
    case let .kept(row, _): row.notes
    case let .changed(row, changes, _):
      changes.compactMap { if case let .note(note) = $0 { note } else { nil } }.first ?? row.notes
    case let .new(item, _): item.note
    }
  }
}
