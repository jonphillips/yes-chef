import Foundation
import Testing
@testable import YesChef

@Suite
@MainActor
struct ChatAssistantSelectionTests {
  @Test
  func resignationRetainsSelectionUntilItIsConsumedOrCleared() {
    let selection = ChatAssistantSelection()
    let owner = NSObject()
    selection.update("The selected dish.", owner: owner)

    selection.relinquish(owner: owner)

    #expect(selection.text == "The selected dish.")
    selection.clear(ifMatching: "A different selection")
    #expect(selection.text == "The selected dish.")
    selection.clear(ifMatching: "The selected dish.")
    #expect(selection.text.isEmpty)
  }
}
