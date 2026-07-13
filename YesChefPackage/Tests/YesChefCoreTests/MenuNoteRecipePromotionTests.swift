import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuNoteRecipePromotionTests {
    @Test
    func extractsAnExplicitlySectionedMenuNoteIntoAReviewDraft() throws {
      let now = Date(timeIntervalSinceReferenceDate: 807_100_000)
      let menuItem = MenuItem(
        id: SampleUUIDSequence.uuid(40_001),
        menuID: SampleUUIDSequence.uuid(40_002),
        kind: .note,
        title: "Chile-Lime Cauliflower",
        dayOffset: 1,
        mealSlot: .dinner,
        notes: """
          A bright side dish for taco night.

          Ingredients:
          - 1 head cauliflower
          - 2 tablespoons olive oil
          - 1 lime

          Method:
          1. Roast the cauliflower until browned.
          2. Finish with lime.
          """,
        sortOrder: 0,
        dateCreated: now,
        dateModified: now
      )

      let promotion = try #require(MenuNoteRecipePromotion(menuItem: menuItem))

      expectNoDifference(
        promotion.draftRecipe,
        WorkbenchDraftRecipe(
          title: "Chile-Lime Cauliflower",
          ingredientLines: ["1 head cauliflower", "2 tablespoons olive oil", "1 lime"],
          instructionLines: ["Roast the cauliflower until browned.", "Finish with lime."],
          notes: ["A bright side dish for taco night."],
          rationale: "Promoted from a menu note."
        )
      )
      let editorDraft = promotion.editorDraft(for: promotion.draftRecipe)
      expectNoDifference(editorDraft.sourceName, "")
      expectNoDifference(editorDraft.sourceNotes, "")
      #expect(editorDraft.noteText.contains("From menu note \"Chile-Lime Cauliflower\":"))
      #expect(editorDraft.noteText.contains("1 head cauliflower"))
    }

    @Test
    func committingThenReplacingPreservesTheMenuPositionAndNoteProse() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 807_200_000)
      var uuids = SampleUUIDSequence(start: 40_100)

      try database.write { db in
        let menuID = try MenuRepository.addMenu(
          title: "Taco Night",
          notes: nil,
          dayCount: 3,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let noteItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Chile-Lime Cauliflower",
          notes: """
            Ingredients:
            1 head cauliflower

            Instructions:
            1. Roast until browned.
            """,
          dayOffset: 2,
          mealSlot: .lunch,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let noteItem = try #require(try MenuItem.find(noteItemID).fetchOne(db))
        let promotion = try #require(MenuNoteRecipePromotion(menuItem: noteItem))
        let recipeID = try RecipeRepository.save(
          draft: promotion.editorDraft(for: promotion.draftRecipe),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        try MenuRepository.replaceNoteItemWithRecipe(
          itemID: noteItemID,
          recipeID: recipeID,
          in: db,
          now: now.addingTimeInterval(60)
        )

        let replacedItem = try #require(try MenuItem.find(noteItemID).fetchOne(db))
        let recipeNotes = try RecipeNote.where { $0.recipeID.eq(recipeID) }.fetchAll(db)

        expectNoDifference(replacedItem.kind, .recipe)
        expectNoDifference(replacedItem.recipeID, recipeID)
        expectNoDifference(replacedItem.dayOffset, 2)
        expectNoDifference(replacedItem.mealSlot, .lunch)
        expectNoDifference(replacedItem.notes, nil)
        expectNoDifference(replacedItem.sortOrder, noteItem.sortOrder)
        #expect(recipeNotes.contains { $0.text.contains("Roast until browned.") })
      }
    }
  }
}
