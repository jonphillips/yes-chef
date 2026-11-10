import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class ChatMenuReviewModel: Identifiable {
  let id = UUID()
  let row: ChatAccessInbox.MenuRow
  var title: String
  let dayCount: Int
  var items: [ChatMenuImport.ResolvedItem]

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
