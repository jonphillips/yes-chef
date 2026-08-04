import CustomDump
import Foundation
import Testing
import YesChefCore

@Suite
struct ServeWithRepairPresentationTests {
  @Test
  func presentationRequiresMatchingRecipeAndPreservesItsOriginalTextualForm() throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000005801")!
    let otherRecipeID = UUID(uuidString: "00000000-0000-0000-0000-000000005802")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)
    let error = ServeWithCodingError.malformedData(recipeID: recipeID)
    let recipeWithoutServeWith = Recipe(
      id: recipeID,
      title: "Tomato Soup",
      dateCreated: now,
      dateModified: now
    )

    #expect(ServeWithRepairPresentation(error: error, recipe: recipeWithoutServeWith) == nil)
    #expect(
      ServeWithRepairPresentation(
        error: error,
        recipe: Recipe(
          id: otherRecipeID,
          title: "Other Soup",
          dateCreated: now,
          dateModified: now,
          serveWith: Data("[]".utf8)
        )
      ) == nil
    )

    let utf8Data = Data("[{\"title\":\"Bread\"}]".utf8)
    let utf8Presentation = try #require(
      ServeWithRepairPresentation(
        error: error,
        recipe: Recipe(
          id: recipeID,
          title: "Tomato Soup",
          dateCreated: now,
          dateModified: now,
          serveWith: utf8Data
        )
      )
    )
    #expect(utf8Presentation.showsBase64Fallback == false)
    expectNoDifference(utf8Presentation.initialText, "[{\"title\":\"Bread\"}]")

    let nonUTF8Data = Data([0xFF, 0x00, 0xC3])
    let nonUTF8Presentation = try #require(
      ServeWithRepairPresentation(
        error: error,
        recipe: Recipe(
          id: recipeID,
          title: "Tomato Soup",
          dateCreated: now,
          dateModified: now,
          serveWith: nonUTF8Data
        )
      )
    )
    #expect(nonUTF8Presentation.showsBase64Fallback)
    expectNoDifference(nonUTF8Presentation.initialText, nonUTF8Data.base64EncodedString())
  }
}
