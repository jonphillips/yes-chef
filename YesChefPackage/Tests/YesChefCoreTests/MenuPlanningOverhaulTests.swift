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
    func menuChatContextDropsMethodsBeforeOtherDishDetailsAtOnDeviceBudget() {
      let menuID = SampleUUIDSequence.uuid(14_800)
      let now = Date(timeIntervalSinceReferenceDate: 805_260_000)
      let rows = (0..<4).map { index in
        let recipeID = SampleUUIDSequence.uuid(14_900 + index)
        return MenuItemRowData(
          item: MenuItem(
            id: SampleUUIDSequence.uuid(15_000 + index),
            menuID: menuID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Dish \(index)",
            dayOffset: index,
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
            makeAhead: "Make-ahead note \(index)."
          ),
          recipeIngredientLines: ["ingredient \(index)"],
          recipeMethodLines: [
            "1. \(String(repeating: "Method step \(index). ", count: 250))"
          ]
        )
      }
      let context = MenuChatContext(
        detail: MenuDetailData(
          menu: Menu(
            id: menuID,
            title: "Large Method Menu",
            dayCount: 4,
            dateCreated: now,
            dateModified: now
          ),
          itemRows: rows
        )
      )

      let serialized = context.serialized()

      #expect(serialized.count <= MenuChatContext.onDeviceSerializedCharacterBudget)
      #expect(
        serialized.contains(
          "Recipe methods were omitted before other dish details to stay within the context budget."
        )
      )
      #expect(!serialized.contains("Method step 0."))
      for index in 0..<4 {
        #expect(serialized.contains("- Dish \(index)"))
        #expect(serialized.contains("    - ingredient \(index)"))
        #expect(serialized.contains("Make-ahead note \(index)."))
      }
    }

    @Test
    func menuChatContextFrontierPromptUsesFullIngredientsAndPrepPreferences() {
      let itemID = SampleUUIDSequence.uuid(15_100)
      let context = MenuChatContext(
        title: "Saturday Dinner",
        dayCount: 1,
        items: [
          MenuChatItemContext(
            id: itemID,
            title: "Fennel Chicken",
            kind: .recipe,
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: 0,
            keyIngredients: (0..<10).map { "ingredient \($0)" },
            method: ["Prep:", "1. Salt the chicken overnight."]
          )
        ]
      )
      let settings = AISettingsRecord(
        id: AISettingsRepository.singletonID,
        tasteProfile: "Favor bright, spicy flavors.",
        makeAheadPrepPlanPreference: "Protect the resting time.",
        dateModified: .distantPast
      )

      let prompt = withDependencies {
        $0.aiPromptPreferences = AIPromptPreferencesClient { settings }
      } operation: {
        context.prepPrompt()
      }

      #expect(prompt.contains("ingredient 9"))
      #expect(prompt.contains("1. Salt the chicken overnight."))
      #expect(prompt.contains("Favor bright, spicy flavors."))
      #expect(prompt.contains("Protect the resting time."))
      #expect(prompt.contains("Wednesday evening:"))
      #expect(prompt.contains("`- task → serves` bullet"))
      #expect(!prompt.contains("strict JSON"))
      #expect(!prompt.contains("menu item UUID"))
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
