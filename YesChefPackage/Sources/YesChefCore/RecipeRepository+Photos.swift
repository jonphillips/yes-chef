import Foundation
import SQLiteData

extension RecipeRepository {
  static func savePendingPhotos(
    _ photos: [RecipePhoto],
    existingPhotos: [RecipePhoto],
    in db: Database
  ) throws {
    let existingPhotoIDs = Set(existingPhotos.map(\.id))
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
    let firstPendingSortOrder = (existingPhotos.map(\.sortOrder).min() ?? 0) - pendingPhotos.count
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
    return (existingPhotos + newPhotos)
      .sorted { lhs, rhs in
        if lhs.kind != rhs.kind {
          return lhs.kind == .hero
        }
        return lhs.sortOrder < rhs.sortOrder
      }
  }
}
