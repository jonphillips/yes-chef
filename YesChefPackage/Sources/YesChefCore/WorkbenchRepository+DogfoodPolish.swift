import Foundation
import SQLiteData

extension WorkbenchRepository {
  public static func candidateLinks(
    forRecipeID recipeID: Recipe.ID,
    in db: Database
  ) throws -> [WorkbenchCandidateLink] {
    let workbenchIDs = try Workbench
      .where { $0.draftRecipeID.eq(recipeID) }
      .fetchAll(db)
      .map(\.id)
    guard !workbenchIDs.isEmpty else { return [] }

    let candidates = try WorkbenchCandidate
      .fetchAll(db)
      .filter { workbenchIDs.contains($0.workbenchID) }
      .sorted(by: areWorkbenchCandidateLinksInIncreasingOrder)

    var seenRecipeIDs: Set<Recipe.ID> = []
    return try candidates.compactMap { candidate in
      if let candidateRecipeID = candidate.recipeID {
        guard !seenRecipeIDs.contains(candidateRecipeID) else { return nil }
        seenRecipeIDs.insert(candidateRecipeID)
        if let recipe = try Recipe.find(candidateRecipeID).fetchOne(db), !recipe.archived {
          let sourceName = try RecipeSource
            .where { $0.recipeID.eq(candidateRecipeID) }
            .fetchOne(db)
            .flatMap(\.workbenchDisplayName)
          return WorkbenchCandidateLink(
            id: candidate.id,
            recipeID: candidateRecipeID,
            title: recipe.title,
            sourceName: sourceName
          )
        }
      }

      return WorkbenchCandidateLink(
        id: candidate.id,
        recipeID: nil,
        title: candidate.recipeTitleSnapshot
      )
    }
  }

  public static func moveAllCandidatesToReference(
    for workbenchID: Workbench.ID,
    in db: Database,
    now: Date
  ) throws {
    guard var workbench = try Workbench.find(workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(workbenchID)
    }
    let candidates = try WorkbenchCandidate
      .where { $0.workbenchID.eq(workbenchID) }
      .fetchAll(db)

    var movedRecipeIDs: Set<Recipe.ID> = []
    for candidate in candidates {
      guard let recipeID = candidate.recipeID, !movedRecipeIDs.contains(recipeID) else { continue }
      if try Recipe.find(recipeID).fetchOne(db) != nil {
        try RecipeRepository.setLibraryPlacement(.reference, recipeID: recipeID, in: db, now: now)
      }
      movedRecipeIDs.insert(recipeID)
    }

    try WorkbenchCandidate
      .where { $0.workbenchID.eq(workbenchID) }
      .delete()
      .execute(db)
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  @discardableResult
  public static func copyCandidatePhotoToDraft(
    photoID: RecipePhoto.ID,
    for workbenchID: Workbench.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipePhoto.ID {
    guard let workbench = try Workbench.find(workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(workbenchID)
    }
    guard let draftRecipeID = workbench.draftRecipeID else {
      throw WorkbenchRepositoryError.missingDraftRecipe(workbenchID)
    }
    guard let sourcePhoto = try RecipePhoto.find(photoID).fetchOne(db) else {
      throw WorkbenchRepositoryError.photoNotFound(photoID)
    }
    guard (
      try WorkbenchCandidate
        .where { $0.workbenchID.eq(workbenchID) }
        .fetchAll(db)
        .contains(where: { $0.recipeID == sourcePhoto.recipeID })
    ) else {
      throw WorkbenchRepositoryError.photoNotFromCandidate(photoID)
    }

    try RecipePhoto
      .where {
        $0.recipeID.eq(draftRecipeID)
          && $0.kind.eq(RecipePhotoKind.hero)
      }
      .delete()
      .execute(db)

    let copiedPhotoID = uuid()
    let copiedPhoto = RecipePhoto(
      id: copiedPhotoID,
      recipeID: draftRecipeID,
      imageDataReference: "recipePhotos/\(copiedPhotoID.uuidString)",
      displayData: sourcePhoto.displayData,
      thumbnailData: sourcePhoto.thumbnailData,
      mediaType: sourcePhoto.mediaType,
      pixelWidth: sourcePhoto.pixelWidth,
      pixelHeight: sourcePhoto.pixelHeight,
      originalSourcePath: sourcePhoto.originalSourcePath,
      sourceURL: sourcePhoto.sourceURL,
      checksum: sourcePhoto.checksum,
      kind: .hero,
      caption: sourcePhoto.caption,
      source: sourcePhoto.source,
      sortOrder: 0,
      dateCreated: now
    )
    try RecipePhoto.insert { copiedPhoto }.execute(db)
    try RecipeRepository.setCoverPhotoID(copiedPhoto.id, recipeID: draftRecipeID, in: db, now: now)
    return copiedPhoto.id
  }
}

private func areWorkbenchCandidateLinksInIncreasingOrder(
  _ lhs: WorkbenchCandidate,
  _ rhs: WorkbenchCandidate
) -> Bool {
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  if lhs.dateCreated != rhs.dateCreated {
    return lhs.dateCreated < rhs.dateCreated
  }
  return lhs.id.uuidString < rhs.id.uuidString
}
