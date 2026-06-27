import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryIngredientParsingTests {
    @Test
    func generatesGroceriesFromUnitlessIngredientItems() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_210_000)
      let recipeID = SampleUUIDSequence.uuid(14_101)
      let sectionID = SampleUUIDSequence.uuid(14_102)
      var lineUUIDs = SampleUUIDSequence(start: 14_103)
      var uuids = SampleUUIDSequence(start: 14_200)
      let lines = IngredientParser.lines(
        from: """
        4 anchovy fillets, minced
        1/2 red onion, thinly sliced
        2 celery ribs, sliced
        """,
        recipeID: recipeID,
        sectionID: sectionID,
        uuid: { lineUUIDs.next() }
      )

      try database.write { db in
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try insertIngredientParsingRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Pantry Pasta",
          lines: lines,
          now: now,
          in: db
        )

        let itemIDs = try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let rows = try GroceryItemListRequest().fetch(db)
          .filter { itemIDs.contains($0.id) }

        expectNoDifference(rows.map(\.item.title), ["anchovies", "red onion", "celery ribs"])
        expectNoDifference(rows.map(\.item.quantityText), ["4", "1/2", "2"])
        expectNoDifference(rows.map(\.item.unit), [nil, nil, nil])
        expectNoDifference(rows.map(\.item.notes), ["minced", "thinly sliced", "sliced"])
      }
    }
  }
}

private func insertIngredientParsingRecipeFixture(
  recipeID: Recipe.ID,
  sectionID: IngredientSection.ID,
  title: String,
  lines: [IngredientLine],
  now: Date,
  in db: Database
) throws {
  try Recipe.insert {
    Recipe(
      id: recipeID,
      title: title,
      dateCreated: now,
      dateModified: now
    )
  }
  .execute(db)
  try IngredientSection.insert {
    IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)
  }
  .execute(db)
  for line in lines {
    try IngredientLine.insert { line }.execute(db)
  }
}
