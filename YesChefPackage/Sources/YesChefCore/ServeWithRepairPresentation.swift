import Foundation

public struct ServeWithRepairPresentation: Identifiable, Equatable {
  public let recipeID: Recipe.ID
  public let recipeTitle: String
  private let rawData: Data

  public var id: Recipe.ID { recipeID }

  public var initialText: String {
    String(data: rawData, encoding: .utf8) ?? rawData.base64EncodedString()
  }

  public var showsBase64Fallback: Bool {
    String(data: rawData, encoding: .utf8) == nil
  }

  public init?(error: ServeWithCodingError, recipe: Recipe) {
    guard error.recipeID == recipe.id, let rawData = recipe.serveWith else { return nil }
    self.recipeID = recipe.id
    self.recipeTitle = recipe.title
    self.rawData = rawData
  }
}
