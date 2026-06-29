import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RecipePhotoProcessingOptions: Equatable, Sendable {
  public var displayMaxPixelSize: Int
  public var thumbnailMaxPixelSize: Int
  public var compressionQuality: Double
  public var targetMaxBytes: Int?

  public init(
    displayMaxPixelSize: Int = 1_600,
    thumbnailMaxPixelSize: Int = 320,
    compressionQuality: Double = 0.82,
    targetMaxBytes: Int? = 300_000
  ) {
    self.displayMaxPixelSize = displayMaxPixelSize
    self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
    self.compressionQuality = compressionQuality
    self.targetMaxBytes = targetMaxBytes
  }

  public static let canonicalDisplay = RecipePhotoProcessingOptions()

  public static let referenceDocument = RecipePhotoProcessingOptions(
    displayMaxPixelSize: 2_400,
    thumbnailMaxPixelSize: 480,
    compressionQuality: 0.86,
    targetMaxBytes: 900_000
  )

  public static func defaults(for kind: RecipePhotoKind) -> Self {
    kind == .referenceDocument ? .referenceDocument : .canonicalDisplay
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
    kind: RecipePhotoKind
  ) -> ProcessedRecipePhoto {
    process(
      sourceData: sourceData,
      sourcePath: sourcePath,
      options: .defaults(for: kind)
    )
  }

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
      compressionQuality: options.compressionQuality,
      targetMaxBytes: options.targetMaxBytes
    ) ?? sourceData
    let thumbnailData = jpegData(
      from: source,
      maxPixelSize: options.thumbnailMaxPixelSize,
      compressionQuality: options.compressionQuality,
      targetMaxBytes: nil
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
    compressionQuality: Double,
    targetMaxBytes: Int?
  ) -> Data? {
    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }

    let qualitySteps = qualitySteps(startingAt: compressionQuality)
    var bestData: Data?
    for quality in qualitySteps {
      guard let data = encodeJPEG(image, compressionQuality: quality) else { continue }
      bestData = data
      if targetMaxBytes.map({ data.count <= $0 }) ?? true {
        return data
      }
    }
    return bestData
  }

  private static func encodeJPEG(_ image: CGImage, compressionQuality: Double) -> Data? {
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

  private static func qualitySteps(startingAt quality: Double) -> [Double] {
    let boundedQuality = min(max(quality, 0.55), 0.95)
    var steps = [boundedQuality]
    var next = boundedQuality - 0.08
    while next >= 0.55 {
      steps.append(next)
      next -= 0.08
    }
    if steps.last != 0.55 {
      steps.append(0.55)
    }
    return steps
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
