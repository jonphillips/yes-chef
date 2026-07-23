import Dependencies
import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class RecipeVariationEditorModel {
  enum SaveResult: Equatable {
    case saved
    case needsSplitOff([RecipeVariationUnrepresentableEdit])
    case failed
  }

  let recipeID: Recipe.ID
  let variationID: RecipeVariation.ID

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @Fetch var baseDetail: RecipeDetailData?

  var resolvedDetail: RecipeDetailData?
  var name = ""
  var note = ""
  var isSaving = false
  var errorMessage: String?
  var isShowingError = false
  private var hasLoaded = false

  init(recipeID: Recipe.ID, variationID: RecipeVariation.ID) {
    self.recipeID = recipeID
    self.variationID = variationID
    _baseDetail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
  }

  var isSaveDisabled: Bool {
    isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func baseDetailChanged(_ detail: RecipeDetailData?) {
    guard !hasLoaded, let detail, let variation = detail.variations.first(where: { $0.id == variationID }) else {
      return
    }
    do {
      resolvedDetail = try detail.resolved(applying: variation)
      name = variation.name
      note = variation.note ?? ""
      hasLoaded = true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }

  func addIngredientSection() {
    guard var detail = resolvedDetail else { return }
    detail.ingredientSections.append(
      IngredientSection(
        id: uuid(), recipeID: recipeID, name: nil,
        sortOrder: (detail.ingredientSections.map(\.sortOrder).max() ?? -1) + 1
      )
    )
    resolvedDetail = detail
  }

  func addIngredientLine(to sectionID: IngredientSection.ID) {
    guard var detail = resolvedDetail else { return }
    let sortOrder = (detail.ingredientLines.filter { $0.sectionID == sectionID }.map(\.sortOrder).max() ?? -1) + 1
    detail.ingredientLines.append(
      IngredientLine(id: uuid(), recipeID: recipeID, sectionID: sectionID, originalText: "", sortOrder: sortOrder)
    )
    resolvedDetail = detail
  }

  func removeIngredientLine(_ id: IngredientLine.ID) {
    guard var detail = resolvedDetail else { return }
    detail.ingredientLines.removeAll { $0.id == id }
    resolvedDetail = detail
  }

  func addInstructionSection() {
    guard var detail = resolvedDetail else { return }
    detail.instructionSections.append(
      InstructionSection(
        id: uuid(), recipeID: recipeID, name: nil,
        sortOrder: (detail.instructionSections.map(\.sortOrder).max() ?? -1) + 1
      )
    )
    resolvedDetail = detail
  }

  func addInstructionStep(to sectionID: InstructionSection.ID) {
    guard var detail = resolvedDetail else { return }
    let sortOrder = (detail.instructionSteps.filter { $0.sectionID == sectionID }.map(\.sortOrder).max() ?? -1) + 1
    detail.instructionSteps.append(
      InstructionStep(id: uuid(), recipeID: recipeID, sectionID: sectionID, text: "", sortOrder: sortOrder)
    )
    resolvedDetail = detail
  }

  func removeInstructionStep(_ id: InstructionStep.ID) {
    guard var detail = resolvedDetail else { return }
    detail.instructionSteps.removeAll { $0.id == id }
    resolvedDetail = detail
  }

  func ingredientSectionName(_ id: IngredientSection.ID) -> Binding<String> {
    Binding(
      get: { self.resolvedDetail?.ingredientSections.first { $0.id == id }?.name ?? "" },
      set: { text in
        guard var detail = self.resolvedDetail,
          let index = detail.ingredientSections.firstIndex(where: { $0.id == id })
        else { return }
        detail.ingredientSections[index].name = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        self.resolvedDetail = detail
      }
    )
  }

  func ingredientLineText(_ id: IngredientLine.ID) -> Binding<String> {
    Binding(
      get: { self.resolvedDetail?.ingredientLines.first { $0.id == id }?.originalText ?? "" },
      set: { text in
        guard var detail = self.resolvedDetail,
          let index = detail.ingredientLines.firstIndex(where: { $0.id == id })
        else { return }
        detail.ingredientLines[index].originalText = text
        self.resolvedDetail = detail
      }
    )
  }

  func instructionSectionName(_ id: InstructionSection.ID) -> Binding<String> {
    Binding(
      get: { self.resolvedDetail?.instructionSections.first { $0.id == id }?.name ?? "" },
      set: { text in
        guard var detail = self.resolvedDetail,
          let index = detail.instructionSections.firstIndex(where: { $0.id == id })
        else { return }
        detail.instructionSections[index].name = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        self.resolvedDetail = detail
      }
    )
  }

  func instructionStepText(_ id: InstructionStep.ID) -> Binding<String> {
    Binding(
      get: { self.resolvedDetail?.instructionSteps.first { $0.id == id }?.text ?? "" },
      set: { text in
        guard var detail = self.resolvedDetail,
          let index = detail.instructionSteps.firstIndex(where: { $0.id == id })
        else { return }
        detail.instructionSteps[index].text = text
        self.resolvedDetail = detail
      }
    )
  }

  func saveButtonTapped() async -> SaveResult {
    guard !isSaveDisabled, let resolvedDetail else { return .failed }
    isSaving = true
    defer { isSaving = false }
    let now = now
    let name = name
    let note = note
    do {
      let derivation = try await database.write { db in
        try RecipeRepository.saveEditedVariation(
          variationID, resolvedDetail: resolvedDetail, name: name, note: note,
          in: db, now: now
        )
      }
      return derivation.isRepresentable ? .saved : .needsSplitOff(derivation.unrepresentableEdits)
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return .failed
    }
  }

  func splitOffButtonTapped() async -> Bool {
    guard let resolvedDetail else { return false }
    isSaving = true
    defer { isSaving = false }
    let now = now
    let name = name
    let makeUUID = uuid
    do {
      _ = try await database.write { db in
        try RecipeRepository.splitVariationOff(
          variationID, resolvedDetail: resolvedDetail, name: name,
          in: db, now: now, uuid: { makeUUID() }
        )
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }
}

struct RecipeVariationEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model: RecipeVariationEditorModel
  @State private var unrepresentableEdits: [RecipeVariationUnrepresentableEdit] = []

  init(recipeID: Recipe.ID, variationID: RecipeVariation.ID) {
    _model = State(wrappedValue: RecipeVariationEditorModel(recipeID: recipeID, variationID: variationID))
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section("Variation") {
        TextField("Name", text: $model.name)
        TextField("Method note", text: $model.note, axis: .vertical)
      }
      if let detail = model.resolvedDetail {
        ingredients(detail: detail, model: model)
        instructions(detail: detail, model: model)
      } else {
        ContentUnavailableView("Loading Variation", systemImage: "square.stack.3d.up")
      }
    }
    .navigationTitle("Edit Variation")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          .disabled(model.isSaving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          Task {
            switch await model.saveButtonTapped() {
            case .saved:
              dismiss()
            case let .needsSplitOff(edits):
              unrepresentableEdits = edits
            case .failed:
              break
            }
          }
        }
        .disabled(model.isSaveDisabled)
      }
    }
    .onAppear { model.baseDetailChanged(model.baseDetail) }
    .onChange(of: model.baseDetail) { _, detail in model.baseDetailChanged(detail) }
    .alert("Could Not Save Variation", isPresented: $model.isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "Something went wrong.")
    }
    .confirmationDialog(
      "Keep every change?",
      isPresented: Binding(
        get: { !unrepresentableEdits.isEmpty },
        set: { if !$0 { unrepresentableEdits = [] } }
      ),
      titleVisibility: .visible
    ) {
      Button("Split Off as Recipe") {
        Task {
          if await model.splitOffButtonTapped() { dismiss() }
        }
      }
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text(unrepresentableEdits.map { "\($0.description) can’t be kept in a variation." }.joined(separator: "\n"))
    }
  }

  @ViewBuilder
  private func ingredients(detail: RecipeDetailData, model: RecipeVariationEditorModel) -> some View {
    Section("Ingredients") {
      ForEach(detail.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }) { section in
        VariationIngredientSectionEditor(section: section, model: model)
      }
      Button("Add Ingredient Section", systemImage: "plus") { model.addIngredientSection() }
    }
  }

  @ViewBuilder
  private func instructions(detail: RecipeDetailData, model: RecipeVariationEditorModel) -> some View {
    Section("Instructions") {
      ForEach(detail.instructionSections.sorted { $0.sortOrder < $1.sortOrder }) { section in
        VariationInstructionSectionEditor(section: section, model: model)
      }
      Button("Add Instruction Section", systemImage: "plus") { model.addInstructionSection() }
    }
  }
}

private struct VariationIngredientSectionEditor: View {
  let section: IngredientSection
  let model: RecipeVariationEditorModel

  var body: some View {
    if model.resolvedDetail?.ingredientSections.contains(where: { $0.id == section.id }) == true {
      TextField("Section", text: model.ingredientSectionName(section.id))
      ForEach(model.resolvedDetail?.ingredientLines.filter { $0.sectionID == section.id } ?? []) { line in
        TextField("Ingredient", text: model.ingredientLineText(line.id))
          .swipeActions {
            Button(role: .destructive) { model.removeIngredientLine(line.id) } label: {
              Label("Delete", systemImage: "trash")
            }
          }
      }
      Button("Add Ingredient", systemImage: "plus") { model.addIngredientLine(to: section.id) }
    }
  }
}

private struct VariationInstructionSectionEditor: View {
  let section: InstructionSection
  let model: RecipeVariationEditorModel

  var body: some View {
    if model.resolvedDetail?.instructionSections.contains(where: { $0.id == section.id }) == true {
      TextField("Section", text: model.instructionSectionName(section.id))
      ForEach(model.resolvedDetail?.instructionSteps.filter { $0.sectionID == section.id } ?? []) { step in
        TextField("Instruction", text: model.instructionStepText(step.id), axis: .vertical)
          .swipeActions {
            Button(role: .destructive) { model.removeInstructionStep(step.id) } label: {
              Label("Delete", systemImage: "trash")
            }
          }
      }
      Button("Add Instruction", systemImage: "plus") { model.addInstructionStep(to: section.id) }
    }
  }
}
