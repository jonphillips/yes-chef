import SwiftUI
import YesChefCore

struct RecipeEditorView: View {
  @State private var model: RecipeEditorModel
  @Environment(\.dismiss) private var dismiss

  init(model: RecipeEditorModel) {
    _model = State(wrappedValue: model)
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section("Recipe") {
        TextField("Title", text: $model.draft.title)
        TextField("Subtitle", text: $model.draft.subtitle)
        TextField("Summary", text: $model.draft.summary, axis: .vertical)
        Toggle("Favorite", isOn: $model.draft.favorite)
      }

      Section("Source") {
        TextField("Source name", text: $model.draft.sourceName)
        TextField("URL", text: $model.draft.sourceURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
      }

      Section("Timing and Yield") {
        TextField("Servings", text: $model.draft.servingsText)
        TextField("Yield", text: $model.draft.yieldText)
        Stepper(value: $model.draft.prepTimeMinutes, in: 0...600, step: 5) {
          Text("Prep: \(model.draft.prepTimeMinutes) min")
        }
        Stepper(value: $model.draft.cookTimeMinutes, in: 0...600, step: 5) {
          Text("Cook: \(model.draft.cookTimeMinutes) min")
        }
      }

      Section("Organization") {
        TextField("Cuisine", text: $model.draft.cuisine)
        TextField("Course", text: $model.draft.course)
        TextField("Tags", text: $model.draft.tagNames, prompt: Text("grill, make-ahead"))
        TextField("Categories", text: $model.draft.categoryNames, prompt: Text("Mains, Chicken"))
      }

      Section("Ingredients") {
        TextEditor(text: $model.draft.ingredientText)
          .frame(minHeight: 180)
          .font(.body.monospacedDigit())
      }

      Section("Instructions") {
        TextEditor(text: $model.draft.instructionText)
          .frame(minHeight: 220)
      }

      Section("Notes") {
        TextEditor(text: $model.draft.noteText)
          .frame(minHeight: 120)
      }
    }
    .navigationTitle(model.recipeID == nil ? "New Recipe" : "Edit Recipe")
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
        .disabled(model.isSavingDisabled)
      }
    }
    .onAppear {
      model.detailChanged(model.detail)
    }
    .onChange(of: model.detail) { _, detail in
      model.detailChanged(detail)
    }
    .alert("Could Not Save Recipe", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}
