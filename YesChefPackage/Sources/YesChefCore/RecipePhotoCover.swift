import Foundation

public enum RecipePhotoCover {
  public static func coverPhoto(
    coverPhotoID: RecipePhoto.ID?,
    from photos: [RecipePhoto]
  ) -> RecipePhoto? {
    if let coverPhotoID, let photo = photos.first(where: { $0.id == coverPhotoID }) {
      return photo
    }

    return photos.min { lhs, rhs in
      displaySortKey(for: lhs) < displaySortKey(for: rhs)
    }
  }

  private static func displaySortKey(for photo: RecipePhoto) -> PhotoDisplaySortKey {
    PhotoDisplaySortKey(
      isLowResolution: max(photo.pixelWidth ?? 0, photo.pixelHeight ?? 0) < 700,
      kindRank: photo.kind == .hero ? 0 : 1,
      sortOrder: photo.sortOrder
    )
  }
}

private struct PhotoDisplaySortKey: Comparable {
  var isLowResolution: Bool
  var kindRank: Int
  var sortOrder: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.isLowResolution != rhs.isLowResolution {
      return !lhs.isLowResolution
    }
    if lhs.kindRank != rhs.kindRank {
      return lhs.kindRank < rhs.kindRank
    }
    return lhs.sortOrder < rhs.sortOrder
  }
}
