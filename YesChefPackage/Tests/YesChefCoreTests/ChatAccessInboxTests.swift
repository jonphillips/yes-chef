import Foundation
import Testing
import YesChefCore

struct ChatAccessInboxTests {
  @Test func rowsParseBothTimestampFormsSkipBadNamesAndSortNewestFirst() {
    let root = URL(fileURLWithPath: "/tmp/MCP/Inbox", isDirectory: true)
    let snapshots = [
      ChatAccessInbox.MetadataSnapshot(
        url: root.appending(path: "20261022T180000Z-soup.json"), name: "20261022T180000Z-soup.json", isCurrent: false
      ),
      ChatAccessInbox.MetadataSnapshot(
        url: root.appending(path: "2026-10-22T19:00:00Z-stew.json"), name: "2026-10-22T19:00:00Z-stew.json", isCurrent: true
      ),
      ChatAccessInbox.MetadataSnapshot(url: root.appending(path: "malformed.json"), name: "malformed.json", isCurrent: true),
      ChatAccessInbox.MetadataSnapshot(url: root.appending(path: "Processed"), name: "Processed", isCurrent: true),
    ]

    let rows = ChatAccessInbox.rows(from: snapshots)
    #expect(rows.map(\.name) == ["Stew", "Soup"])
    #expect(rows.last?.downloadState == .downloading)
  }

  @Test func expirationUsesStagingDateAndFallsBackToModificationDate() {
    let root = URL(fileURLWithPath: "/tmp/MCP/Inbox/Processed", isDirectory: true)
    let now = ISO8601DateFormatter().date(from: "2027-02-15T08:00:00Z")!
    let expiredDate = now.addingTimeInterval(-ChatAccessInbox.processedRetentionInterval - 1)
    let recentDate = now.addingTimeInterval(-ChatAccessInbox.processedRetentionInterval + 1)
    let fromName = root.appending(path: "20270115T080000Z-old.json")
    let fallback = root.appending(path: "unparseable.json")
    let recent = root.appending(path: "20270117T080000Z-recent.json")
    let snapshots = [
      ChatAccessInbox.ProcessedSnapshot(url: fromName, modifiedAt: recentDate),
      ChatAccessInbox.ProcessedSnapshot(url: fallback, modifiedAt: expiredDate),
      ChatAccessInbox.ProcessedSnapshot(url: recent, modifiedAt: expiredDate),
    ]

    #expect(ChatAccessInbox.expired(snapshots, now: now) == [fromName, fallback])
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
    #expect(ChatAccessServerInstructions.text.contains("If a tool call fails or times out"))
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
