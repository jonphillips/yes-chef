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
  var isRepairingAnchor = false
  var errorTitle = "Could Not Load Variation"
  var errorMessage: String?
  var isShowingError = false
  var unresolvedAnchors: [RecipeVariationUnresolvedAnchor] = []
  var repairItems: [RecipeVariationAnchorRepairItem] = []
  private var hasLoaded = false

  init(recipeID: Recipe.ID, variationID: RecipeVariation.ID) {
    self.recipeID = recipeID
    self.variationID = variationID
    _baseDetail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
  }

  var isSaveDisabled: Bool {
    isSaving || isRepairingAnchor || !unresolvedAnchors.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var repairIngredientLines: [IngredientLine] {
    baseDetail?.ingredientLines.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var repairInstructionSteps: [InstructionStep] {
    baseDetail?.instructionGroups.flatMap(\.steps) ?? []
  }

  func baseDetailChanged(_ detail: RecipeDetailData?) {
    guard !hasLoaded, let detail, let variation = detail.variations.first(where: { $0.id == variationID }) else {
      return
    }
    do {
      let resolution = try detail.resolved(applying: variation)
      resolvedDetail = resolution.detail
      name = variation.name
      note = variation.note ?? ""
      unresolvedAnchors = resolution.unresolvedAnchors
      repairItems = try RecipeRepository.variationAnchorRepairItems(for: variation, in: detail)
      hasLoaded = true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }

  func repairAnchor(
    _ item: RecipeVariationAnchorRepairItem,
    reanchoringTo targetID: UUID?
  ) async {
    guard !isRepairingAnchor else { return }
    isRepairingAnchor = true
    defer { isRepairingAnchor = false }
    let now = now
    do {
      let variation = try await database.write { db in
        try RecipeRepository.repairVariationAnchor(
          item.address,
          in: variationID,
          reanchoringTo: targetID,
          in: db,
          now: now
        )
      }
      guard var detail = baseDetail,
        let variationIndex = detail.variations.firstIndex(where: { $0.id == variation.id })
      else { return }
      detail.variations[variationIndex] = variation
      let resolution = try detail.resolved(applying: variation)
      resolvedDetail = resolution.detail
      unresolvedAnchors = resolution.unresolvedAnchors
      repairItems = try RecipeRepository.variationAnchorRepairItems(for: variation, in: detail)
    } catch {
      errorTitle = "Could Not Repair Variation"
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
      errorTitle = "Could Not Save Variation"
      errorMessage = error.localizedDescription
      isShowingError = true
      return .failed
    }
  }

  func splitOffButtonTapped(title: String) async -> Bool {
    guard let resolvedDetail else { return false }
    isSaving = true
    defer { isSaving = false }
    let now = now
    let makeUUID = uuid
    do {
      _ = try await database.write { db in
        try RecipeRepository.splitVariationOff(
          variationID, resolvedDetail: resolvedDetail, name: title,
          in: db, now: now, uuid: { makeUUID() }
        )
      }
      return true
    } catch {
      errorTitle = "Could Not Split Off Variation"
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
  @State private var isNamingSplitOff = false
  @State private var splitOffTitleDraft = ""
  @State private var isRepairingAnchors = false

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
      if !model.unresolvedAnchors.isEmpty {
        Section {
          RecipeVariationRepairNotice(
            anchors: model.unresolvedAnchors,
            blocksSaving: true
          )
          Button("Repair Anchors", systemImage: "wrench.and.screwdriver") {
            isRepairingAnchors = true
          }
        }
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
    .alert(model.errorTitle, isPresented: $model.isShowingError) {
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
        splitOffTitleDraft = model.name
        unrepresentableEdits = []
        isNamingSplitOff = true
      }
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text(unrepresentableEdits.map { "\($0.description) can’t be kept in a variation." }.joined(separator: "\n"))
    }
    .alert("Split Off as Recipe", isPresented: $isNamingSplitOff) {
      TextField("Recipe name", text: $splitOffTitleDraft)
      Button("Save") {
        let title = splitOffTitleDraft
        Task {
          if await model.splitOffButtonTapped(title: title) { dismiss() }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This creates a new standalone recipe and removes the variation.")
    }
    .sheet(isPresented: $isRepairingAnchors) {
      NavigationStack {
        RecipeVariationAnchorRepairView(model: model)
      }
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

private struct RecipeVariationAnchorRepairView: View {
  @Environment(\.dismiss) private var dismiss
  let model: RecipeVariationEditorModel
  @State private var discardingItem: RecipeVariationAnchorRepairItem?

  var body: some View {
    List {
      if model.repairItems.isEmpty {
        ContentUnavailableView(
          "All Anchors Repaired",
          systemImage: "checkmark.circle",
          description: Text("This variation is ready to save.")
        )
      } else {
        ForEach(model.repairItems) { item in
          repairSection(item)
        }
      }
    }
    .navigationTitle("Repair Variation")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
          .disabled(model.isRepairingAnchor)
      }
    }
    .confirmationDialog(
      "Discard this variation change?",
      isPresented: Binding(
        get: { discardingItem != nil },
        set: { if !$0 { discardingItem = nil } }
      ),
      titleVisibility: .visible,
      presenting: discardingItem
    ) { item in
      Button("Discard Change", role: .destructive) {
        Task {
          await model.repairAnchor(item, reanchoringTo: nil)
          discardingItem = nil
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { item in
      Text("This removes the variation change anchored to “\(item.originalText)”.")
    }
  }

  @ViewBuilder
  private func repairSection(_ item: RecipeVariationAnchorRepairItem) -> some View {
    Section {
      Text(item.originalText)
        .font(.headline)
      Text("Choose the current recipe row this change should use.")
        .foregroundStyle(.secondary)
      switch item.kind {
      case .ingredient:
        ForEach(model.repairIngredientLines) { line in
          Button {
            Task { await model.repairAnchor(item, reanchoringTo: line.id) }
          } label: {
            Text(line.originalText)
          }
          .disabled(model.isRepairingAnchor)
        }
      case .instructionStep:
        ForEach(model.repairInstructionSteps) { step in
          Button {
            Task { await model.repairAnchor(item, reanchoringTo: step.id) }
          } label: {
            Text(step.text)
          }
          .disabled(model.isRepairingAnchor)
        }
      }
      Button("Discard This Change", role: .destructive) {
        discardingItem = item
      }
      .disabled(model.isRepairingAnchor)
    } header: {
      Label(item.kind == .ingredient ? "Ingredient Anchor" : "Instruction Anchor", systemImage: "link.badge.plus")
    }
  }
}

private struct VariationIngredientSectionEditor: View {
  let section: IngredientSection
  let model: RecipeVariationEditorModel

  var body: some View {
    if model.resolvedDetail?.ingredientSections.contains(where: { $0.id == section.id }) == true {
      if let name = section.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        Text(name)
          .font(.subheadline.bold())
          .foregroundStyle(.secondary)
      }
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
      if let name = section.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        Text(name)
          .font(.subheadline.bold())
          .foregroundStyle(.secondary)
      }
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
