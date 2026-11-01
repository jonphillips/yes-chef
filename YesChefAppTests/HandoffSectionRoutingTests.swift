import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
struct HandoffSectionRoutingTests {
  // ADR-0038 Amd 7: the token's stored row is authoritative for scope, so `matches` is now an
  // item-level test (same source type + id) that decides only whether the return belongs to *this*
  // item at all. The task/day/variation discriminator moved to `matchesScope`, which drives the
  // redirect toast on a same-item mismatch rather than a rejection. These tests pin that split.

  @Test
  func recipeSectionReturnMatchesTheRecipeButScopesToItsOwnSection() {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003901")!
    let otherRecipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003921")!
    let chefItUpHandoff = AIHandoff(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000003902")!,
      sourceType: .recipe,
      sourceID: recipeID,
      taskType: .chefItUp,
      createdAt: .distantPast,
      exportedPrompt: ""
    )

    // Any section door on the same recipe matches at the item level — so a Chef It Up return pasted
    // into the Make Ahead door is routed by its stored row, not rejected.
    #expect(HandoffExportSource.recipeSection(recipeID, .chefItUp).matches(chefItUpHandoff))
    #expect(HandoffExportSource.recipeSection(recipeID, .makeAhead).matches(chefItUpHandoff))
    // A door on a different recipe does not match.
    #expect(!HandoffExportSource.recipeSection(otherRecipeID, .chefItUp).matches(chefItUpHandoff))

    // Scope still distinguishes the section: only the originating door is in scope.
    #expect(HandoffExportSource.recipeSection(recipeID, .chefItUp).matchesScope(chefItUpHandoff))
    #expect(!HandoffExportSource.recipeSection(recipeID, .makeAhead).matchesScope(chefItUpHandoff))
  }

  @Test
  func menuDayReturnMatchesTheMenuButScopesToItsOriginalDay() {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000003904")!
    let otherMenuID = UUID(uuidString: "00000000-0000-0000-0000-000000003924")!
    let dayTwoHandoff = AIHandoff(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000003905")!,
      sourceType: .menu,
      sourceID: menuID,
      taskType: .prepPlan,
      dayOffset: 1,
      createdAt: .distantPast,
      exportedPrompt: ""
    )

    // Either day's door on the same menu matches at the item level; a different menu does not.
    #expect(HandoffExportSource.menuDay(menuID, dayOffset: 1).matches(dayTwoHandoff))
    #expect(HandoffExportSource.menuDay(menuID, dayOffset: 0).matches(dayTwoHandoff))
    #expect(!HandoffExportSource.menuDay(otherMenuID, dayOffset: 1).matches(dayTwoHandoff))

    // Scope pins the return to its original day.
    #expect(HandoffExportSource.menuDay(menuID, dayOffset: 1).matchesScope(dayTwoHandoff))
    #expect(!HandoffExportSource.menuDay(menuID, dayOffset: 0).matchesScope(dayTwoHandoff))
  }

  @Test
  func variationAdjustmentReturnMatchesTheRecipeButScopesToItsOriginalVariation() {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003906")!
    let variationID = UUID(uuidString: "00000000-0000-0000-0000-000000003907")!
    let otherVariationID = UUID(uuidString: "00000000-0000-0000-0000-000000003908")!
    let otherRecipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003926")!
    let variationHandoff = AIHandoff(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000003909")!,
      sourceType: .recipe,
      sourceID: recipeID,
      taskType: .adjustRecipe,
      variationID: variationID,
      createdAt: .distantPast,
      exportedPrompt: ""
    )

    // Base, exact-variation, and other-variation doors all match at the item level (same recipe);
    // a different recipe does not.
    #expect(HandoffExportSource.recipeAdjustment(recipeID, variationID: variationID).matches(variationHandoff))
    #expect(HandoffExportSource.recipeAdjustment(recipeID).matches(variationHandoff))
    #expect(HandoffExportSource.recipeAdjustment(recipeID, variationID: otherVariationID).matches(variationHandoff))
    #expect(!HandoffExportSource.recipeAdjustment(otherRecipeID, variationID: variationID).matches(variationHandoff))

    // Scope is what prevents a silent base rewrite: only the originating variation is in scope.
    #expect(HandoffExportSource.recipeAdjustment(recipeID, variationID: variationID).matchesScope(variationHandoff))
    #expect(!HandoffExportSource.recipeAdjustment(recipeID).matchesScope(variationHandoff))
    #expect(!HandoffExportSource.recipeAdjustment(recipeID, variationID: otherVariationID).matchesScope(variationHandoff))
  }

  @Test
  @MainActor
  func unmatchedVariationPasteRestagesTheOriginalVariationScope() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003910")!
    let variationID = UUID(uuidString: "00000000-0000-0000-0000-000000003911")!
    let unrecognizedHandoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003912")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)
    let coordinator = HandoffReviewCoordinator()

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Variation Handoff", dateCreated: now, dateModified: now)
        }
        .execute(db)
      }

      let transport = HandoffInAppTransport()
      await transport.pastedResultsReceived(
        ["""
        YC-HANDOFF: \(unrecognizedHandoffID.uuidString)
        \(AIHandoffReturnContract.marker)
        Use a lighter sauce for this variation.
        """],
        source: .recipeAdjustment(recipeID, variationID: variationID)
      )

      #expect(transport.isShowingUnmatchedConfirmation)
      await transport.reviewUnmatchedResult()

      guard case let .recipeAdjustmentBrief(review) = coordinator.review else {
        Issue.record("Expected a recipe-adjustment brief review.")
        return
      }
      #expect(review.variationID == variationID)
      let stagedRows = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(stagedRows.isEmpty)
    }
  }

  @Test
  @MainActor
  func unmatchedNoTokenPasteOpensReviewWithoutWritingALedgerRow() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003933")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_100)
    let coordinator = HandoffReviewCoordinator()

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "No Token", dateCreated: now, dateModified: now)
        }
        .execute(db)
      }

      let transport = HandoffInAppTransport()
      await transport.pastedResultsReceived(
        ["\(AIHandoffReturnContract.marker)\nBrown the butter before creaming it."],
        source: .recipeAdjustment(recipeID)
      )
      #expect(transport.isShowingUnmatchedConfirmation)
      await transport.reviewUnmatchedResult()

      guard case .recipeAdjustmentBrief = coordinator.review else {
        Issue.record("Expected a recipe-adjustment brief review.")
        return
      }
      let rows = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(rows.isEmpty)
    }
  }

  @Test
  @MainActor
  func pendingUnmatchedHandoffIsWrittenImportedWithTheFirstReviewCommit() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003930")!
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003931")!
    let variationID = UUID(uuidString: "00000000-0000-0000-0000-000000003932")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)
    let coordinator = HandoffReviewCoordinator()
    let review = AIHandoffRecipeMakeAheadReview(
      handoffID: handoffID,
      recipeID: recipeID,
      makeAhead: "Toast the spices.",
      learnings: []
    )
    let handoff = AIHandoff(
      id: handoffID,
      sourceType: .recipe,
      sourceID: recipeID,
      taskType: .recipeMakeAhead,
      dayOffset: 2,
      variationID: variationID,
      createdAt: now,
      exportedPrompt: ""
    )

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Spiced Lentils", dateCreated: now, dateModified: now)
        }
        .execute(db)
      }

      coordinator.present(.recipeMakeAhead(review), pendingHandoff: handoff)
      let item = try #require(coordinator.reviewItems(for: .recipeMakeAhead(review)).first)
      try await item.commit(item.unmodifiedApprovedText)
      try await item.commit(item.unmodifiedApprovedText)

      let rows = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(rows.count == 1)
      #expect(rows.first?.id == handoffID)
      #expect(rows.first?.sourceType == .recipe)
      #expect(rows.first?.sourceID == recipeID)
      #expect(rows.first?.taskType == .recipeMakeAhead)
      #expect(rows.first?.variationID == variationID)
      #expect(rows.first?.dayOffset == 2)
      #expect(rows.first?.status == .imported)
      #expect(rows.first?.importedAt == now)
    }
  }

  @Test
  @MainActor
  func adjustmentDraftingKeepsPendingHandoffUntilOverwriteCommitsIt() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003940")!
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003941")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_200)
    let coordinator = HandoffReviewCoordinator()
    let brief = AIHandoffRecipeAdjustmentBriefReview(
      handoffID: handoffID,
      recipeID: recipeID,
      brief: "Make the spices more aromatic.",
      learnings: []
    )
    let handoff = AIHandoff(
      id: handoffID,
      sourceType: .recipe,
      sourceID: recipeID,
      taskType: .adjustRecipe,
      createdAt: now,
      exportedPrompt: ""
    )

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Aromatic Stew", dateCreated: now, dateModified: now)
        }
        .execute(db)
      }
      let possibleDetail = try await database.read { db in
        try RecipeDetailRequest(recipeID: recipeID).fetch(db)
      }
      let detail = try #require(possibleDetail)
      let proposal = RecipeAdjustmentProposal(summary: "Toast the spices before adding liquid.")
      let proposedDetail = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { UUID() })
      let adjustmentReview = RecipeAdjustmentReviewState(
        currentDetail: detail,
        proposedDetail: proposedDetail,
        proposal: proposal,
        deliberationBody: brief.brief
      )
      let originalReview = AIHandoffReview.recipeAdjustmentBrief(brief)

      coordinator.present(originalReview, pendingHandoff: handoff)
      coordinator.finishDraftingRecipeAdjustment(from: originalReview, adjustmentReview: adjustmentReview)
      let beforeOverwrite = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(beforeOverwrite.isEmpty)

      coordinator.presentPendingAdjustmentReviewAfterReviewDismissal()
      #expect(coordinator.adjustmentReview != nil)
      guard case .success = coordinator.overwriteAdjustmentButtonTapped(adjustmentReview) else {
        Issue.record("Expected the recipe adjustment overwrite to succeed.")
        return
      }

      let rows = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(rows.count == 1)
      #expect(rows.first?.id == handoffID)
      #expect(rows.first?.status == .imported)
      #expect(rows.first?.importedAt == now)
    }
  }

  @Test
  @MainActor
  func everyDiscardPathClearsPendingHandoffBeforeAnotherCommit() async throws {
    let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000003942")!
    let now = Date(timeIntervalSinceReferenceDate: 840_300_300)
    let coordinator = HandoffReviewCoordinator()
    let pendingIDs = [
      UUID(uuidString: "00000000-0000-0000-0000-000000003943")!,
      UUID(uuidString: "00000000-0000-0000-0000-000000003944")!,
      UUID(uuidString: "00000000-0000-0000-0000-000000003945")!
    ]
    let discardReviews: [AIHandoffReview] = [
      .recipeMakeAhead(AIHandoffRecipeMakeAheadReview(
        handoffID: pendingIDs[0], recipeID: recipeID, makeAhead: "Toast the spices.", learnings: []
      )),
      .recipeMakeAhead(AIHandoffRecipeMakeAheadReview(
        handoffID: pendingIDs[1], recipeID: recipeID, makeAhead: "Toast the spices.", learnings: []
      )),
      .recipeAdjustmentBrief(AIHandoffRecipeAdjustmentBriefReview(
        handoffID: pendingIDs[2], recipeID: recipeID, brief: "Brighten the stew.", learnings: []
      ))
    ]

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Discarded Handoff", dateCreated: now, dateModified: now)
        }
        .execute(db)
      }
      let unrelatedReview = AIHandoffRecipeMakeAheadReview(
        handoffID: UUID(uuidString: "00000000-0000-0000-0000-000000003946")!,
        recipeID: recipeID,
        makeAhead: "Toast the spices.",
        learnings: []
      )
      let unrelatedCommit = try #require(coordinator.reviewItems(for: .recipeMakeAhead(unrelatedReview)).first)

      for (index, review) in discardReviews.enumerated() {
        let handoff = AIHandoff(
          id: pendingIDs[index],
          sourceType: .recipe,
          sourceID: recipeID,
          taskType: index == 2 ? .adjustRecipe : .recipeMakeAhead,
          createdAt: now,
          exportedPrompt: ""
        )
        coordinator.present(review, pendingHandoff: handoff)
        switch index {
        case 0:
          coordinator.discard(review)
        case 1:
          coordinator.discardAll()
        default:
          coordinator.discardPendingHandoff()
        }
        try await unrelatedCommit.commit(unrelatedCommit.unmodifiedApprovedText)
      }

      let rows = try await database.read { db in try AIHandoff.fetchAll(db) }
      #expect(rows.isEmpty)
    }
  }

  @Test
  @MainActor
  func workbenchDraftReviewStagesTheRecipeEvenWhenTheRationaleIsMissing() {
    // ADR-0042 S3b: a draft that omitted the rationale block (it argued it in-thread) must still
    // stage the recipe item — the review sheet fills the empty rationale — alongside its learnings.
    let coordinator = HandoffReviewCoordinator()
    let review = AIHandoffWorkbenchDraftReview(
      handoffID: UUID(uuidString: "00000000-0000-0000-0000-000000003940")!,
      workbenchID: UUID(uuidString: "00000000-0000-0000-0000-000000003941")!,
      draftRecipe: WorkbenchDraftRecipe(
        title: "No-Rationale Dish",
        ingredientLines: ["1 egg"],
        instructionLines: ["Cook it."],
        rationale: ""
      ),
      learnings: ["Eggs are a constraint."]
    )

    let items = coordinator.workbenchDraftReviewItems(for: review)

    #expect(items.count == 2)
    #expect(items.first?.commitTitle == "Create Working Recipe")
    #expect(items.last?.commitTitle == "Save to Workbench Log")
  }

  @Test
  func recipeAdjustmentRoundTripKeepsTheTokenContractMarkerProseAndLearnings() throws {
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003903")!
    let result = """
    YC-HANDOFF: \(handoffID.uuidString)
    YC-CONTRACT: v3
    Brown the butter before creaming it so the cookies have more nutty depth.
    YC-LEARNINGS:
    - Bacon was rejected because it would overpower the cookie.
    """

    let contractChecked = try AIHandoffReturnContract.strippingMarker(from: result)
    let routed = try #require(AIHandoffToken.stripping(from: contractChecked.text))
    let returned = AIHandoffReturn.plainText(from: routed.payload)

    #expect(routed.handoffID == handoffID)
    #expect(returned.deliverable == "Brown the butter before creaming it so the cookies have more nutty depth.")
    #expect(returned.learnings == ["Bacon was rejected because it would overpower the cookie."])
  }
}
