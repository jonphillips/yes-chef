import SwiftUI
import YesChefCore

struct RecipeEditorView: View {
  @State private var model: RecipeEditorModel
  @Environment(\.dismiss) private var dismiss

  init(recipeID: Recipe.ID?) {
    _model = State(wrappedValue: RecipeEditorModel(recipeID: recipeID))
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section("Recipe") {
        StackedTextField(title: "Title", text: $model.draft.title)
        StackedTextField(title: "Subtitle", text: $model.draft.subtitle)
        StackedTextField(title: "Summary", text: $model.draft.summary, axis: .vertical)
        Toggle("Favorite", isOn: $model.draft.favorite)
      }

      Section("Source") {
        StackedTextField(title: "Source name", text: $model.draft.sourceName)
        StackedTextField(title: "URL", text: $model.draft.sourceURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
        StackedTextField(title: "Author", text: $model.draft.sourceAuthor)
        StackedTextField(title: "Publication", text: $model.draft.sourcePublicationName)
        StackedTextField(title: "Book title", text: $model.draft.sourceBookTitle)
        StackedTextField(title: "Page", text: $model.draft.sourcePageNumber)
        StackedTextField(title: "Source notes", text: $model.draft.sourceNotes, axis: .vertical)
      }

      Section("Timing and Yield") {
        StackedTextField(title: "Servings", text: $model.draft.servingsText)
        StackedTextField(title: "Yield", text: $model.draft.yieldText)
        Stepper(value: $model.draft.prepTimeMinutes, in: 0...600, step: 5) {
          Text("Prep: \(model.draft.prepTimeMinutes) min")
        }
        Stepper(value: $model.draft.cookTimeMinutes, in: 0...600, step: 5) {
          Text("Cook: \(model.draft.cookTimeMinutes) min")
        }
      }

      Section("Organization") {
        Picker("Library", selection: $model.draft.libraryPlacement) {
          ForEach(RecipeLibraryPlacement.allCases, id: \.self) { placement in
            Text(placement.title)
              .tag(placement)
          }
        }
        StackedTextField(title: "Cuisine", text: $model.draft.cuisine)
        StackedTextField(title: "Course", text: $model.draft.course)
        StackedTextField(title: "Tags", text: $model.draft.tagNames, prompt: "grill, make-ahead")
        RecipeCategorySelectionField(model: model)
      }

      Section("Ingredients") {
        StackedTextEditor(
          title: "Ingredients",
          text: $model.draft.ingredientText,
          minHeight: 180,
          font: .body.monospacedDigit()
        )
      }

      Section("Instructions") {
        StackedTextEditor(
          title: "Instructions",
          text: $model.draft.instructionText,
          minHeight: 220
        )
      }

      Section("Notes") {
        StackedTextEditor(
          title: "Notes",
          text: $model.draft.noteText,
          minHeight: 120
        )
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
