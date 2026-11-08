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

    #expect(!model.isCopyDisabled)
    #expect(model.fitDescription == "Too much to send: Candidate 2 would be left out")
    #expect(model.serialization.includedCandidateIDs == Array(ids.prefix(2)))

    model.selectedCandidateIDs = [ids[0]]
    #expect(model.orderedSelection == [ids[0]])
    let prompt = context.draftHandoffPrompt(candidateIDs: model.orderedSelection)
    #expect(prompt.contains("Candidate 0"))
    #expect(!prompt.contains("Candidate 1"))
    #expect(!prompt.contains("Candidate 2"))

    model.selectedCandidateIDs = []
    #expect(model.isCopyDisabled)
  }
}
