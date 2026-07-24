import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct AIHandoffTests {
  @Test
  func handoffPromptUsesTheTitleThenTokenAndTheProjectContractOwnsTheReturnShape() throws {
    let handoffID = SampleUUIDSequence.uuid(38_001)
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      title: "Prep Plan: Beach Menu",
      context: "Menu context"
    )

    #expect(prompt.hasPrefix("Prep Plan: Beach Menu\nYC-HANDOFF: \(handoffID.uuidString)\n"))
    #expect(!prompt.contains(AIHandoffReturnContract.marker))
    #expect(AIHandoffReturnContract.projectInstructions.contains(AIHandoffReturnContract.marker))
    #expect(AIHandoffReturnContract.projectInstructions.contains("Return no preamble, sign-off, headings, or nesting"))
    #expect(AIHandoffReturnContract.projectInstructions.contains("Hypothesis: <one sentence>"))
    #expect(AIHandoffReturnContract.projectInstructions.contains("Do not include `YC-LEARNINGS:` for Experiments"))

    let routedText = try #require(
      AIHandoffToken.stripping(
        from: """
        YC-HANDOFF: \(handoffID.uuidString)
        Wednesday evening:
        - Salt the chicken → Thursday dinner
        """
      )
    )
    expectNoDifference(routedText.handoffID, handoffID)
    expectNoDifference(
      routedText.payload,
      """
      Wednesday evening:
      - Salt the chicken → Thursday dinner
      """
    )
  }

  @Test
  func immediatePromptRequestsTheResultWithoutDuplicatingTheProjectReturnContract() {
    let handoffID = SampleUUIDSequence.uuid(38_002)
    let prompt = AIHandoffToken.prompt(
      handoffID: handoffID,
      context: "Menu context",
      mode: .immediate
    )

    #expect(prompt.contains("Return the completed prep plan in your first response when the menu needs one."))
    #expect(!prompt.contains(AIHandoffReturnContract.marker))
    #expect(!prompt.contains("YC-LEARNINGS:"))
  }

  @Test
  func currentContractMarkerIsRequiredAndRemovedBeforeRouting() {
    let result = """
    YC-HANDOFF: \(SampleUUIDSequence.uuid(38_003).uuidString)
    \(AIHandoffReturnContract.marker)
    Comparison text
    """

    expectNoDifference(
      AIHandoffReturnContract.strippingMarker(from: result),
      """
      YC-HANDOFF: \(SampleUUIDSequence.uuid(38_003).uuidString)
      Comparison text
      """
    )
    #expect(AIHandoffReturnContract.strippingMarker(from: "YC-CONTRACT: v0") == nil)
    #expect(AIHandoffReturnContract.strippingMarker(from: "Comparison text") == nil)
  }

  @Test
  func twoPartReturnSplitsBeforePrepPlanParsingAndKeepsDistinctLearningBullets() {
    let returned = AIHandoffReturn.menuPrepPlan(
      from: """
      Wednesday evening:
      - Salt the chicken → Thursday dinner
      ## **yc-learnings:**
      - Dried bay leaves beat fresh.
      - Salt the chicken a day ahead.
      - Dried bay leaves beat fresh.
      """,
      currentPlan: MenuPrepPlan()
    )

    expectNoDifference(
      returned.plan.steps,
      [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
    )
    expectNoDifference(
      returned.learnings,
      ["Dried bay leaves beat fresh.", "Salt the chicken a day ahead."]
    )
  }

  @Test
  func matchedMenuHandoffImportsOnceAndMissingHandoffPreservesManualPaste() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_010)
    let handoffID = SampleUUIDSequence.uuid(38_011)
    let otherHandoffID = SampleUUIDSequence.uuid(38_012)
    let createdAt = Date(timeIntervalSinceReferenceDate: 840_000_000)
    let importedAt = createdAt.addingTimeInterval(60)

    try database.write { db in
      try Menu.insert {
        Menu(
          id: menuID,
          title: "Beach Menu",
          dayCount: 2,
          dateCreated: createdAt,
          dateModified: createdAt
        )
      }
      .execute(db)
      try AIHandoffRepository.create(
        AIHandoff(
          id: handoffID,
          sourceType: .menu,
          sourceID: menuID,
          taskType: .prepPlan,
          createdAt: createdAt,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let imported = try AIHandoffMenuPrepPlanImport.apply(
        text: """
        YC-HANDOFF: \(handoffID.uuidString)
        Wednesday evening:
        - Salt the chicken → Thursday dinner
        """,
        to: menuID,
        currentPlan: MenuPrepPlan(),
        in: db,
        now: importedAt,
        uuid: { SampleUUIDSequence.uuid(38_013) }
      )
      expectNoDifference(imported, .imported)
      expectNoDifference(
        try PrepPlanStepRepository.steps(for: menuID, in: db).map { PrepPlanStep($0) },
        [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
      )
      let handoff = try #require(try AIHandoffRepository.handoff(id: handoffID, in: db))
      expectNoDifference(handoff.status, .imported)
      expectNoDifference(handoff.importedAt, importedAt)

      let duplicate = try AIHandoffMenuPrepPlanImport.apply(
        text: """
        YC-HANDOFF: \(handoffID.uuidString)
        """,
        to: menuID,
        currentPlan: MenuPrepPlan(
          steps: try PrepPlanStepRepository.steps(for: menuID, in: db).map { PrepPlanStep($0) }
        ),
        in: db,
        now: importedAt.addingTimeInterval(60),
        uuid: { SampleUUIDSequence.uuid(38_014) }
      )
      expectNoDifference(duplicate, .duplicate)

      let fallback = try AIHandoffMenuPrepPlanImport.apply(
        text: """
        YC-HANDOFF: \(otherHandoffID.uuidString)
        Thursday morning:
        - Chop the herbs
        """,
        to: menuID,
        currentPlan: MenuPrepPlan(),
        in: db,
        now: importedAt.addingTimeInterval(120),
        uuid: { SampleUUIDSequence.uuid(38_015) }
      )
      expectNoDifference(fallback, .applied)
      expectNoDifference(
        try PrepPlanStepRepository.steps(for: menuID, in: db).map { PrepPlanStep($0) },
        [PrepPlanStep(session: "Thursday morning", task: "Chop the herbs")]
      )
    }
  }

  @Test
  func manualPastePersistsTwoPartAndLearningOnlyReturns() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_016)
    let handoffID = SampleUUIDSequence.uuid(38_017)
    let learningOnlyHandoffID = SampleUUIDSequence.uuid(38_018)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    var uuids = SampleUUIDSequence(start: 38_100)

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

      let twoPart = try AIHandoffMenuPrepPlanImport.apply(
        text: """
        YC-HANDOFF: \(handoffID.uuidString)
        Wednesday evening:
        - Salt the chicken → Thursday dinner
        **YC-LEARNINGS:**
        - Dried bay leaves beat fresh.
        - Birria benefits from sitting overnight.
        """,
        to: menuID,
        currentPlan: MenuPrepPlan(),
        in: db,
        now: now,
        uuid: { uuids.next() }
      )
      expectNoDifference(twoPart, .imported)
      expectNoDifference(
        try PrepPlanStepRepository.steps(for: menuID, in: db).map { PrepPlanStep($0) },
        [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
      )

      try AIHandoffRepository.create(
        AIHandoff(
          id: learningOnlyHandoffID,
          sourceType: .menu,
          sourceID: menuID,
          taskType: .learning,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(learningOnlyHandoffID.uuidString)"
        ),
        in: db
      )
      let learningOnly = try AIHandoffMenuPrepPlanImport.apply(
        text: """
        YC-HANDOFF: \(learningOnlyHandoffID.uuidString)
        ## YC-LEARNINGS:
        - Salt the chicken a day ahead.
        """,
        to: menuID,
        currentPlan: MenuPrepPlan(
          steps: try PrepPlanStepRepository.steps(for: menuID, in: db).map { PrepPlanStep($0) }
        ),
        in: db,
        now: now,
        uuid: { uuids.next() }
      )
      expectNoDifference(learningOnly, .imported)
      expectNoDifference(
        try PrepPlanStepRepository.steps(for: menuID, in: db).map { PrepPlanStep($0) },
        [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
      )
      expectNoDifference(
        try Learning
          .where { $0.sourceType.eq(AIHandoffSourceType.menu) && $0.sourceID.eq(menuID) }
          .fetchAll(db)
          .map(\.text)
          .sorted(),
        [
          "Birria benefits from sitting overnight.",
          "Dried bay leaves beat fresh.",
          "Salt the chicken a day ahead.",
        ]
      )
    }
  }

  @Test
  func intentImportStagesAReviewOnceWithoutWritingTheMenuPlan() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_020)
    let handoffID = SampleUUIDSequence.uuid(38_021)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

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

      let review = try AIHandoffIntentImport.stageMenuPrepPlanReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Wednesday evening:
        - Salt the chicken → Thursday dinner
        """,
        in: db,
        now: now
      )
      expectNoDifference(review.menuID, menuID)
      expectNoDifference(
        review.plan.steps,
        [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
      )
      expectNoDifference(review.learnings, [])
      #expect(try Menu.find(menuID).fetchOne(db)?.prepPlan == nil)
      #expect(try AIHandoffRepository.handoff(id: handoffID, in: db)?.status == .imported)

      #expect(
        throws: AIHandoffIntentImportError.duplicate,
        performing: {
          _ = try AIHandoffIntentImport.stageMenuPrepPlanReview(
            handoffID: handoffID,
            result: "Wednesday evening:\n- Duplicate import",
            in: db,
            now: now
          )
        }
      )
    }
  }

  @Test
  func intentImportStagesUnparsedPlanLinesAlongsideValidContent() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_029)
    let handoffID = SampleUUIDSequence.uuid(38_030)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

    try database.write { db in
      try Menu.insert {
        Menu(id: menuID, title: "Beach Menu", dayCount: 2, dateCreated: now, dateModified: now)
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

      let review = try AIHandoffIntentImport.stageMenuPrepPlanReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        Wednesday evening:
        - Salt the chicken → Thursday dinner
        Let me know if you'd like changes!
        YC-LEARNINGS:
        - Salt early for better seasoning.
        """,
        in: db,
        now: now
      )

      expectNoDifference(
        review.plan.steps,
        [PrepPlanStep(session: "Wednesday evening", task: "Salt the chicken", serves: "Thursday dinner")]
      )
      expectNoDifference(review.unparsedPlanLines, ["Let me know if you'd like changes!"])
      expectNoDifference(review.learnings, ["Salt early for better seasoning."])
      #expect(try Menu.find(menuID).fetchOne(db)?.prepPlan == nil)
    }
  }

  @Test
  func learningOnlyIntentImportStagesWithoutWritingTheMenuPlan() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_022)
    let handoffID = SampleUUIDSequence.uuid(38_023)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

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
          taskType: .learning,
          createdAt: now,
          exportedPrompt: "YC-HANDOFF: \(handoffID.uuidString)"
        ),
        in: db
      )

      let review = try AIHandoffIntentImport.stageMenuPrepPlanReview(
        handoffID: handoffID,
        result: """
        YC-HANDOFF: \(handoffID.uuidString)
        YC-LEARNINGS:
        - Dried bay leaves beat fresh.
        - Birria benefits from sitting overnight.
        """,
        in: db,
        now: now
      )
      expectNoDifference(review.plan.steps, [])
      expectNoDifference(
        review.learnings,
        ["Dried bay leaves beat fresh.", "Birria benefits from sitting overnight."]
      )
      #expect(try Menu.find(menuID).fetchOne(db)?.prepPlan == nil)
    }
  }

  @Test
  func menuDeletionHandCascadesItsLearnings() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_024)
    let learningID = SampleUUIDSequence.uuid(38_025)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

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
      try LearningRepository.create(
        Learning(
          id: learningID,
          sourceType: .menu,
          sourceID: menuID,
          text: "Dried bay leaves beat fresh.",
          provenance: .externalHandoff,
          dateCreated: now,
          dateModified: now
        ),
        in: db
      )

      try MenuRepository.deleteMenu(menuID: menuID, in: db)
      #expect(try Learning.find(learningID).fetchOne(db) == nil)
    }
  }

  @Test
  func learningEditsKeepProvenanceAndSingleDeleteTargetsOnlyThatRow() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_026)
    let firstID = SampleUUIDSequence.uuid(38_027)
    let secondID = SampleUUIDSequence.uuid(38_028)
    let createdAt = Date(timeIntervalSinceReferenceDate: 840_000_000)
    let modifiedAt = createdAt.addingTimeInterval(60)

    try database.write { db in
      for (id, text) in [(firstID, "Use dried bay leaves."), (secondID, "Toast the cumin.")] {
        try LearningRepository.create(
          Learning(
            id: id,
            sourceType: .menu,
            sourceID: menuID,
            text: text,
            provenance: .externalHandoff,
            dateCreated: createdAt,
            dateModified: createdAt
          ),
          in: db
        )
      }
      try LearningRepository.update(
        id: firstID,
        text: "Use dried Mexican bay leaves.",
        in: db,
        now: modifiedAt
      )
      try LearningRepository.delete(id: secondID, in: db)

      expectNoDifference(
        try Learning.find(firstID).fetchOne(db),
        Learning(
          id: firstID,
          sourceType: .menu,
          sourceID: menuID,
          text: "Use dried Mexican bay leaves.",
          provenance: .externalHandoff,
          dateCreated: createdAt,
          dateModified: modifiedAt
        )
      )
      #expect(try Learning.find(secondID).fetchOne(db) == nil)
    }
  }

  @Test
  func menuExternalProjectNameIsTrimmedAndCanBeCleared() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_030)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)

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

      try MenuRepository.updateExternalProjectName(
        menuID: menuID,
        externalProjectName: "  Emerald Isle Beach  ",
        in: db,
        now: now
      )
      #expect(try Menu.find(menuID).fetchOne(db)?.externalProjectName == "Emerald Isle Beach")

      try MenuRepository.updateExternalProjectName(
        menuID: menuID,
        externalProjectName: "   ",
        in: db,
        now: now
      )
      #expect(try Menu.find(menuID).fetchOne(db)?.externalProjectName == nil)
    }
  }

}
