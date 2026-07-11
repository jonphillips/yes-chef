import ImageIO
import SwiftUI
import UIKit
import YesChefCore

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
struct RecipePhotoImage: View {
  let data: Data
  let photoID: UUID
  let checksum: String?
  let variant: RecipePhotoImageVariant

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

    let data = data
    let maxPixelSize = variant.maxPixelSize
    let image = await Task.detached(priority: .userInitiated) {
      downsampledRecipeImage(from: data, maxPixelSize: maxPixelSize)
    }.value

    guard let image else { return }
    RecipeImageCache.shared.insert(image, forKey: key)
    decoded = (key, image)
  }
}
