import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RecipePhotoProcessingOptions: Equatable, Sendable {
  public var displayMaxPixelSize: Int
  public var thumbnailMaxPixelSize: Int
  public var compressionQuality: Double

  public init(
    displayMaxPixelSize: Int = 1_600,
    thumbnailMaxPixelSize: Int = 320,
    compressionQuality: Double = 0.82
  ) {
    self.displayMaxPixelSize = displayMaxPixelSize
    self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
    self.compressionQuality = compressionQuality
  }
}

public struct ProcessedRecipePhoto: Equatable, Sendable {
  public var displayData: Data
  public var thumbnailData: Data?
  public var mediaType: String
  public var pixelWidth: Int?
  public var pixelHeight: Int?
  public var checksum: String

  public init(
    displayData: Data,
    thumbnailData: Data? = nil,
    mediaType: String,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    checksum: String
  ) {
    self.displayData = displayData
    self.thumbnailData = thumbnailData
    self.mediaType = mediaType
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.checksum = checksum
  }
}

public enum RecipePhotoProcessor {
  public static func process(
    sourceData: Data,
    sourcePath: String,
    options: RecipePhotoProcessingOptions = RecipePhotoProcessingOptions()
  ) -> ProcessedRecipePhoto {
    let fallbackMediaType = mediaType(forPath: sourcePath)
    let checksum = fnv1a64Hex(sourceData)
    guard
      let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return ProcessedRecipePhoto(
        displayData: sourceData,
        mediaType: fallbackMediaType,
        checksum: checksum
      )
    }

    let width = properties[kCGImagePropertyPixelWidth] as? Int
    let height = properties[kCGImagePropertyPixelHeight] as? Int
    let displayData = jpegData(
      from: source,
      maxPixelSize: options.displayMaxPixelSize,
      compressionQuality: options.compressionQuality
    ) ?? sourceData
    let thumbnailData = jpegData(
      from: source,
      maxPixelSize: options.thumbnailMaxPixelSize,
      compressionQuality: options.compressionQuality
    )

    return ProcessedRecipePhoto(
      displayData: displayData,
      thumbnailData: thumbnailData,
      mediaType: "image/jpeg",
      pixelWidth: width,
      pixelHeight: height,
      checksum: checksum
    )
  }

  private static func jpegData(
    from source: CGImageSource,
    maxPixelSize: Int,
    compressionQuality: Double
  ) -> Data? {
    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      output,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    ) else { return nil }
    let destinationOptions = [
      kCGImageDestinationLossyCompressionQuality: compressionQuality,
    ] as CFDictionary
    CGImageDestinationAddImage(destination, image, destinationOptions)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }

  private static func mediaType(forPath path: String) -> String {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "heic": "image/heic"
    case "jpeg", "jpg": "image/jpeg"
    case "png": "image/png"
    case "webp": "image/webp"
    default: "application/octet-stream"
    }
  }

  private static func fnv1a64Hex(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in data {
      hash ^= UInt64(byte)
      hash &*= 0x100000001b3
    }
    return String(hash, radix: 16)
  }
}
