import PhotosUI
import SwiftUI
import UIKit
import YesChefCore

struct RecipeEditorView: View {
  @State private var model: RecipeEditorModel
  @State private var selectedHeroPhotoItem: PhotosPickerItem?
  @State private var ingredientSelections: [IngredientSection.ID: TextSelection] = [:]
  @State private var ingredientSelectionUTF16Offsets: [IngredientSection.ID: Int] = [:]
  @FocusState private var focusedIngredientSectionID: IngredientSection.ID?
  @FocusState private var focusedIngredientSectionNameID: IngredientSection.ID?
  @Environment(\.dismiss) private var dismiss

  init(recipeID: Recipe.ID?) {
    _model = State(wrappedValue: RecipeEditorModel(recipeID: recipeID))
  }

  var body: some View {
    @Bindable var model = model

    Form {
      if let variationName = model.activeVariationName {
        Section {
          RecipeVariationBaseWriteNotice(variationName: variationName)
        }
      }

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

      ForEach($model.draft.ingredientSections) { $section in
        Section {
          StackedTextField(
            title: "Section title",
            text: $section.name,
            focusedSectionID: $focusedIngredientSectionNameID,
            focusedSectionValue: section.id
          ) {
            model.ingredientSectionNameChanged(sectionID: section.id)
            pruneIngredientSelections()
          }
          StackedTextEditor(
            title: "Ingredients",
            text: $section.text,
            selection: ingredientSelectionBinding(for: section.id),
            minHeight: 180,
            font: .body.monospacedDigit()
          )
          .focused($focusedIngredientSectionID, equals: section.id)
          .onChange(of: section.text) { _, _ in
            if let newSectionID = model.ingredientTextChanged(sectionID: section.id) {
              focusedIngredientSectionID = newSectionID
            }
            ingredientSelections[section.id] = nil
            ingredientSelectionUTF16Offsets[section.id] = nil
            pruneIngredientSelections()
          }
          .contextMenu {
            if let lineIndex = selectedIngredientLineIndex(in: section) {
              Button("Start a section here") {
                if let newSectionID = model.startIngredientSection(sectionID: section.id, atLineIndex: lineIndex) {
                  focusedIngredientSectionID = newSectionID
                }
                ingredientSelections[section.id] = nil
                ingredientSelectionUTF16Offsets[section.id] = nil
                pruneIngredientSelections()
              }
            }
          }

          if model.draft.ingredientSections.count > 1 {
            Button(role: .destructive) {
              model.deleteIngredientSection(id: section.id)
            } label: {
              Label("Delete Section", systemImage: "trash")
            }
          }
        } header: {
          if section.id == model.draft.ingredientSections.first?.id {
            Text("Ingredients")
          }
        }
      }

      Section {
        Button {
          model.addIngredientSection()
        } label: {
          Label("Add Ingredient Section", systemImage: "plus")
        }
      }

      ForEach($model.draft.instructionSections) { $section in
        Section {
          StackedTextField(title: "Section title", text: $section.name)
          StackedTextEditor(
            title: "Instructions",
            text: $section.text,
            minHeight: 220
          )

          if model.draft.instructionSections.count > 1 {
            Button(role: .destructive) {
              model.deleteInstructionSection(id: section.id)
            } label: {
              Label("Delete Section", systemImage: "trash")
            }
          }
        } header: {
          if section.id == model.draft.instructionSections.first?.id {
            Text("Instructions")
          }
        }
      }

      Section {
        Button {
          model.addInstructionSection()
        } label: {
          Label("Add Instruction Section", systemImage: "plus")
        }
      }

      Section("Notes") {
        StackedTextEditor(
          title: "Notes",
          text: $model.draft.noteText,
          minHeight: 120
        )
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let focusedIngredientSectionID {
        IngredientFractionPillRow { fraction in
          model.ingredientFractionTapped(fraction, sectionID: focusedIngredientSectionID)
          self.focusedIngredientSectionID = focusedIngredientSectionID
        }
        .padding(.horizontal)
        .background(.bar)
        .overlay(alignment: .top) {
          Divider()
        }
      }
    }
    .navigationTitle(model.recipeID == nil ? "New Recipe" : "Edit Recipe")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          .disabled(model.isSaving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button {
          if let focusedIngredientSectionNameID {
            model.ingredientSectionNameChanged(sectionID: focusedIngredientSectionNameID)
            self.focusedIngredientSectionNameID = nil
            pruneIngredientSelections()
          }
          Task {
            if await model.saveButtonTapped() {
              dismiss()
            }
          }
        } label: {
          if model.isSaving {
            ProgressView()
          } else {
            Text("Save")
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
    .onChange(of: focusedIngredientSectionNameID) { oldValue, newValue in
      guard let oldValue, oldValue != newValue else { return }
      model.ingredientSectionNameChanged(sectionID: oldValue)
      pruneIngredientSelections()
    }
    .alert("Could Not Save Recipe", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private func ingredientSelectionBinding(
    for sectionID: IngredientSection.ID
  ) -> Binding<TextSelection?> {
    Binding(
      get: { ingredientSelections[sectionID] },
      set: { selection in
        ingredientSelections[sectionID] = selection
        let currentText = model.draft.ingredientSections
          .first { $0.id == sectionID }?
          .text ?? ""
        ingredientSelectionUTF16Offsets[sectionID] = selection
          .flatMap { selectionUTF16Offset($0, in: currentText) }
      }
    )
  }

  private func selectedIngredientLineIndex(
    in section: RecipeEditorIngredientSectionDraft
  ) -> Int? {
    guard let offset = ingredientSelectionUTF16Offsets[section.id],
      (0...section.text.utf16.count).contains(offset)
    else { return nil }

    let utf16 = section.text.utf16
    guard
      let utf16Index = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex),
      let startIndex = String.Index(utf16Index, within: section.text)
    else { return nil }
    let endIndex = section.text[startIndex...].firstIndex(where: \.isNewline) ?? section.text.endIndex
    guard !section.text[startIndex..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }

    return section.text.utf16.prefix(offset).reduce(into: 0) { lineCount, codeUnit in
      if codeUnit == 10 { lineCount += 1 }
    }
  }

  private func selectionUTF16Offset(_ selection: TextSelection, in text: String) -> Int? {
    guard case let .selection(range) = selection.indices else { return nil }
    // A collapsed caret is transient while the editor applies a text mutation (notably Return at
    // the end of a card). It cannot identify a line for the context-menu action anyway.
    guard range.lowerBound != range.upperBound else { return nil }
    guard let utf16Index = range.lowerBound.samePosition(in: text.utf16) else { return nil }
    return text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
  }

  private func pruneIngredientSelections() {
    let sectionIDs = Set(model.draft.ingredientSections.map(\.id))
    ingredientSelections = ingredientSelections.filter { sectionIDs.contains($0.key) }
    ingredientSelectionUTF16Offsets = ingredientSelectionUTF16Offsets.filter { sectionIDs.contains($0.key) }
  }
}

private struct IngredientFractionPillRow: View {
  let onSelect: (ScaleFraction) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ScaleFraction.ingredientInputCases) { fraction in
          Button {
            onSelect(fraction)
          } label: {
            Text(verbatim: fraction.label)
              .font(.title3)
              .frame(minWidth: 44, minHeight: 36)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .accessibilityLabel(Text(verbatim: "Insert " + fraction.label))
          .accessibilityHint(Text("Appends this fraction to the ingredient text."))
        }
      }
      .padding(.horizontal, 2)
    }
    .padding(.vertical, 2)
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

      HStack(alignment: .firstTextBaseline, spacing: 12) {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          Label(hasPhoto ? "Change Photo" : "Add Photo", systemImage: "photo.badge.plus")
        }
        .buttonStyle(.bordered)
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

        if hasPhoto {
          Button(role: .destructive) {
            model.heroPhotoRemoved()
          } label: {
            Label("Delete Photo", systemImage: "trash")
          }
          .buttonStyle(.bordered)
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
