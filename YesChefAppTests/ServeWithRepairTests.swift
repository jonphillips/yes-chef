import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct ServeWithRepairTests {
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

  // NOTE: The Workbench ServeWith-repair surface (`WorkbenchDetailModel.presentServeWithRepair`
  // and the `.repairServeWith` destination case) was intentionally removed in b2cf8a1 "Harden
  // Serve With migration repair" — repair is now a recipe-detail concern surfaced via
  // `serveWithRepairError` on load (ADR-0048 amendment). Its test was dropped with it.

  @Test
  func recipeDetailPresentsOwnRepairAndLeavesDestinationUntouchedForAnotherRecipe() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000005821")!
    let otherRecipeID = UUID(uuidString: "00000000-0000-0000-0000-000000005822")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)

    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Tomato Soup",
            dateCreated: now,
            dateModified: now,
            serveWith: Data("not a list".utf8)
          )
        }
        .execute(db)
      }

      let model = RecipeDetailModel(recipeID: recipeID)
      try await model.$detail.load()

      #expect(model.presentServeWithRepair(for: .malformedData(recipeID: recipeID)))
      guard case let .repairServeWith(presentation)? = model.destination else {
        Issue.record("Expected recipe repair presentation.")
        return
      }
      expectNoDifference(presentation.recipeID, recipeID)

      model.destination = .scaling
      #expect(model.presentServeWithRepair(for: .malformedData(recipeID: otherRecipeID)) == false)
      guard case .scaling? = model.destination else {
        Issue.record("Another recipe should leave the existing destination intact.")
        return
      }
    }
  }
}
