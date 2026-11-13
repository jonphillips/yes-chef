import Foundation

/// Lossless-or-loud transport: newer payload versions are counted; other decoding errors fail the load.
public struct CookbookFile: Codable, Sendable {
  public var ownerName: String
  public var generatedAt: Date
  public var payloads: [Data]

  public init(ownerName: String, generatedAt: Date, payloads: [Data]) {
    self.ownerName = ownerName
    self.generatedAt = generatedAt
    self.payloads = payloads
  }

  public func decodedPayloads() throws -> (bundles: [RecipeBundleCoding.RecipeBundle], newerVersionCount: Int) {
    var bundles: [RecipeBundleCoding.RecipeBundle] = []
    var newerVersionCount = 0
    for payload in payloads {
      do {
        bundles.append(try RecipeBundleCoding.decodePayload(payload))
      } catch RecipeBundleCoding.PayloadError.newerVersion {
        newerVersionCount += 1
      }
    }
    return (bundles, newerVersionCount)
  }
}
