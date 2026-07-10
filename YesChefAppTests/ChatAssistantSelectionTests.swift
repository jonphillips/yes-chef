import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore
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

  // Guards the ADR-0027 D2 transcript-scan path. The verb must NOT require a subject: when it does,
  // the no-selection case falls back to the latest-reply subject and `run` feeds that reply in as
  // `selection`, so the client's transcript branch never runs. `requiresSubject == false` is what
  // routes an empty selection into `extract`, letting the client scan the assistant transcript.
  @Test
  func captureToMenuActionDoesNotRequireASubject() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let menuID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A7")!
      let chatModel = RecipeChatModel(context: .menu(MenuChatContext(title: "Test", dayCount: 1)))
      let catalog = MenuDetailModel(menuID: menuID).applyActionCatalog(for: chatModel)

      let harvest = try #require(catalog.first { $0.title == "Capture to menu" })
      #expect(harvest.requiresSubject == false)
    }
  }
}
