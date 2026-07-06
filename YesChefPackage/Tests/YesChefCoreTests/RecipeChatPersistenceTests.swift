import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeChatPersistenceTests {
    @Test
    @MainActor
    func recipeChatPersistsAcrossModelsForSameRecipeSubject() async {
      let recipeID = SampleUUIDSequence.uuid(700)
      let sentAt = Date(timeIntervalSinceReferenceDate: 820_100_000)

      await withDependencies {
        $0.date.now = sentAt
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient.constant("Make the sauce tomorrow.")
      } operation: {
        let first = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )

        await first.send("Can I prep this ahead?")

        let second = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce, revised"))
        )

        expectNoDifference(
          second.messages.map(MessageSnapshot.init(message:)),
          [
            MessageSnapshot(role: .user, text: "Can I prep this ahead?"),
            MessageSnapshot(role: .assistant, text: "Make the sauce tomorrow."),
          ]
        )
      }
    }

    @Test
    @MainActor
    func chatPersistenceIsIsolatedBySubject() async {
      let tomatoID = SampleUUIDSequence.uuid(701)
      let soupID = SampleUUIDSequence.uuid(702)

      await withDependencies {
        $0.date.now = Date(timeIntervalSinceReferenceDate: 820_200_000)
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient.constant("Use low heat.")
      } operation: {
        let tomato = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: tomatoID, title: "Tomato Sauce"))
        )
        await tomato.send("How do I avoid scorching?")

        let soup = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: soupID, title: "Tomato Soup"))
        )

        expectNoDifference(soup.messages, [])
      }
    }

    @Test
    @MainActor
    func mealPlanChatUsesSelectedDayAsSubject() async {
      let calendar = Calendar(identifier: .gregorian)
      let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 4))!

      await withDependencies {
        $0.date.now = Date(timeIntervalSinceReferenceDate: 820_300_000)
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient.constant("Prep the salad first.")
      } operation: {
        let first = RecipeChatModel(
          context: .mealPlan(MealPlanChatContext(title: "Saturday, July 4", subjectDate: day))
        )
        await first.send("What should I do first?")

        let sameDay = RecipeChatModel(
          context: .mealPlan(MealPlanChatContext(title: "July 4", subjectDate: day))
        )

        expectNoDifference(
          sameDay.messages.map(MessageSnapshot.init(message:)),
          [
            MessageSnapshot(role: .user, text: "What should I do first?"),
            MessageSnapshot(role: .assistant, text: "Prep the salad first."),
          ]
        )
      }
    }

    @Test
    @MainActor
    func clearRemovesPersistedChatForSubject() async {
      let recipeID = SampleUUIDSequence.uuid(706)

      await withDependencies {
        $0.date.now = Date(timeIntervalSinceReferenceDate: 820_450_000)
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient.constant("Use low heat.")
      } operation: {
        let first = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )
        await first.send("How do I avoid scorching?")

        first.clear()

        let second = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )
        expectNoDifference(second.messages, [])
      }
    }

    @Test
    func chatStorePrunesMessagesOlderThanRetention() throws {
      @Dependency(\.defaultDatabase) var database
      let subject = RecipeChatSubject.recipe(SampleUUIDSequence.uuid(703))
      let now = Date(timeIntervalSinceReferenceDate: 820_400_000)
      let retained = RecipeChatMessage(
        id: SampleUUIDSequence.uuid(704),
        role: .user,
        text: "Still useful"
      )
      let expired = ChatMessageRecord(
        id: SampleUUIDSequence.uuid(705),
        subjectKind: subject.kind,
        subjectID: subject.id,
        role: .assistant,
        text: "Too old",
        createdAt: now.addingTimeInterval(-RecipeChatStore.retention - 1),
        sortOrder: 0
      )

      try database.write { db in
        try ChatMessageRecord.insert { expired }.execute(db)
        try RecipeChatStore.replaceMessages([retained], for: subject, in: db, now: now)

        let messages = try RecipeChatStore.fetchMessages(for: subject, in: db)
        expectNoDifference(messages, [retained])
      }
    }
  }
}

private struct MessageSnapshot: Equatable {
  var role: RecipeChatMessage.Role
  var text: String

  init(role: RecipeChatMessage.Role, text: String) {
    self.role = role
    self.text = text
  }

  init(message: RecipeChatMessage) {
    self.init(role: message.role, text: message.text)
  }
}
