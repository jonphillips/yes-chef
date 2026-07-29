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

  @Test
  func workbenchPresentsCandidateRepairAndLeavesDestinationUntouchedForAnAbsentRecipe() async throws {
    let workbenchID = UUID(uuidString: "00000000-0000-0000-0000-000000005811")!
    let candidateID = UUID(uuidString: "00000000-0000-0000-0000-000000005812")!
    let candidateRecipeID = UUID(uuidString: "00000000-0000-0000-0000-000000005813")!
    let absentRecipeID = UUID(uuidString: "00000000-0000-0000-0000-000000005814")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)

    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(
            id: candidateRecipeID,
            title: "Candidate Soup",
            dateCreated: now,
            dateModified: now,
            serveWith: Data("not a list".utf8)
          )
        }
        .execute(db)
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Soup Trials",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try WorkbenchCandidate.insert {
          WorkbenchCandidate(
            id: candidateID,
            workbenchID: workbenchID,
            recipeID: candidateRecipeID,
            recipeTitleSnapshot: "Candidate Soup",
            sortOrder: 0,
            dateCreated: now
          )
        }
        .execute(db)
      }

      let model = WorkbenchDetailModel(workbenchID: workbenchID)
      try await model.$detail.load()

      #expect(model.presentServeWithRepair(for: .malformedData(recipeID: candidateRecipeID)))
      guard case let .repairServeWith(presentation)? = model.destination else {
        Issue.record("Expected candidate repair presentation.")
        return
      }
      expectNoDifference(presentation.recipeID, candidateRecipeID)

      model.destination = .addCandidates
      #expect(model.presentServeWithRepair(for: .malformedData(recipeID: absentRecipeID)) == false)
      guard case .addCandidates? = model.destination else {
        Issue.record("An absent recipe should leave the existing destination intact.")
        return
      }
    }
  }

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
