import Foundation
import SQLiteData

extension RecipeRepository {
  static func reconcilePhotos(
    _ photos: [RecipePhoto],
    existingPhotos: [RecipePhoto],
    in db: Database
  ) throws {
    let desiredPhotoIDs = Set(photos.map(\.id))
    let existingPhotoIDs = Set(existingPhotos.map(\.id))
    for photo in existingPhotos where !desiredPhotoIDs.contains(photo.id) {
      try Recipe
        .where { $0.coverPhotoID.eq(photo.id) }
        .update { $0.coverPhotoID = #bind(nil as RecipePhoto.ID?) }
        .execute(db)
      try RecipePhoto.find(photo.id).delete().execute(db)
    }
    for photo in photos where !existingPhotoIDs.contains(photo.id) {
      try RecipePhoto.insert { photo }.execute(db)
    }
  }

  static func mergedPhotos(
    _ existingPhotos: [RecipePhoto],
    pendingPhotos: [RecipeEditorPhotoDraft],
    recipeID: Recipe.ID,
    now: Date
  ) -> [RecipePhoto] {
    let replacesExistingHero = pendingPhotos.contains { $0.kind == .hero }
    let retainedPhotos = existingPhotos.filter { photo in
      !(replacesExistingHero && photo.kind == .hero)
    }
    let firstPendingSortOrder = (retainedPhotos.map(\.sortOrder).min() ?? 0) - pendingPhotos.count
    let newPhotos = pendingPhotos.enumerated().map { index, pendingPhoto in
      RecipePhoto(
        id: pendingPhoto.id,
        recipeID: recipeID,
        imageDataReference: "recipePhotos/\(pendingPhoto.id.uuidString)",
        displayData: pendingPhoto.processedPhoto.displayData,
        thumbnailData: pendingPhoto.processedPhoto.thumbnailData,
        mediaType: pendingPhoto.processedPhoto.mediaType,
        pixelWidth: pendingPhoto.processedPhoto.pixelWidth,
        pixelHeight: pendingPhoto.processedPhoto.pixelHeight,
        originalSourcePath: pendingPhoto.originalSourcePath,
        checksum: pendingPhoto.processedPhoto.checksum,
        kind: pendingPhoto.kind,
        caption: pendingPhoto.caption,
        source: pendingPhoto.source,
        sortOrder: firstPendingSortOrder + index,
        dateCreated: now
      )
    }
    return (retainedPhotos + newPhotos)
      .sorted { lhs, rhs in
        if lhs.kind != rhs.kind {
          return lhs.kind == .hero
        }
        return lhs.sortOrder < rhs.sortOrder
      }
  }
}
