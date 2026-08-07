import Foundation
import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class RecipeEditorModel {
  let recipeID: Recipe.ID?

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?
  @ObservationIgnored
  @Fetch(CategoryListRequest(), animation: .default) var categories: [YesChefCore.Category] = []
  @ObservationIgnored
  @Fetch(FacetListRequest(), animation: .default) var facets: [Facet] = []

  var draft = RecipeEditorDraft()
  var errorMessage: String?
  var isShowingError = false
  var isSaving = false
  private var hasLoadedDraft = false

  init(recipeID: Recipe.ID?) {
    self.recipeID = recipeID
    if let recipeID {
      _detail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
    } else {
      _detail = Fetch(wrappedValue: nil)
    }
  }

  /// Seeds a brand-new recipe's structured half with an already-populated draft — the Create Recipe
  /// destination hands the editor an extraction result (ADR-0053 D2). There is no `recipeID` to fetch,
  /// and `hasLoadedDraft` starts true so the (empty) detail observation never clobbers the seed.
  init(seededDraft: RecipeEditorDraft) {
    recipeID = nil
    _detail = Fetch(wrappedValue: nil)
    draft = seededDraft
    hasLoadedDraft = true
  }

  /// Replaces the structured draft with a fresh extraction result while a Create Recipe session is
  /// open. The source material that produced it lives on `CreateRecipeModel`, so a re-extraction
  /// re-seeds the form without losing what the cook supplied (ADR-0053 D4).
  func applyExtractedDraft(_ extracted: RecipeEditorDraft) {
    draft = extracted
    hasLoadedDraft = true
  }

  var isSavingDisabled: Bool {
    isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Non-nil when the reader has a variation selected. The editor writes to the base regardless, so
  /// the view surfaces this rather than letting the write land silently — see
  /// `RecipeVariationBaseWriteGuard`.
  var activeVariationName: String? {
    guard let name = detail?.activeVariation?.name.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    else { return nil }
    return name
  }

  var categoryRows: [CategoryHierarchy.DisplayRow] {
    CategoryHierarchy.displayRows(from: categories)
  }

  var categorySections: [RecipeCategorySelectionSection] {
    RecipeCategorySelectionSection.sections(categories: categories, facets: facets)
  }

  var selectedCategoryIDs: Set<YesChefCore.Category.ID> {
    draft.selectedCategoryIDs ?? []
  }

  var selectedCategorySummary: String {
    let selectedNames: [String] = categorySections
      .flatMap { section in
        section.rows.compactMap { row -> String? in
          guard selectedCategoryIDs.contains(row.category.id) else { return nil }
          return section.facetName.map { "\($0) > \(row.displayName)" } ?? row.displayName
        }
      }
    guard !selectedNames.isEmpty else { return "No categories" }
    return selectedNames.joined(separator: ", ")
  }

  var pendingHeroPhoto: RecipeEditorPhotoDraft? {
    draft.pendingPhotos.last { $0.kind == .hero }
  }

  var heroPhotoPreviewData: Data? {
    if let pendingHeroPhoto {
      return pendingHeroPhoto.processedPhoto.thumbnailData ?? pendingHeroPhoto.processedPhoto.displayData
    }
    // The editor preview prefers the carried thumbnail; the detail fetch no longer
    // holds full-res bytes (ADR-0029 Amd2 S5b), so a thumbnail-less photo falls
    // through to the placeholder here rather than pulling megabytes.
    return detail?.photos
      .filter { photo in
        photo.kind != .referenceDocument && photo.thumbnailData != nil
      }
      .sorted { lhs, rhs in
        if lhs.kind != rhs.kind {
          return lhs.kind == .hero
        }
        return lhs.sortOrder < rhs.sortOrder
      }
      .lazy
      .compactMap(\.thumbnailData)
      .first
  }

  func detailChanged(_ detail: RecipeDetailData?) {
    guard !hasLoadedDraft, let detail else { return }
    draft = RecipeEditorDraft(detail: detail)
    hasLoadedDraft = true
  }

  func categorySelectionButtonTapped(_ categoryID: YesChefCore.Category.ID) {
    var categoryIDs = selectedCategoryIDs
    if categoryIDs.contains(categoryID) {
      categoryIDs.remove(categoryID)
    } else {
      categoryIDs.insert(categoryID)
    }
    draft.selectedCategoryIDs = categoryIDs
    draft.categoryNames = categoryRows
      .filter { categoryIDs.contains($0.category.id) }
      .map(\.displayName)
      .joined(separator: ", ")
  }

  func ingredientTextChanged(sectionID: IngredientSection.ID) -> IngredientSection.ID? {
    draft.ingredientTextChanged(sectionID: sectionID, uuid: { uuid() })
  }

  func ingredientSectionNameChanged(sectionID: IngredientSection.ID) {
    draft.ingredientSectionNameChanged(sectionID: sectionID)
  }

  func ingredientFractionTapped(_ fraction: ScaleFraction, sectionID: IngredientSection.ID) {
    guard let index = draft.ingredientSections.firstIndex(where: { $0.id == sectionID }) else { return }
    draft.ingredientSections[index].text = ScaleFraction.appending(
      fraction,
      to: draft.ingredientSections[index].text
    )
  }

  func addIngredientSection() {
    draft.ingredientSections.append(RecipeEditorIngredientSectionDraft(id: uuid()))
  }

  func deleteIngredientSection(id: IngredientSection.ID) {
    draft.ingredientSections.removeAll { $0.id == id }
  }

  func addInstructionSection() {
    draft.instructionSections.append(RecipeEditorInstructionSectionDraft(id: uuid()))
  }

  func deleteInstructionSection(id: InstructionSection.ID) {
    draft.instructionSections.removeAll { $0.id == id }
  }

  func heroPhotoSelected(sourceData: Data, sourcePath: String) async {
    let photoID = uuid()
    let processedPhoto = await Task.detached {
      RecipePhotoProcessor.process(
        sourceData: sourceData,
        sourcePath: sourcePath,
        kind: .hero
      )
    }
    .value
    draft.pendingPhotos.removeAll { $0.kind == .hero }
    draft.pendingPhotos.append(
      RecipeEditorPhotoDraft(
        id: photoID,
        processedPhoto: processedPhoto,
        originalSourcePath: sourcePath,
        kind: .hero,
        source: .user
      )
    )
    draft.removesHeroPhoto = false
  }

  func heroPhotoRemoved() {
    draft.pendingPhotos.removeAll { $0.kind == .hero }
    draft.removesHeroPhoto = true
  }

  func heroPhotoSelectionFailed(_ error: any Error) {
    errorMessage = String(describing: error)
    isShowingError = true
  }

  func saveButtonTapped() async -> Bool {
    guard !isSavingDisabled else { return false }
    isSaving = true
    defer { isSaving = false }

    let draft = draft
    let saveDate = now
    let makeUUID = uuid

    do {
      _ = try await database.write { db in
        try RecipeRepository.save(
          draft: draft,
          in: db,
          now: saveDate,
          uuid: { makeUUID() }
        )
      }
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }
}

struct RecipeCategorySelectionSection: Identifiable, Equatable {
  enum ID: Hashable {
    case facet(Facet.ID)
    case otherCategories
  }

  let id: ID
  let title: String
  let facetName: String?
  let rows: [CategoryHierarchy.DisplayRow]

  static func sections(
    categories: [YesChefCore.Category],
    facets: [Facet]
  ) -> [Self] {
    let facetSections = facets.map { facet in
      Self(
        id: .facet(facet.id),
        title: facet.name,
        facetName: facet.name,
        rows: CategoryHierarchy.displayRows(from: categories.filter { $0.facetID == facet.id })
      )
    }
    let looseRows = CategoryHierarchy.displayRows(from: categories.filter { $0.facetID == nil })
    guard !looseRows.isEmpty else { return facetSections }
    return facetSections + [
      Self(id: .otherCategories, title: "Other Categories", facetName: nil, rows: looseRows)
    ]
  }
}
