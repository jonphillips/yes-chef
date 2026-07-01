import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeEditorialProseTests {
    @Test
    func atkEditorialProseBlocksBecomeLabeledNotesWithoutClobberingSummary() throws {
      let page = WebRecipePageParser.parse(
        html: try fixtureHTML("atk-rendered"),
        sourceURL: URL(string: "https://www.americastestkitchen.com/recipes/4737-perfect-chocolate-chip-cookies"),
        capturedAt: Date(timeIntervalSinceReferenceDate: 804_400_000)
      )

      expectNoDifference(
        page.summary,
        "Uncover the secrets to the perfect chocolate chip cookie: crisp edges, gooey center, and a deep, rich flavor that will leave everyone asking for more."
      )
      expectNoDifference(page.editorialBlocks.map(\.label), ["Why This Recipe Works", "Before You Begin"])
      expectNoDifference(
        page.editorialBlocks.map { $0.text.contains("Melting the butter gave us the chewiness") },
        [true, false]
      )
      expectNoDifference(
        page.editorialBlocks.map { $0.text.contains("Avoid using a nonstick skillet to brown the butter") },
        [false, true]
      )

      var uuids = SampleUUIDSequence(start: 28_000)
      let bundle = try page.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 804_500_000),
        uuid: { uuids.next() }
      )

      expectNoDifference(bundle.recipe.summary, page.summary)
      expectNoDifference(bundle.recipeNotes.map(\.noteType), [.general, .general])
      expectNoDifference(
        bundle.notes.map { $0.hasPrefix("Why This Recipe Works\n\n") },
        [true, false]
      )
      expectNoDifference(
        bundle.notes.map { $0.hasPrefix("Before You Begin\n\n") },
        [false, true]
      )

      let snapshotData = try #require(bundle.recipe.originalSnapshot)
      let snapshot = try RecipeBundleCoding.decodeSnapshot(snapshotData)
      expectNoDifference(snapshot.notes, bundle.notes)
    }

    @Test
    func editedEditorialBlocksTrimAndDropEmptyNotesInBundle() throws {
      var page = ParsedRecipePage(
        title: "Curated Cookies",
        ingredientSections: [ParsedRecipeIngredientSection(lines: ["1 cup flour"])],
        instructionSections: [ParsedRecipeInstructionSection(steps: ["Bake."])],
        editorialBlocks: [
          ParsedRecipeEditorialBlock(label: "Why This Recipe Works", text: "Original text."),
          ParsedRecipeEditorialBlock(label: "Before You Begin", text: "Read me."),
        ]
      )
      page.editorialBlocks[0].text = "  Trimmed note.  "
      page.editorialBlocks[1].text = "   "

      var uuids = SampleUUIDSequence(start: 29_000)
      let bundle = try page.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 804_600_000),
        uuid: { uuids.next() }
      )

      expectNoDifference(bundle.notes, ["Why This Recipe Works\n\nTrimmed note."])

      let snapshotData = try #require(bundle.recipe.originalSnapshot)
      let snapshot = try RecipeBundleCoding.decodeSnapshot(snapshotData)
      expectNoDifference(snapshot.notes, bundle.notes)
    }

    private func fixtureHTML(_ name: String) throws -> String {
      try String(contentsOf: fixtureURL.appendingPathComponent("\(name).html"), encoding: .utf8)
    }

    private var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/WebRecipeCapture/SanitizedSites", isDirectory: true)
    }
  }
}
