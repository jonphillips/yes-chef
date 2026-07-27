import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct OnboardChatFinalizationTests {
  @Test
  func failedTerminalTurnStagesNothingAndSurfacesTheModelError() async throws {
    var stagedResults: [String] = []

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.modelClient = StubModelClient { request in
        if request.messages.contains(where: { $0.text == "Finalize." }) {
          throw OnboardFinalizationFailure.unavailable
        }
        return ModelResponse(text: "Make the sauce a day ahead.")
      }
    } operation: {
      let chatModel = RecipeChatModel(
        context: .recipe(RecipeChatRecipeContext(title: "Tomato Sauce"))
      )
      await chatModel.send("How should I prep this?")
      let existingReplyID = try #require(chatModel.messages.last(where: { $0.role == .assistant })?.id)

      let error = await OnboardChatFinalizer.finalize(using: chatModel) { result in
        stagedResults.append(result)
      }

      #expect(stagedResults.isEmpty)
      #expect(error != nil)
      #expect(error == chatModel.errorText)
      #expect(chatModel.messages.last(where: { $0.role == .assistant })?.id == existingReplyID)
    }
  }

  @Test
  func everyOnboardFinalizerActionResolvesInItsActualCatalog() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      // Building the catalogs reaches for `\.date`; without an override that is an unimplemented
      // dependency access and Dependencies reports it as a test issue.
      $0.date = .constant(Date(timeIntervalSinceReferenceDate: 840_100_000))
    } operation: {
      let recipeID = UUID(uuidString: "00000000-0000-0000-0000-000000004511")!
      let recipeChat = RecipeChatModel(
        context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
      )
      let recipeCatalog = RecipeDetailModel(recipeID: recipeID).applyActionCatalog(for: recipeChat)

      let expectedRecipeActionIDs: [PlaybookSectionKind: AnyChatApplyAction.ID] = [
        .makeAhead: "Create Make-ahead",
        .chefItUp: "Chef It Up",
        .serveWith: "Capture Side Dishes",
      ]
      for section in PlaybookSectionKind.allCases {
        let configuration = ChatFinalizeConfiguration.recipe(recipeID: recipeID, section: section)
        #expect(configuration.actionID == expectedRecipeActionIDs[section])
        #expect(recipeCatalog.contains { $0.id == configuration.actionID })
      }

      let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000004512")!
      let menuChat = RecipeChatModel(
        context: .menu(MenuChatContext(title: "Beach Menu", dayCount: 2))
      )
      let menuCatalog = MenuDetailModel(menuID: menuID).applyActionCatalog(for: menuChat)
      let menuConfiguration = ChatFinalizeConfiguration.menu(menuID: menuID)

      #expect(menuCatalog.contains { $0.id == menuConfiguration.actionID })
    }
  }
}

private enum OnboardFinalizationFailure: Error, Sendable {
  case unavailable
}
