import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct RecipeTextMarkupTests {
  @Test
  func ingredientParserKeepsBracketedAuthorNotesOutOfParsedFields() {
    let recipeID = SampleUUIDSequence.uuid(1)
    let sectionID = SampleUUIDSequence.uuid(2)
    let originalText = "2 tablespoons olive oil [not extra virgin], divided"

    let line = IngredientParser.lines(
      from: originalText,
      recipeID: recipeID,
      sectionID: sectionID,
      uuid: { SampleUUIDSequence.uuid(3) }
    )[0]

    expectNoDifference(line.originalText, originalText)
    expectNoDifference(line.quantity, 2)
    expectNoDifference(line.unit, "tablespoons")
    expectNoDifference(line.item, "olive oil")
    expectNoDifference(line.preparation, "divided")
    expectNoDifference(line.comment, "not extra virgin")
  }

  @Test
  func recipeProseMarkdownRoundTripsWithoutChangingStructuredRows() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 0)
    var uuids = SampleUUIDSequence(start: 4)
    let summary = "**Silky** with *just enough* heat."
    let note = "Use a **chilled** bowl."
    let makeAhead = "*One day ahead:* prepare the sauce."
    let chefItUp = "Finish with **extra lime zest**."
    let ingredient = "1 cup **flour**"
    let instruction = "Whisk *until smooth*."

    try database.write { db in
      let recipeID = try RecipeRepository.save(
        draft: RecipeEditorDraft(
          title: "Markdown Soup",
          summary: summary,
          makeAhead: makeAhead,
          chefItUp: chefItUp,
          ingredientText: ingredient,
          instructionText: instruction,
          noteText: note
        ),
        in: db,
        now: now,
        uuid: { uuids.next() }
      )

      let saved = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
      expectNoDifference(saved.recipe.summary, summary)
      expectNoDifference(saved.recipe.makeAhead, makeAhead)
      expectNoDifference(saved.recipe.chefItUp, chefItUp)
      expectNoDifference(saved.notes.map(\.text), [note])
      expectNoDifference(saved.ingredientLines.map(\.originalText), [ingredient])
      expectNoDifference(saved.instructionSteps.map(\.text), [instruction])

      _ = try RecipeRepository.save(
        draft: RecipeEditorDraft(detail: saved),
        in: db,
        now: now,
        uuid: { uuids.next() }
      )

      let roundTripped = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
      expectNoDifference(roundTripped.recipe.summary, summary)
      expectNoDifference(roundTripped.recipe.makeAhead, makeAhead)
      expectNoDifference(roundTripped.recipe.chefItUp, chefItUp)
      expectNoDifference(roundTripped.notes.map(\.text), [note])
      expectNoDifference(roundTripped.ingredientLines.map(\.originalText), [ingredient])
      expectNoDifference(roundTripped.instructionSteps.map(\.text), [instruction])
    }
  }
}
