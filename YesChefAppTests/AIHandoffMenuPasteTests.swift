import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct AIHandoffMenuPasteTests {
  @Test
  func duplicatePasteInformsWithoutReplacingTheImportedPlan() throws {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000003801")!
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003802")!
    let now = Date(timeIntervalSinceReferenceDate: 840_100_000)
    let firstPaste = """
      YC-HANDOFF: \(handoffID.uuidString)
      Wednesday evening:
      - Salt the chicken → Thursday dinner
      """
    let repeatedPaste = """
      YC-HANDOFF: \(handoffID.uuidString)
      Thursday morning:
      - This old clipboard must not replace the plan
      """

    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try Menu.insert {
          Menu(
            id: menuID,
            title: "Beach Menu",
            dayCount: 2,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try AIHandoffRepository.create(
          AIHandoff(
            id: handoffID,
            sourceType: .menu,
            sourceID: menuID,
            taskType: .prepPlan,
            createdAt: now,
            exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
          ),
          in: db
        )
      }

      let model = MenuDetailModel(menuID: menuID)
      model.prepPlanPasted(firstPaste)
      model.prepPlanPasted(repeatedPaste)

      #expect(model.information == .alreadyImported)
      #expect(model.isShowingError == false)
      let storedSteps = try database.read { db in
        try PrepPlanStepRepository.steps(for: menuID, in: db).map(PrepPlanStep.init)
      }
      #expect(
        storedSteps == [
          PrepPlanStep(
            session: "Wednesday evening",
            task: "Salt the chicken",
            serves: "Thursday dinner"
          )
        ]
      )
    }
  }

  @Test
  func advisoryNotesStayOutOfEditablePrepTextAndDoNotBlockSaving() async throws {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000003803")!
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000003804")!
    let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000003805")!
    let dishID = UUID(uuidString: "00000000-0000-0000-0000-000000003806")!
    let now = Date(timeIntervalSinceReferenceDate: 840_100_000)
    let advisory = "Existing prep step missing from returned plan: Friday: Salt the chicken"

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.modelClient = StubModelClient { request in
        if request.messages.last?.text == "Finalize." {
          return ModelResponse(text: "Sunday morning:\n- Make the salsa → Sunday dinner")
        }
        return ModelResponse(text: "Let's make a fresh plan.")
      }
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Beach Menu", dayCount: 2, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(
            id: stepID,
            menuID: menuID,
            sortOrder: 0,
            session: "Saturday",
            task: "Soak the beans",
            sourceDish: dishID
          )
        }
        .execute(db)
      }

      let review = AIHandoffMenuPrepPlanReview(
        handoffID: handoffID,
        menuID: menuID,
        plan: MenuPrepPlan(
          steps: [PrepPlanStep(session: "Saturday", task: "Soak the beans", sourceDish: dishID)]
        ),
        learnings: [],
        advisoryNotes: [advisory]
      )
      let item = try #require(HandoffReviewCoordinator().reviewItems(for: .menuPrepPlan(review)).first)
      let editableText = try #require(item.editableText)

      #expect(!editableText.contains(advisory))
      #expect(item.supportingEvidenceTitle == "Review omitted steps before saving")
      #expect(item.supportingEvidenceRows == [advisory])
      try await item.commit(editableText, usingSecondaryCommit: false)
      let remainingSteps = try await database.read { db in
        try PrepPlanStepRepository.steps(for: menuID, in: db).map(PrepPlanStep.init)
      }
      // `sourceDish` survives the commit. It is not incidental: `droppedSourceDishEvidence` exists
      // to warn when the returned plan loses a step's dish link, so preserving it through a
      // round-trip is the behavior being protected here.
      #expect(
        remainingSteps == [
          PrepPlanStep(session: "Saturday", task: "Soak the beans", sourceDish: dishID)
        ]
      )
    }
  }

  @Test
  func regenerationReviewDeclaresTheReplacementWithoutAnOmissionWarning() throws {
    let review = AIHandoffMenuPrepPlanReview(
      handoffID: UUID(uuidString: "00000000-0000-0000-0000-000000003807")!,
      menuID: UUID(uuidString: "00000000-0000-0000-0000-000000003808")!,
      plan: MenuPrepPlan(steps: [PrepPlanStep(session: "Sunday", task: "Make the salsa")]),
      learnings: [],
      prepPlanIntent: .regenerate,
      replacementStepCount: 4
    )

    let item = try #require(HandoffReviewCoordinator().reviewItems(for: .menuPrepPlan(review)).first)

    #expect(item.supportingEvidenceTitle == "This replaces your 4-step prep plan")
    #expect(item.supportingEvidenceRows.isEmpty)
  }

  @Test
  func secondOnboardFinalizeAfterRegenerationSurfacesDroppedSteps() async throws {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000003809")!
    let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000003810")!
    let now = Date(timeIntervalSinceReferenceDate: 840_100_000)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.modelClient = StubModelClient { request in
        if request.messages.last?.text == "Finalize." {
          return ModelResponse(text: "Sunday morning:\n- Make the salsa → Sunday dinner")
        }
        return ModelResponse(text: "Let's make a fresh plan.")
      }
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Beach Menu", dayCount: 2, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(
            id: stepID,
            menuID: menuID,
            sortOrder: 0,
            session: "Friday",
            task: "Salt the chicken"
          )
        }
        .execute(db)
      }

      let model = MenuDetailModel(menuID: menuID)
      model.prepPlanHandoffIntent = .regenerate
      let firstFinalization = ChatFinalizeConfiguration.menu(
        menuID: menuID,
        prepPlanIntent: model.prepPlanHandoffIntent,
        onFinalized: model.onboardPrepPlanFinalized
      )
      let chatModel = RecipeChatModel(context: .menu(MenuChatContext(title: "Beach Menu", dayCount: 2)))
      let seeded = await chatModel.send("Make a fresh prep plan.")
      #expect(seeded)
      let finalizationError = await OnboardChatFinalizer.finalize(
        using: chatModel,
        stage: { _ in },
        onFinalized: firstFinalization.onFinalized
      )
      #expect(finalizationError == nil)

      let secondFinalization = ChatFinalizeConfiguration.menu(
        menuID: menuID,
        prepPlanIntent: model.prepPlanHandoffIntent
      )
      let review = try await HandoffAppOperations.stageOnboardReview(
        source: secondFinalization.source,
        result: """
        Sunday morning:
        - Make the salsa → Sunday dinner
        """,
        in: database,
        now: now,
        handoffID: UUID(uuidString: "00000000-0000-0000-0000-000000003811")!
      )

      guard case let .menuPrepPlan(prepPlanReview) = review else {
        Issue.record("Expected a menu prep-plan review.")
        return
      }
      expectNoDifference(prepPlanReview.prepPlanIntent, .refine)
      expectNoDifference(
        prepPlanReview.advisoryNotes,
        ["Existing prep step missing from returned plan: Friday: Salt the chicken"]
      )
    }
  }
}
