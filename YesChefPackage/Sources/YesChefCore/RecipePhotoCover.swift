import Foundation

/// The photo fields cover-selection needs. Both the full `RecipePhoto` and the
/// slim `RecipeDetailPhoto` (ADR-0029 Amd2 S5b) conform, so cover selection works
/// off either without pulling image bytes.
public protocol RecipePhotoDisplayMetadata: Identifiable where ID == UUID {
  var pixelWidth: Int? { get }
  var pixelHeight: Int? { get }
  var kind: RecipePhotoKind { get }
  var sortOrder: Int { get }
}

extension RecipePhoto: RecipePhotoDisplayMetadata {}
extension RecipeDetailPhoto: RecipePhotoDisplayMetadata {}

public enum RecipePhotoCover {
  public static func coverPhoto<Photo: RecipePhotoDisplayMetadata>(
    coverPhotoID: RecipePhoto.ID?,
    from photos: [Photo]
  ) -> Photo? {
    if let coverPhotoID, let photo = photos.first(where: { $0.id == coverPhotoID }) {
      return photo
    }

    return photos.min { lhs, rhs in
      displaySortKey(for: lhs) < displaySortKey(for: rhs)
    }
  }

  private static func displaySortKey(for photo: some RecipePhotoDisplayMetadata) -> PhotoDisplaySortKey {
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
