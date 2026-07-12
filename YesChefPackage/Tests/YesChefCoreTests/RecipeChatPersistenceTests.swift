import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Synchronization
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeChatErrorTextTests {
    @Test
    func timeoutErrorGetsActionableMessage() {
      let message = RecipeChatErrorText.describe(URLError(.timedOut))
      #expect(message.contains("timed out"))
      #expect(message.contains("Try again"))
    }

    @Test
    func offlineErrorMentionsConnection() {
      let message = RecipeChatErrorText.describe(URLError(.notConnectedToInternet))
      #expect(message.contains("internet connection"))
    }
  }

  @Suite
  struct RecipeChatPersistenceTests {
    @Test
    @MainActor
    func consecutiveOpenAITurnsThreadAndPersistResponseID() async {
      let recipeID = SampleUUIDSequence.uuid(710)
      let requests = Mutex<[ModelRequest]>([])
      let responseCount = Mutex(0)
      let keyStore = chatAPIKeyStore()
      keyStore.setKey("sk-openai-test", for: .openai)

      await withDependencies {
        $0.apiKeyStore = keyStore
        $0.date.now = Date(timeIntervalSinceReferenceDate: 820_500_000)
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient { request in
          requests.withLock { $0.append(request) }
          let index = responseCount.withLock { count in
            count += 1
            return count
          }
          return ModelResponse(
            text: "Answer \(index)",
            continuationToken: ModelContinuationToken(
              provider: .openai,
              value: "resp_\(index)"
            )
          )
        }
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )
        model.selectedProvider = .openai
        model.useFrontier = true

        await model.send("First question")
        await model.send("Follow up")

        let captured = requests.withLock { $0 }
        #expect(captured.count == 2)
        #expect(captured[0].continuationToken == nil)
        expectNoDifference(
          captured[1].continuationToken,
          ModelContinuationToken(provider: .openai, value: "resp_1")
        )
        #expect(captured[1].messages.count == 3)

        let reloaded = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )
        expectNoDifference(
          reloaded.continuationToken,
          ModelContinuationToken(provider: .openai, value: "resp_2")
        )
      }
    }

    @Test
    @MainActor
    func providerSwitchInvalidatesOpenAIResponseIDAndSendsFullContext() async {
      let recipeID = SampleUUIDSequence.uuid(711)
      let requests = Mutex<[ModelRequest]>([])
      let responseCount = Mutex(0)
      let keyStore = chatAPIKeyStore()
      keyStore.setKey("sk-openai-test", for: .openai)
      keyStore.setKey("sk-anthropic-test", for: .anthropic)

      await withDependencies {
        $0.apiKeyStore = keyStore
        $0.date.now = Date(timeIntervalSinceReferenceDate: 820_600_000)
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient { request in
          requests.withLock { $0.append(request) }
          let index = responseCount.withLock { count in
            count += 1
            return count
          }
          return ModelResponse(
            text: "Answer \(index)",
            continuationToken: request.tier == .frontier(.openai)
              ? ModelContinuationToken(provider: .openai, value: "resp_\(index)")
              : nil
          )
        }
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )
        model.selectedProvider = .openai
        model.useFrontier = true
        await model.send("First question")

        model.selectedProvider = .anthropic
        await model.send("Different provider")

        let second = requests.withLock { $0[1] }
        #expect(second.continuationToken == nil)
        #expect(second.messages.count == 3)
      }
    }

    @Test
    @MainActor
    func tierDegradationInvalidatesOpenAIResponseIDAndSendsFullContext() async {
      let recipeID = SampleUUIDSequence.uuid(712)
      let requests = Mutex<[ModelRequest]>([])
      let keyStore = chatAPIKeyStore()
      keyStore.setKey("sk-openai-test", for: .openai)

      await withDependencies {
        $0.apiKeyStore = keyStore
        $0.date.now = Date(timeIntervalSinceReferenceDate: 820_700_000)
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient { request in
          requests.withLock { $0.append(request) }
          return ModelResponse(
            text: "Answer",
            continuationToken: request.tier == .frontier(.openai)
              ? ModelContinuationToken(provider: .openai, value: "resp_1")
              : nil
          )
        }
      } operation: {
        let model = RecipeChatModel(
          context: .recipe(RecipeChatRecipeContext(recipeID: recipeID, title: "Tomato Sauce"))
        )
        model.selectedProvider = .openai
        model.useFrontier = true
        await model.send("First question")

        keyStore.setKey(nil, for: .openai)
        await model.send("No key now")

        let second = requests.withLock { $0[1] }
        #expect(second.tier == .onDevice)
        #expect(second.continuationToken == nil)
        #expect(second.messages.count == 3)
      }
    }

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

private func chatAPIKeyStore() -> APIKeyStore {
  let storage = Mutex<[FrontierProvider: String]>([:])
  return APIKeyStore(
    read: { provider in storage.withLock { $0[provider] } },
    write: { provider, key in storage.withLock { $0[provider] = key } }
  )
}
