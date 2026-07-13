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
  func tokenPrefixesTheExportAndStripsOnlyItsHeaderFromTheReturn() throws {
    let handoffID = SampleUUIDSequence.uuid(38_001)
    let prompt = AIHandoffToken.prompt(handoffID: handoffID, context: "Menu context")

    #expect(prompt.hasPrefix("YC-HANDOFF: \(handoffID.uuidString)\n"))
    #expect(prompt.contains("Preserve that token exactly"))

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
        now: importedAt
      )
      expectNoDifference(imported, .imported)
      expectNoDifference(
        MenuPrepPlanCoding.decode(try Menu.find(menuID).fetchOne(db)?.prepPlan),
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
        currentPlan: MenuPrepPlan(steps: MenuPrepPlanCoding.decode(try Menu.find(menuID).fetchOne(db)?.prepPlan)),
        in: db,
        now: importedAt.addingTimeInterval(60)
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
        now: importedAt.addingTimeInterval(120)
      )
      expectNoDifference(fallback, .applied)
      expectNoDifference(
        MenuPrepPlanCoding.decode(try Menu.find(menuID).fetchOne(db)?.prepPlan),
        [PrepPlanStep(session: "Thursday morning", task: "Chop the herbs")]
      )
    }
  }
}
