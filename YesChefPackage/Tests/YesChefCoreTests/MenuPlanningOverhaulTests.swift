import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuPlanningOverhaulTests {
    @Test
    func menuChatContextClipsMakeAheadBeforeDroppingDishes() {
      let menuID = SampleUUIDSequence.uuid(14_500)
      let now = Date(timeIntervalSinceReferenceDate: 805_250_000)
      let rows = (0..<4).map { index in
        let recipeID = SampleUUIDSequence.uuid(14_600 + index)
        return MenuItemRowData(
          item: MenuItem(
            id: SampleUUIDSequence.uuid(14_700 + index),
            menuID: menuID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Dish \(index)",
            dayOffset: index % 2,
            mealSlot: .dinner,
            sortOrder: index,
            dateCreated: now,
            dateModified: now
          ),
          recipe: Recipe(
            id: recipeID,
            title: "Dish \(index)",
            dateCreated: now,
            dateModified: now,
            makeAhead: String(repeating: "Long make-ahead note \(index). ", count: 80)
          ),
          recipeIngredientLines: ["ingredient \(index)"]
        )
      }
      let context = MenuChatContext(
        detail: MenuDetailData(
          menu: Menu(
            id: menuID,
            title: "Large Prep Menu",
            dayCount: 2,
            dateCreated: now,
            dateModified: now
          ),
          itemRows: rows
        )
      )

      let serialized = context.serialized(characterBudget: 2_800)

      #expect(serialized.count <= 2_800)
      #expect(serialized.contains("Recipe make-ahead notes are capped"))
      #expect(!serialized.contains("lower-priority menu item(s) were omitted"))
      for index in 0..<4 {
        #expect(serialized.contains("- Dish \(index)"))
      }
    }

    @Test
    func menuChatContextUsesLargerFrontierBudget() {
      expectNoDifference(MenuChatContext.serializedCharacterBudget(for: .onDevice), 12_000)
      expectNoDifference(
        MenuChatContext.serializedCharacterBudget(for: .frontier(.anthropic)),
        120_000
      )
      expectNoDifference(
        MenuChatContext.serializedCharacterBudget(for: .frontierPreferred),
        120_000
      )
    }

    @Test
    func updatesMenuItemsAndDayCountWithoutDeletingRows() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 805_500_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_600_000)
      let recipeID = SampleUUIDSequence.uuid(12_300)
      var uuids = SampleUUIDSequence(start: 12_400)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Edited Recipe Dish",
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)

        let menuID = try MenuRepository.addMenu(
          title: "Edit Menu",
          notes: nil,
          dayCount: 3,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )
        let noteItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Original note",
          notes: nil,
          dayOffset: 2,
          mealSlot: .lunch,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )
        let recipeItemID = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .breakfast,
          notes: nil,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )

        try MenuRepository.updateNoteItem(
          itemID: noteItemID,
          title: "Edited note",
          notes: "Pack leftovers.",
          dayOffset: 1,
          mealSlot: .dinner,
          in: db,
          now: modifiedAt
        )
        try MenuRepository.updateRecipeItem(
          itemID: recipeItemID,
          recipeID: recipeID,
          dayOffset: 1,
          mealSlot: .lunch,
          notes: "Serve warm.",
          in: db,
          now: modifiedAt
        )
        try MenuRepository.updateMenuDayCount(
          menuID: menuID,
          dayCount: 2,
          in: db,
          now: modifiedAt
        )

        let detail = try #require(try MenuDetailRequest(menuID: menuID).fetch(db))
        expectNoDifference(detail.menu.dayCount, 2)
        expectNoDifference(detail.itemRows.map(\.id), [recipeItemID, noteItemID])
        expectNoDifference(detail.itemRows.map(\.item.dateCreated), [createdAt, createdAt])
        expectNoDifference(detail.itemRows.map(\.item.dateModified), [modifiedAt, modifiedAt])
        expectNoDifference(detail.itemRows.map(\.displayTitle), ["Edited Recipe Dish", "Edited note"])
        expectNoDifference(detail.itemRows.map(\.item.dayOffset), [1, 1])
        expectNoDifference(detail.itemRows.map(\.item.mealSlot), [.lunch, .dinner])
        expectNoDifference(detail.itemRows.map(\.item.notes), ["Serve warm.", "Pack leftovers."])
      }
    }

    @Test
    func deletesMenuItemsAndMenus() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_700_000)
      var uuids = SampleUUIDSequence(start: 12_500)

      try database.write { db in
        let menuID = try MenuRepository.addMenu(
          title: "Delete Menu",
          notes: nil,
          dayCount: 1,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let itemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Delete me",
          notes: nil,
          dayOffset: 0,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        _ = try MenuRepository.placeMenu(
          menuID: menuID,
          startDate: now,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        try MenuRepository.deleteItem(itemID: itemID, in: db)
        expectNoDifference(try MenuDetailRequest(menuID: menuID).fetch(db)?.itemRows, [])

        try MenuRepository.deleteMenu(menuID: menuID, in: db)
        expectNoDifference(try Menu.find(menuID).fetchOne(db), nil)
        expectNoDifference(try MenuItem.fetchAll(db).contains { $0.menuID == menuID }, false)
        expectNoDifference(try MenuPlacement.fetchAll(db).contains { $0.menuID == menuID }, false)
      }
    }
  }
}
