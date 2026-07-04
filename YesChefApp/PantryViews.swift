import SwiftUI
import YesChefCore

struct PantryItemEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var notes = ""
  @State private var policyMode: PantryPolicyMode = .unlimited
  @State private var thresholdQuantity = ""
  @State private var thresholdUnit = ""

  let model: GroceryLibraryModel
  let itemID: PantryItem.ID?

  init(model: GroceryLibraryModel, itemID: PantryItem.ID? = nil) {
    self.model = model
    self.itemID = itemID
    let item = itemID.flatMap { id in
      model.pantryItems.first { $0.id == id }
    }
    _title = State(initialValue: item?.title ?? "")
    _notes = State(initialValue: item?.notes ?? "")
    _policyMode = State(initialValue: PantryPolicyMode(policy: item?.policy ?? .unlimited))
    if case let .threshold(quantity, unit)? = item?.policy {
      _thresholdQuantity = State(initialValue: formatPantryThresholdQuantity(quantity))
      _thresholdUnit = State(initialValue: unit)
    }
  }

  private var isSaveDisabled: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var selectedPolicy: PantryPolicy {
    switch policyMode {
    case .unlimited:
      return .unlimited
    case .threshold:
      return PantryPolicy.thresholdOrAlwaysConfirm(
        quantity: Double(thresholdQuantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
        unit: thresholdUnit
      )
    case .alwaysConfirm:
      return .alwaysConfirm
    }
  }

  private var showsThresholdQuantity: Bool {
    thresholdUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || PantryPolicy.canUseThreshold(unit: thresholdUnit)
  }

  var body: some View {
    Form {
      Section("Pantry Item") {
        StackedTextField(title: "Name", text: $title, prompt: "Sugar")
        StackedTextEditor(title: "Notes", text: $notes, minHeight: 90)
      }

      Section("Shopping Policy") {
        Picker("Policy", selection: $policyMode) {
          ForEach(PantryPolicyMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        if policyMode == .threshold {
          StackedTextField(title: "Unit", text: $thresholdUnit, prompt: "cup")
            .textInputAutocapitalization(.never)
          if showsThresholdQuantity {
            StackedTextField(title: "Quantity", text: $thresholdQuantity, prompt: "0.5")
              .keyboardType(.decimalPad)
          }
        }
      }
    }
    .navigationTitle(itemID == nil ? "Add Pantry Item" : "Edit Pantry Item")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.savePantryItemButtonTapped(
            itemID: itemID,
            title: title,
            notes: notes,
            policy: selectedPolicy
          ) {
            dismiss()
          }
        }
        .disabled(isSaveDisabled)
      }
    }
  }
}

private enum PantryPolicyMode: String, CaseIterable, Identifiable {
  case unlimited
  case threshold
  case alwaysConfirm

  var id: Self { self }

  init(policy: PantryPolicy) {
    switch policy {
    case .unlimited:
      self = .unlimited
    case .threshold:
      self = .threshold
    case .alwaysConfirm:
      self = .alwaysConfirm
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .unlimited:
      "Always have it"
    case .threshold:
      "Remind me"
    case .alwaysConfirm:
      "Always confirm"
    }
  }
}

extension PantryPolicy {
  var pantrySummary: String {
    switch self {
    case .unlimited:
      "Always have it"
    case let .threshold(quantity, unit):
      "Remind above \(formatPantryThresholdQuantity(quantity)) \(unit)"
    case .alwaysConfirm:
      "Always confirm"
    }
  }
}

private func formatPantryThresholdQuantity(_ quantity: Double) -> String {
  if quantity.rounded() == quantity {
    return String(Int(quantity))
  }
  return String(format: "%g", quantity)
}
