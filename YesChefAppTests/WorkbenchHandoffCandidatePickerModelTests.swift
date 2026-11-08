import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct WorkbenchHandoffCandidatePickerModelTests {
  @Test
  func pickerReportsFrontierFitAndExportsOnlyTheSelectedCandidatesInWorkbenchOrder() {
    let ids = (0..<3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))! }
    let context = WorkbenchChatContext(
      title: "Soup",
      candidates: ids.enumerated().map { index, id in
        WorkbenchCandidateChatContext(
          id: id,
          title: "Candidate \(index)",
          sortOrder: index,
          summary: index == 2 ? String(repeating: "long", count: 45_000) : nil
        )
      }
    )
    let state = WorkbenchHandoffPickerState(
      source: .workbench(UUID(), task: .draft),
      context: context,
      selectedCandidateIDs: Set(ids)
    )
    let model = WorkbenchHandoffCandidatePickerModel(state: state)
    let serialization = model.serialization

    #expect(!model.isCopyDisabled)
    #expect(model.fitDescription(using: serialization) == "Too much to send: Candidate 2 would be left out")
    #expect(serialization.includedCandidateIDs == Array(ids.prefix(2)))

    model.selectedCandidateIDs = [ids[0]]
    #expect(model.orderedSelection == [ids[0]])
    let prompt = context.draftHandoffPrompt(candidateIDs: model.orderedSelection)
    #expect(prompt.contains("Candidate 0"))
    #expect(!prompt.contains("Candidate 1"))
    #expect(!prompt.contains("Candidate 2"))

    model.selectedCandidateIDs = []
    #expect(model.isCopyDisabled)
  }

  @Test
  func compareExportCarriesCandidateSelectionThroughTheAppOperation() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 900_300_000)
    let workbenchID = UUID(uuidString: "00000000-0000-0000-0000-000000008001")!
    let recipeIDs = (0..<3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 8_010 + $0))! }
    let candidateIDs = (0..<3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 8_020 + $0))! }
    let handoffID = UUID(uuidString: "00000000-0000-0000-0000-000000008030")!

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        for (index, recipeID) in recipeIDs.enumerated() {
          try Recipe.insert {
            Recipe(id: recipeID, title: "Candidate \(index)", dateCreated: now, dateModified: now)
          }
          .execute(db)
        }
        var generatedIDs = [workbenchID] + candidateIDs
        _ = try WorkbenchRepository.addWorkbench(
          title: "Soup Study",
          candidateRecipeIDs: recipeIDs,
          in: db,
          now: now,
          uuid: { generatedIDs.removeFirst() }
        )
      }

      let source = HandoffExportSource.workbench(workbenchID, task: .compare)
        .withCandidateIDs([candidateIDs[1]])
      let handoff = try await HandoffAppOperations.export(
        source: source,
        mode: .discuss,
        in: database,
        now: now,
        handoffID: handoffID
      )

      #expect(handoff.prompt.contains("Candidate 1"))
      #expect(!handoff.prompt.contains("Candidate 0"))
      #expect(!handoff.prompt.contains("Candidate 2"))
    }
  }
}
