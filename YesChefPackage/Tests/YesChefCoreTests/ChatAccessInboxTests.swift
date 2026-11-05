import Foundation
import Testing
import YesChefCore

struct ChatAccessInboxTests {
  @Test func returnRowsRespectTaskAndDeviceRouting() throws {
    let root = URL(fileURLWithPath: "/tmp/MCP/Inbox", isDirectory: true)
    let singleID = UUID(), repeatID = UUID(), captureID = UUID(), unknownID = UUID()
    func handoff(_ id: UUID, _ source: AIHandoffSourceType, _ task: AIHandoffTaskType) -> AIHandoff {
      AIHandoff(id: id, sourceType: source, sourceID: UUID(), taskType: task,
        createdAt: .distantPast, exportedPrompt: "Task: Soup\nYC-HANDOFF:")
    }
    let values = [handoff(singleID, .menu, .prepPlan), handoff(repeatID, .recipe, .recipe), handoff(captureID, .capture, .recipe)]
    func snapshot(_ time: String, _ slug: String) -> ChatAccessInbox.MetadataSnapshot {
      let url = root.appending(path: "20261022T\(time)Z-\(slug).ycreturn")
      return .init(url: url, name: url.lastPathComponent, isCurrent: true)
    }
    let snapshots = [snapshot("180000", singleID.uuidString), snapshot("190000", singleID.uuidString),
      snapshot("180000", repeatID.uuidString), snapshot("190000", repeatID.uuidString),
      snapshot("180000", captureID.uuidString), snapshot("180000", unknownID.uuidString),
      snapshot("190000", unknownID.uuidString), snapshot("180000", "broken")]
    let rows = ChatAccessInbox.returnRows(from: snapshots) { id in values.first { $0.id == id } }
    let single = try #require(rows.first { if case let .openable(h) = $0.destination { h.id == singleID } else { false } })
    #expect(single.url == snapshots[1].url)
    #expect(single.superseded == [snapshots[0].url])
    #expect(single.title == "Task: Soup")
    #expect(rows.filter { if case let .openable(h) = $0.destination { h.id == repeatID } else { false } }.map(\.url) == [snapshots[2].url, snapshots[3].url])
    #expect(rows.filter { if case .otherDevice = $0.destination { true } else { false } }.count == 2)
    #expect(rows.contains { if case .capture = $0.destination { true } else { false } })
    #expect(rows.contains { if case .unreadable = $0.destination { true } else { false } })
  }

  @Test func returnsStagedInSameSecondUseCollisionSequence() throws {
    let id = UUID()
    let handoff = AIHandoff(id: id, sourceType: .menu, sourceID: UUID(), taskType: .prepPlan,
      createdAt: .distantPast, exportedPrompt: "Plan: Dinner")
    let root = URL(fileURLWithPath: "/tmp/MCP/Inbox", isDirectory: true)
    let urls = ["", "--2", "--10"].map { root.appending(path: "20261022T180000Z-\(id.uuidString)\($0).ycreturn") }
    let snapshots = urls.map { ChatAccessInbox.MetadataSnapshot(url: $0, name: $0.lastPathComponent, isCurrent: true) }
    let row = try #require(ChatAccessInbox.returnRows(from: snapshots) { _ in handoff }.first)
    #expect(row.url == urls[2])
    #expect(row.superseded == Array(urls.prefix(2)))
  }

  @Test func rowsParseBothTimestampFormsSkipBadNamesAndSortNewestFirst() {
    let root = URL(fileURLWithPath: "/tmp/MCP/Inbox", isDirectory: true)
    let snapshots = [
      ChatAccessInbox.MetadataSnapshot(
        url: root.appending(path: "20261022T180000Z-soup.json"), name: "20261022T180000Z-soup.json", isCurrent: false
      ),
      ChatAccessInbox.MetadataSnapshot(
        url: root.appending(path: "2026-10-22T19:00:00Z-stew.json"), name: "2026-10-22T19:00:00Z-stew.json", isCurrent: true
      ),
      ChatAccessInbox.MetadataSnapshot(url: root.appending(path: "20261022T200000Z-return.ycreturn"), name: "20261022T200000Z-return.ycreturn", isCurrent: true),
      ChatAccessInbox.MetadataSnapshot(url: root.appending(path: "malformed.json"), name: "malformed.json", isCurrent: true),
      ChatAccessInbox.MetadataSnapshot(url: root.appending(path: "Processed"), name: "Processed", isCurrent: true),
    ]

    let rows = ChatAccessInbox.rows(from: snapshots)
    #expect(rows.map(\.name) == ["Stew", "Soup"])
    #expect(rows.last?.downloadState == .downloading)
  }

  @Test func rowNameUsesRecipeTitleAndFallsBackToSlugWhenMissingOrBlank() {
    #expect(ChatAccessInbox.displayName(slug: "creme-brulee", recipeName: "Crème Brûlée") == "Crème Brûlée")
    #expect(ChatAccessInbox.displayName(slug: "p-te-choux", recipeName: nil) == "P Te Choux")
    #expect(ChatAccessInbox.displayName(slug: "p-te-choux", recipeName: " \n ") == "P Te Choux")
  }

  @Test func recipeNameReadsTheDeterministicJSONLDTitle() {
    let text = #"{"@context":"https://schema.org","@type":"Recipe","name":"Crème Brûlée","recipeIngredient":["1 cup cream"],"recipeInstructions":[{"@type":"HowToStep","text":"Heat the cream."}]}"#
    #expect(ChatAccessInbox.recipeName(from: text) == "Crème Brûlée")
    #expect(ChatAccessInbox.recipeName(from: "not json") == nil)
  }

  @Test func stagingRejectsMalformedAndIncompleteContractsWithTypedReasons() throws {
    #expect(throws: RecipeContractStagingError.notJSON) {
      try RecipeContractStaging.validate("not json")
    }
    #expect(throws: RecipeContractStagingError.noRecipeNode) {
      try RecipeContractStaging.validate("{\"@type\":\"Thing\"}")
    }
    #expect(throws: RecipeContractStagingError.missingIngredientsOrInstructions) {
      try RecipeContractStaging.validate("{\"@type\":\"Recipe\",\"recipeIngredient\":[\"1 cup water\"]}")
    }
  }

  @Test func stagingAcceptsACompleteRecipeThroughTheDeterministicPath() throws {
    let text = """
      {"@context":"https://schema.org","@type":"Recipe","name":"Soup","recipeIngredient":["1 cup water"],"recipeInstructions":[{"@type":"HowToStep","text":"Heat the water."}]}
      """
    let extraction = try RecipeContractStaging.validate(text)
    #expect(extraction.title == "Soup")
    #expect(extraction.ingredientSections.flatMap(\.lines) == ["1 cup water"])
    #expect(extraction.instructionSections.flatMap(\.steps) == ["Heat the water."])
  }

  @Test func serverInstructionsCarryTheProjectContractAndPasteFallback() {
    #expect(ChatAccessServerInstructions.text.hasPrefix("These are Yes Chef's recipe tools."))
    #expect(ChatAccessServerInstructions.text.contains(RecipeJSONLDContract.projectSource))
    let text = ChatAccessServerInstructions.text
    let opening = String(text.prefix(512))
    #expect(opening.contains("stage_recipe"))
    #expect(opening.contains("stage_handoff_return"))
    #expect(text.contains(AIHandoffReturnContract.projectInstructions))
    #expect(text.contains("If a tool call fails or times out, print the return block or the JSON-LD object for Jon to paste instead."))
    let libraryCheck = "Before suggesting a recipe, check the Yes Chef library with the read tools."
    #expect(text.components(separatedBy: libraryCheck).count == 2)
  }

  @Test func projectDocumentsMatchTheirCanonicalSources() throws {
    let packageDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let repository = packageDirectory.deletingLastPathComponent()
    let recipeContract = try String(contentsOf: repository.appending(path: "docs/chatgpt/RECIPE-CONTRACT.md"), encoding: .utf8)
    let projectInstructions = try String(contentsOf: repository.appending(path: "docs/chatgpt/PROJECT-INSTRUCTIONS.md"), encoding: .utf8)

    #expect(recipeContract.trimmingCharacters(in: .newlines) == RecipeJSONLDContract.projectSource)
    #expect(projectInstructions.trimmingCharacters(in: .newlines) == AIHandoffReturnContract.projectInstructions)
  }
}
