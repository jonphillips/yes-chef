import PhotosUI
import SwiftUI
import UIKit
import YesChefCore

struct RecipeEditorView: View {
  @State private var model: RecipeEditorModel
  @State private var selectedHeroPhotoItem: PhotosPickerItem?
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

      Section("Photo") {
        RecipeHeroPhotoPickerRow(
          model: model,
          selectedItem: $selectedHeroPhotoItem
        )
      }

      Section("Source") {
        NavigationLink {
          RecipeSourceEditorView(model: model)
        } label: {
          RecipeSourceSummaryRow(
            title: model.draft.sourceSummaryTitle,
            detail: model.draft.sourceSummaryDetail,
            hasSource: model.draft.hasVisibleSourceData
          )
        }
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
        StackedTextField(title: "Section title", text: $model.draft.ingredientSectionName)
        StackedTextEditor(
          title: "Ingredients",
          text: $model.draft.ingredientText,
          minHeight: 180,
          font: .body.monospacedDigit()
        )
        .onChange(of: model.draft.ingredientText) { _, _ in
          model.ingredientTextChanged()
        }

        ForEach($model.draft.ingredientLineDrafts) { $line in
          IngredientLineStructureEditor(line: $line)
        }
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

private struct RecipeHeroPhotoPickerRow: View {
  let model: RecipeEditorModel
  @Binding var selectedItem: PhotosPickerItem?

  var body: some View {
    let hasPhoto = model.heroPhotoPreviewData != nil

    VStack(alignment: .leading, spacing: 12) {
      if let data = model.heroPhotoPreviewData {
        RecipeHeroPhotoPreview(data: data)
      }

      PhotosPicker(selection: $selectedItem, matching: .images) {
        Label(hasPhoto ? "Change Photo" : "Add Photo", systemImage: "photo.badge.plus")
      }
      .onChange(of: selectedItem) { _, item in
        guard let item else { return }
        Task {
          do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
              selectedItem = nil
              return
            }
            await model.heroPhotoSelected(
              sourceData: data,
              sourcePath: sourcePath(for: item)
            )
          } catch {
            model.heroPhotoSelectionFailed(error)
          }
          selectedItem = nil
        }
      }
    }
  }

  private func sourcePath(for item: PhotosPickerItem) -> String {
    guard let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension else {
      return "Photo Library"
    }
    return "Photo Library.\(fileExtension)"
  }
}

private struct RecipeHeroPhotoPreview: View {
  let data: Data

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)

      if let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .font(.title)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 180)
    .clipShape(.rect(cornerRadius: 8))
    .accessibilityLabel(Text("Recipe photo"))
  }
}

private struct RecipeSourceSummaryRow: View {
  let title: String
  let detail: String?
  let hasSource: Bool

  var body: some View {
    StackedFormField(title: "Source") {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Image(systemName: "book")
          .foregroundStyle(.secondary)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .foregroundStyle(hasSource ? .primary : .secondary)
          if let detail {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }
      }
    }
  }
}

private struct RecipeSourceEditorView: View {
  let model: RecipeEditorModel

  var body: some View {
    @Bindable var model = model

    Form {
      Section("Identity") {
        StackedTextField(title: "Source name", text: $model.draft.sourceName)
        StackedTextField(title: "Author", text: $model.draft.sourceAuthor)
        StackedTextField(title: "URL", text: $model.draft.sourceURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
      }

      Section("Publication or Book") {
        StackedTextField(title: "Publication", text: $model.draft.sourcePublicationName)
        StackedTextField(title: "Book title", text: $model.draft.sourceBookTitle)
        StackedTextField(title: "Page", text: $model.draft.sourcePageNumber)
      }

      Section("Notes") {
        StackedTextField(title: "Source notes", text: $model.draft.sourceNotes, axis: .vertical)
      }
    }
    .navigationTitle("Source")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct IngredientLineStructureEditor: View {
  @Binding var line: RecipeIngredientLineDraft

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(line.originalText)
        .font(.subheadline)
      Toggle("Header", isOn: $line.isHeader)
      StackedTextField(title: "Substitution", text: $line.substitution, axis: .vertical)
    }
    .padding(.vertical, 4)
  }
}

private extension RecipeEditorDraft {
  var hasVisibleSourceData: Bool {
    [
      sourceName,
      sourceURL,
      sourceAuthor,
      sourcePublicationName,
      sourceBookTitle,
      sourcePageNumber,
      sourceNotes,
    ]
    .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  var sourceSummaryTitle: String {
    firstNonEmpty(sourceName, publicationNameDisplay, sourceBookTitle, sourceURL) ?? "No source"
  }

  var sourceSummaryDetail: String? {
    let details = [
      sourceAuthor.nonEmpty.map { "Author: \($0)" },
      sourceURL.nonEmpty,
    ].compactMap(\.self)
    guard !details.isEmpty else { return nil }
    return details.joined(separator: " | ")
  }

  private var publicationNameDisplay: String? {
    firstNonEmpty(sourcePublicationName, sourceBookTitle)
  }

  private func firstNonEmpty(_ values: String?...) -> String? {
    values.lazy.compactMap { $0?.nonEmpty }.first
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
