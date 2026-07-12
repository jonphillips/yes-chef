import Dependencies
import ImageIO
import SQLiteData
import SwiftUI
import UIKit
import YesChefCore

/// Reads a photo's full-resolution `displayData` on demand from the concurrent
/// reader pool. The detail fetch no longer carries these bytes (ADR-0029 Amd2
/// S5b), so hero/full-screen rendering hydrates them here — on a pool reader,
/// which never touches the serialized writer the `SyncEngine` contends for.
enum RecipePhotoDisplayDataLoader {
  static func load(photoID: RecipePhoto.ID) async -> Data? {
    @Dependency(\.defaultDatabase) var database
    return try? await database.read { db in
      try RecipePhoto.find(photoID).fetchOne(db)?.displayData
    }
  }
}

/// The rendering contexts a recipe photo appears in. Each maps to a downsample
/// budget so we decode only as many pixels as the slot can show.
enum RecipePhotoImageVariant {
  case thumbnail
  case hero
  case fullScreen

  /// Longest-edge pixel budget for the decoded bitmap. Kept comfortably above
  /// the on-screen point size × max screen scale so images stay crisp.
  var maxPixelSize: CGFloat {
    switch self {
    case .thumbnail: 400
    case .hero: 1800
    case .fullScreen: 3000
    }
  }

  fileprivate var cacheTag: String {
    switch self {
    case .thumbnail: "t"
    case .hero: "h"
    case .fullScreen: "f"
    }
  }
}

/// In-memory cache of decoded, downsampled bitmaps, keyed by photo identity +
/// checksum + variant so a re-render never re-decodes the same image and an
/// edited photo (new checksum) invalidates cleanly.
@MainActor
final class RecipeImageCache {
  static let shared = RecipeImageCache()

  private let cache = NSCache<NSString, UIImage>()

  private init() {
    cache.countLimit = 80
  }

  func image(forKey key: String) -> UIImage? {
    cache.object(forKey: key as NSString)
  }

  func insert(_ image: UIImage, forKey key: String) {
    cache.setObject(image, forKey: key as NSString)
  }

  static func cacheKey(photoID: UUID, checksum: String?, variant: RecipePhotoImageVariant) -> String {
    "\(photoID.uuidString)|\(checksum ?? "")|\(variant.cacheTag)"
  }
}

/// Decode + downsample off the main thread with ImageIO. Producing a thumbnail
/// at `maxPixelSize` avoids fully decoding a multi-megapixel JPEG to a bitmap
/// we would only shrink anyway — the work that was hanging the main thread.
func downsampledRecipeImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
  let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
  guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
    return UIImage(data: data)
  }
  let thumbnailOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
  ]
  guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
    return UIImage(data: data)
  }
  return UIImage(cgImage: cgImage)
}

/// Renders a recipe photo, decoding off the main thread and serving cached
/// bitmaps on re-render. A cache hit renders synchronously (no placeholder
/// flash); a miss shows the placeholder until the background decode lands.
///
/// The thumbnail variant decodes the carried `thumbnailData`; hero/full-screen
/// variants read the full-resolution bytes on demand (ADR-0029 Amd2 S5b), so the
/// detail fetch never has to haul `displayData` through the observed model.
struct RecipePhotoImage: View {
  let photoID: UUID
  let checksum: String?
  let variant: RecipePhotoImageVariant
  /// The small thumbnail bytes carried by the fetch. Used directly for the
  /// thumbnail variant, and as a fallback when a photo has no `displayData`.
  let thumbnailData: Data?

  @State private var decoded: (key: String, image: UIImage)?

  private var cacheKey: String {
    RecipeImageCache.cacheKey(photoID: photoID, checksum: checksum, variant: variant)
  }

  var body: some View {
    let image = resolvedImage
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Image(systemName: "photo")
          .font(.title)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task(id: cacheKey) { await load() }
  }

  private var resolvedImage: UIImage? {
    if let decoded, decoded.key == cacheKey { return decoded.image }
    return RecipeImageCache.shared.image(forKey: cacheKey)
  }

  private func load() async {
    let key = cacheKey
    if RecipeImageCache.shared.image(forKey: key) != nil { return }

    let data: Data?
    switch variant {
    case .thumbnail:
      // Prefer the carried thumbnail (no DB read); fall back to a full-res read
      // only when a photo never got a generated thumbnail.
      if let thumbnailData {
        data = thumbnailData
      } else {
        data = await RecipePhotoDisplayDataLoader.load(photoID: photoID)
      }
    case .hero, .fullScreen:
      data = await RecipePhotoDisplayDataLoader.load(photoID: photoID) ?? thumbnailData
    }
    guard let data else { return }

    let maxPixelSize = variant.maxPixelSize
    let image = await Task.detached(priority: .userInitiated) {
      downsampledRecipeImage(from: data, maxPixelSize: maxPixelSize)
    }.value

    guard let image else { return }
    // The cache key can change while the async decode is in flight (the row
    // re-published with a new checksum); only publish if we still want this key.
    guard key == cacheKey else { return }
    RecipeImageCache.shared.insert(image, forKey: key)
    decoded = (key, image)
  }
}
