import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

/// The recipe-body ("Adjust Recipe") hand-off finalizes two ways (ADR-0042 Amd 4). A prose revision
/// brief stays on the in-app adjustment-review path; a whole new recipe returned as schema.org
/// JSON-LD is diverted to Create Recipe. These assert the transport routes on payload shape.
@Suite
@MainActor
struct AIHandoffRecipePasteRoutingTests {
  private static let recipeID = UUID(uuidString: "00000000-0000-0000-0000-0000000038A0")!
  private static let handoffID = UUID(uuidString: "00000000-0000-0000-0000-0000000038A1")!
  private static let now = Date(timeIntervalSinceReferenceDate: 840_100_000)

  private func seedRecipeAndHandoff(in database: any DatabaseWriter) throws {
    try database.write { db in
      try Recipe.insert {
        Recipe(id: Self.recipeID, title: "Skillet Chicken", dateCreated: Self.now, dateModified: Self.now)
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: Self.handoffID,
          sourceType: .recipe,
          sourceID: Self.recipeID,
          taskType: .adjustRecipe,
          createdAt: Self.now,
          exportedPrompt: "YC-HANDOFF: \(Self.handoffID.uuidString)"
        ),
        in: db
      )
    }
  }

  @Test
  func newRecipeJSONLDReturnDivertsToCreateRecipeAndMarksTheHandoffImported() async throws {
    let createRecipeCoordinator = CreateRecipeCoordinator()

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Self.now
      $0.uuid = .incrementing
      $0.createRecipeCoordinator = createRecipeCoordinator
      $0.handoffReviewCoordinator = HandoffReviewCoordinator()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try seedRecipeAndHandoff(in: database)

      let transport = HandoffInAppTransport()
      let paste = """
        YC-HANDOFF: \(Self.handoffID.uuidString)
        \(AIHandoffReturnContract.marker)
        {"@context":"https://schema.org","@type":"Recipe","name":"Charred Cabbage",\
        "recipeIngredient":["1 head cabbage","2 tbsp olive oil"],\
        "recipeInstructions":[{"@type":"HowToStep","text":"Char over high heat."}]}
        """
      await transport.pastedResultsReceived([paste], source: .recipeAdjustment(Self.recipeID))

      // Diverted to Create Recipe with the raw JSON-LD, not the adjustment review.
      let staged = try #require(createRecipeCoordinator.stagedText)
      #expect(staged.text.contains("Charred Cabbage"))
      #expect(transport.isShowingError == false)
      #expect(transport.isShowingUnmatchedConfirmation == false)

      // The routed handoff row is closed so a later paste cannot re-import it.
      let handoffID = Self.handoffID
      let status = try await database.read { db in
        try AIHandoffRepository.handoff(id: handoffID, in: db)?.status
      }
      #expect(status == .imported)
    }
  }

  @Test
  func proseRevisionBriefStaysOnTheAdjustmentReviewPath() async throws {
    let createRecipeCoordinator = CreateRecipeCoordinator()

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Self.now
      $0.uuid = .incrementing
      $0.createRecipeCoordinator = createRecipeCoordinator
      $0.handoffReviewCoordinator = HandoffReviewCoordinator()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try seedRecipeAndHandoff(in: database)

      let transport = HandoffInAppTransport()
      let paste = """
        YC-HANDOFF: \(Self.handoffID.uuidString)
        \(AIHandoffReturnContract.marker)
        Take the butter to 120g and brown it before creaming — more nutty depth.
        Move the salt into the flour so it distributes evenly.
        """
      await transport.pastedResultsReceived([paste], source: .recipeAdjustment(Self.recipeID))

      // A prose brief must not be diverted to Create Recipe; it stays on the adjustment-review path.
      #expect(createRecipeCoordinator.stagedText == nil)
      #expect(transport.isShowingError == false)
      #expect(transport.isShowingUnmatchedConfirmation == false)
      let handoffID = Self.handoffID
      let status = try await database.read { db in
        try AIHandoffRepository.handoff(id: handoffID, in: db)?.status
      }
      #expect(status == .imported)
    }
  }
}
