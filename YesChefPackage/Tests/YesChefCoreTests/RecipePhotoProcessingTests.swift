import CoreGraphics
import CustomDump
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipePhotoProcessingTests {
    @Test
    func photoProcessorCreatesCanonicalDisplayAndThumbnailDerivatives() throws {
      let sourceData = try Self.makeJPEG(width: 2_400, height: 1_200)

      let processedPhoto = RecipePhotoProcessor.process(
        sourceData: sourceData,
        sourcePath: "Images/reference.jpg"
      )

      expectNoDifference(try Self.pixelSize(of: processedPhoto.displayData), CGSize(width: 1_600, height: 800))
      expectNoDifference(
        try processedPhoto.thumbnailData.map(Self.pixelSize(of:)),
        CGSize(width: 320, height: 160)
      )
      expectNoDifference(processedPhoto.displayData.count <= 300_000, true)
      expectNoDifference(processedPhoto.mediaType, "image/jpeg")
      expectNoDifference(processedPhoto.pixelWidth, 2_400)
      expectNoDifference(processedPhoto.pixelHeight, 1_200)
      expectNoDifference(processedPhoto.checksum.isEmpty, false)
    }

    @Test
    func photoProcessorUsesLargerDisplayBudgetForReferenceDocuments() throws {
      let sourceData = try Self.makeJPEG(width: 2_600, height: 1_300)

      let processedPhoto = RecipePhotoProcessor.process(
        sourceData: sourceData,
        sourcePath: "Images/reference.jpg",
        kind: .referenceDocument
      )

      expectNoDifference(try Self.pixelSize(of: processedPhoto.displayData), CGSize(width: 2_400, height: 1_200))
      expectNoDifference(
        try processedPhoto.thumbnailData.map(Self.pixelSize(of:)),
        CGSize(width: 480, height: 240)
      )
      expectNoDifference(processedPhoto.displayData.count <= 900_000, true)
    }

    private static func makeJPEG(width: Int, height: Int) throws -> Data {
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let bytesPerPixel = 4
      var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
      for y in 0..<height {
        for x in 0..<width {
          let offset = (y * width + x) * bytesPerPixel
          pixels[offset] = UInt8(x % 256)
          pixels[offset + 1] = UInt8(y % 256)
          pixels[offset + 2] = UInt8((x + y) % 256)
          pixels[offset + 3] = 255
        }
      }

      guard
        let provider = CGDataProvider(data: Data(pixels) as CFData),
        let image = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: width * bytesPerPixel,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: true,
          intent: .defaultIntent
        )
      else {
        throw TestImageError.couldNotCreateImage
      }

      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      ) else {
        throw TestImageError.couldNotCreateImageDestination
      }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else {
        throw TestImageError.couldNotFinalizeImage
      }
      return output as Data
    }

    private static func pixelSize(of data: Data) throws -> CGSize {
      guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
      else {
        throw TestImageError.couldNotReadImageSize
      }
      return CGSize(width: width, height: height)
    }
  }
}

private enum TestImageError: Error {
  case couldNotCreateImage
  case couldNotCreateImageDestination
  case couldNotFinalizeImage
  case couldNotReadImageSize
}
