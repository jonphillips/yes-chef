import SwiftUI
import YesChefCore

struct MarkCookedView: View {
  @State private var model: MarkCookedModel
  @Environment(\.dismiss) private var dismiss

  init(model: MarkCookedModel) {
    _model = State(wrappedValue: model)
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section("Retrospective") {
        TextEditor(text: $model.noteText)
          .frame(minHeight: 180)
      }
    }
    .navigationTitle("Mark Cooked")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveButtonTapped() {
            dismiss()
          }
        }
      }
    }
    .alert("Could Not Mark Cooked", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}
