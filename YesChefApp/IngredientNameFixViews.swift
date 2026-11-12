import SwiftUI
import YesChefCore

struct IngredientNameFixesSheet: View {
  let model: GroceryLibraryModel
  @Environment(\.dismiss) private var dismiss
  @State private var editing: IngredientNameFixEditor.Draft?

  var body: some View {
    List {
      if model.ingredientNameFixes.isEmpty {
        ContentUnavailableView(
          "No Name Fixes",
          systemImage: "arrow.left.arrow.right",
          description: Text("Use Same As… on a grocery item to teach the app two names are the same.")
        )
      } else {
        ForEach(model.ingredientNameFixes) { fix in
          Button {
            editing = IngredientNameFixEditor.Draft(
              fromName: fix.fromName,
              toName: fix.toName,
              originalFromName: fix.fromName
            )
          } label: {
            HStack {
              Text(fix.fromName)
              Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
              Text(fix.toName)
            }
          }
          .swipeActions {
            Button("Delete", role: .destructive) {
              model.deleteIngredientNameFixButtonTapped(fromName: fix.fromName)
            }
          }
        }
      }
    }
    .navigationTitle("Name Fixes")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") { dismiss() }
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          editing = IngredientNameFixEditor.Draft(fromName: "", toName: "")
        } label: {
          Label("Add Name Fix", systemImage: "plus")
        }
      }
    }
    .sheet(item: $editing) { draft in
      NavigationStack {
        IngredientNameFixEditor(draft: draft) { from, to, originalFrom in
          model.saveIngredientNameFix(from: from, to: to, replacing: originalFrom)
        }
      }
    }
  }
}

private struct IngredientNameFixEditor: View {
  struct Draft: Identifiable {
    var fromName: String
    var toName: String
    var originalFromName: String? = nil
    var id: String { "\(fromName)→\(toName)" }
  }

  let draft: Draft
  let onSave: (String, String, String?) -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var fromName: String
  @State private var toName: String

  init(draft: Draft, onSave: @escaping (String, String, String?) -> Bool) {
    self.draft = draft
    self.onSave = onSave
    _fromName = State(initialValue: draft.fromName)
    _toName = State(initialValue: draft.toName)
  }

  var body: some View {
    Form {
      Section {
        StackedTextField(title: "From name", text: $fromName, prompt: "Ingredient spelling")
          .textInputAutocapitalization(.never)
        Text("Saves as: \(CanonicalIngredient.baseName(fromName) ?? "—")")
          .font(.caption)
          .foregroundStyle(.secondary)
        StackedTextField(title: "Same as", text: $toName, prompt: "Ingredient spelling")
          .textInputAutocapitalization(.never)
        Text("Saves as: \(CanonicalIngredient.baseName(toName) ?? "—")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Name Fix")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if onSave(fromName, toName, draft.originalFromName) { dismiss() }
        }
      }
    }
  }
}

struct SameAsPickerSheet: View {
  let itemID: GroceryItem.ID
  let rows: [GroceryItemRowData]
  let onSelect: (GroceryItem.ID) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      ForEach(rows.filter { $0.id != itemID }) { row in
        Button {
          onSelect(row.id)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(row.item.title)
            if let aisle = row.item.aisle {
              Text(aisle).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Same As…")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
    }
  }
}
