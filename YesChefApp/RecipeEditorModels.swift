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

  var isSavingDisabled: Bool {
    isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var categoryRows: [CategoryHierarchy.DisplayRow] {
    CategoryHierarchy.displayRows(from: categories)
  }

  var selectedCategoryIDs: Set<YesChefCore.Category.ID> {
    draft.selectedCategoryIDs ?? []
  }

  var selectedCategorySummary: String {
    let selectedRows = categoryRows.filter { selectedCategoryIDs.contains($0.category.id) }
    guard !selectedRows.isEmpty else { return "No categories" }
    return selectedRows.map(\.displayName).joined(separator: ", ")
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

  func ingredientTextChanged() {
    var unmatchedDrafts = draft.ingredientLineDrafts.sorted { $0.sortOrder < $1.sortOrder }
    draft.ingredientLineDrafts = draft.ingredientText
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .enumerated()
      .map { index, text in
        if let matchIndex = unmatchedDrafts.firstIndex(where: { $0.originalText == text && $0.sortOrder == index })
          ?? unmatchedDrafts.firstIndex(where: { $0.originalText == text })
        {
          var draft = unmatchedDrafts.remove(at: matchIndex)
          draft.sortOrder = index
          return draft
        }
        return RecipeIngredientLineDraft(
          id: uuid(),
          originalText: text,
          isHeader: text.hasSuffix(":"),
          sortOrder: index
        )
      }
  }

  func ingredientFractionTapped(_ fraction: ScaleFraction) {
    draft.ingredientText = ScaleFraction.appending(fraction, to: draft.ingredientText)
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
