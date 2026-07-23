import LLMClientKit
import Testing
import YesChefCore

@Suite
struct ModelCallInventoryTests {
  @Test
  func appendOnlyCollectorSnapshotsAddOnlyNewRecordsWithStableEntryIDs() {
    let first = record(task: .categorization)
    let second = record(task: .feedbackCuration)
    var inventory = ModelCallInventory()

    inventory.appendNewRecords(from: [first])
    inventory.appendNewRecords(from: [first, second])

    #expect(inventory.entries.map(\.id) == [0, 1])
    #expect(inventory.entries.map(\.record) == [first, second])
  }

  private func record(task: ModelCallTask) -> ModelCallRecord {
    ModelCallRecord(
      surface: .recipe,
      task: task,
      tierResolution: .callerProvided,
      tier: .onDevice,
      contextLayers: [],
      inputCharacterCount: 0,
      maxTokens: 0,
      reasoningEffort: nil
    )
  }
}
