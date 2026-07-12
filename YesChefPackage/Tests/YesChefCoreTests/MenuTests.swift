import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuTests {
    @Test
    func createsMenuItemsAndPlacements() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 804_100_000)
      let startDate = Date(timeIntervalSinceReferenceDate: 804_200_000)
      let recipeID = SampleUUIDSequence.uuid(9_001)
      let ingredientSectionID = SampleUUIDSequence.uuid(9_002)
      let prepInstructionSectionID = SampleUUIDSequence.uuid(9_005)
      let cookInstructionSectionID = SampleUUIDSequence.uuid(9_006)
      let thumbnailData = Data([1])
      var uuids = SampleUUIDSequence(start: 9_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Menu Chicken",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        for section in [
          InstructionSection(
            id: prepInstructionSectionID,
            recipeID: recipeID,
            name: "Prep",
            sortOrder: 0
          ),
          InstructionSection(
            id: cookInstructionSectionID,
            recipeID: recipeID,
            name: "Cook",
            sortOrder: 1
          ),
        ] {
          try InstructionSection.insert { section }.execute(db)
        }
        for step in [
          InstructionStep(
            id: SampleUUIDSequence.uuid(9_007),
            recipeID: recipeID,
            sectionID: prepInstructionSectionID,
            text: "Salt the chicken overnight.",
            sortOrder: 0
          ),
          InstructionStep(
            id: SampleUUIDSequence.uuid(9_009),
            recipeID: recipeID,
            sectionID: cookInstructionSectionID,
            text: "Grill over medium heat.",
            sortOrder: 1
          ),
          InstructionStep(
            id: SampleUUIDSequence.uuid(9_008),
            recipeID: recipeID,
            sectionID: cookInstructionSectionID,
            text: "Rest before slicing.",
            sortOrder: 0
          ),
        ] {
          try InstructionStep.insert { step }.execute(db)
        }
        try RecipePhoto.insert {
          RecipePhoto(
            id: SampleUUIDSequence.uuid(9_004),
            recipeID: recipeID,
            imageDataReference: "recipePhotos/menu-chicken",
            thumbnailData: thumbnailData,
            kind: .hero,
            sortOrder: 0,
            dateCreated: now
          )
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(
            id: ingredientSectionID,
            recipeID: recipeID,
            name: nil,
            sortOrder: 0
          )
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: SampleUUIDSequence.uuid(9_003),
            recipeID: recipeID,
            sectionID: ingredientSectionID,
            originalText: "1 chicken",
            sortOrder: 0
          )
        }
        .execute(db)

        let menuID = try MenuRepository.addMenu(
          title: " Weekend Menu ",
          notes: "  Guests on Saturday  ",
          dayCount: 2,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let recipeItemID = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .dinner,
          notes: "  Grill outside  ",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let noteItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "  Leftover lunch  ",
          notes: "  Use extra chicken  ",
          dayOffset: 1,
          mealSlot: .lunch,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let placementID = try MenuRepository.placeMenu(
          menuID: menuID,
          startDate: startDate,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let detail = try #require(try MenuDetailRequest(menuID: menuID).fetch(db))
        expectNoDifference(detail.menu.title, "Weekend Menu")
        expectNoDifference(detail.menu.notes, "Guests on Saturday")
        expectNoDifference(detail.menu.dayCount, 2)
        expectNoDifference(detail.itemRows.map(\.id), [recipeItemID, noteItemID])
        expectNoDifference(detail.itemRows.map(\.displayTitle), ["Menu Chicken", "Leftover lunch"])
        expectNoDifference(detail.itemRows.map(\.item.notes), ["Grill outside", "Use extra chicken"])
        expectNoDifference(detail.itemRows[0].recipeIngredientLines, ["1 chicken"])
        expectNoDifference(
          detail.itemRows[0].recipeMethodLines,
          [
            "Prep:",
            "1. Salt the chicken overnight.",
            "Cook:",
            "1. Rest before slicing.",
            "2. Grill over medium heat.",
          ]
        )
        expectNoDifference(detail.itemRows[1].recipeIngredientLines, [])
        expectNoDifference(detail.itemRows.map(\.thumbnailData), [thumbnailData, nil])
        expectNoDifference(detail.placements.map(\.id), [placementID])
      }
    }

  }

  @Suite
  struct MenuChatContextTests {
    @Test
    func menuChatContextSerializesDishSummariesAndMakeAhead() throws {
      let menuID = SampleUUIDSequence.uuid(13_000)
      let recipeID = SampleUUIDSequence.uuid(13_001)
      let itemID = SampleUUIDSequence.uuid(13_002)
      let prepSourceID = SampleUUIDSequence.uuid(13_003)
      let now = Date(timeIntervalSinceReferenceDate: 805_100_000)
      let detail = MenuDetailData(
        menu: Menu(
          id: menuID,
          title: "Birthday Menu",
          notes: "Mostly grill outside.",
          dayCount: 2,
          prepPlan: try MenuPrepPlanCoding.encode([
            PrepPlanStep(
              session: "Day before",
              task: "Marinate the chicken.",
              sourceDish: prepSourceID
            )
          ]),
          dateCreated: now,
          dateModified: now
        ),
        itemRows: [
          MenuItemRowData(
            item: MenuItem(
              id: itemID,
              menuID: menuID,
              kind: .recipe,
              recipeID: recipeID,
              title: "Soy Chicken",
              dayOffset: 1,
              mealSlot: .dinner,
              notes: "Serve sliced.",
              sortOrder: 0,
              dateCreated: now,
              dateModified: now
            ),
            recipe: Recipe(
              id: recipeID,
              title: "Soy Chicken",
              prepTimeMinutes: 20,
              cookTimeMinutes: 45,
              totalTimeMinutes: 65,
              dateCreated: now,
              dateModified: now,
              makeAhead: "Marinate the chicken overnight.\nBring to room temperature before grilling."
            ),
            recipeIngredientLines: [
              "2 pounds chicken thighs",
              "1/2 cup soy sauce",
              "4 cloves garlic"
            ],
            recipeMethodLines: [
              "Marinate:",
              "1. Whisk the soy marinade.",
              "Cook:",
              "1. Grill the chicken until browned.",
            ]
          )
        ]
      )

      let serialized = MenuChatContext(detail: detail).serialized(for: .frontierPreferred)

      #expect(serialized.contains("- Title: Birthday Menu"))
      #expect(serialized.contains("Current prep plan:"))
      #expect(serialized.contains("- Day before: Marinate the chicken."))
      #expect(serialized.contains("  - Source menu item ID: \(prepSourceID.uuidString)"))
      #expect(serialized.contains("- Menu item ID: \(itemID.uuidString)"))
      #expect(serialized.contains("- Day: 2 (dayOffset 1)"))
      #expect(serialized.contains("- Meal slot: Dinner"))
      #expect(serialized.contains("- Prep time: 20 minutes"))
      #expect(serialized.contains("    - 2 pounds chicken thighs"))
      #expect(serialized.contains("- Menu item notes: Serve sliced."))
      #expect(
        serialized.contains(
          "Existing recipe make-ahead note, verbatim:\n"
            + "Marinate the chicken overnight.\n"
            + "Bring to room temperature before grilling."
        )
      )
      #expect(
        serialized.contains(
          "  - Method:\n"
            + "    - Marinate:\n"
            + "    - 1. Whisk the soy marinade.\n"
            + "    - Cook:\n"
            + "    - 1. Grill the chicken until browned."
        )
      )
    }

    @Test
    func menuChatContextNotesBudgetTruncation() {
      let menuID = SampleUUIDSequence.uuid(14_000)
      let now = Date(timeIntervalSinceReferenceDate: 805_200_000)
      let rows = (0..<10).map { index in
        let recipeID = SampleUUIDSequence.uuid(14_100 + index)
        return MenuItemRowData(
          item: MenuItem(
            id: SampleUUIDSequence.uuid(14_200 + index),
            menuID: menuID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Dish \(index)",
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: index,
            dateCreated: now,
            dateModified: now
          ),
          recipe: Recipe(
            id: recipeID,
            title: "Dish \(index)",
            dateCreated: now,
            dateModified: now
          ),
          recipeIngredientLines: [
            "long ingredient \(index)-0 with enough words to matter",
            "long ingredient \(index)-1 with enough words to matter",
            "long ingredient \(index)-2 with enough words to matter",
            "long ingredient \(index)-3 with enough words to matter"
          ]
        )
      }
      let context = MenuChatContext(
        detail: MenuDetailData(
          menu: Menu(
            id: menuID,
            title: "Oversized Menu",
            dayCount: 1,
            dateCreated: now,
            dateModified: now
          ),
          itemRows: rows
        )
      )

      let serialized = context.serialized(characterBudget: 900)

      #expect(serialized.count <= 900)
      #expect(serialized.contains("Ingredient lists were omitted to stay within the context budget."))
      #expect(
        serialized.contains("lower-priority menu item(s) were omitted to stay within the context budget.")
      )
      #expect(serialized.contains("- Dish 0"))
      #expect(!serialized.contains("- Dish 9"))
    }

    @Test
    func projectsPlacedMenusOntoCalendar() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 804_300_000)
      let startDate = Date(timeIntervalSinceReferenceDate: 804_400_000)
      let secondDate = try #require(
        Calendar(identifier: .gregorian)
          .date(byAdding: .day, value: 1, to: startDate)
      )
      let recipeID = SampleUUIDSequence.uuid(10_001)
      var uuids = SampleUUIDSequence(start: 10_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Calendar Menu Chicken",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let menuID = try MenuRepository.addMenu(
          title: "Two Day Menu",
          notes: nil,
          dayCount: 2,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let recipeItemID = try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: 0,
          mealSlot: .dinner,
          notes: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let noteItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Brunch note",
          notes: "Make coffee cake.",
          dayOffset: 1,
          mealSlot: .breakfast,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let placementID = try MenuRepository.placeMenu(
          menuID: menuID,
          startDate: startDate,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let rows = try MealCalendarRequest().fetch(db)
          .filter { $0.menuPlacement?.id == placementID }

        expectNoDifference(rows.map(\.id), [
          .menu(placementID: placementID, itemID: recipeItemID),
          .menu(placementID: placementID, itemID: noteItemID),
        ])
        expectNoDifference(rows.map(\.displayTitle), ["Calendar Menu Chicken", "Brunch note"])
        expectNoDifference(rows.map(\.item.scheduledDate), [startDate, secondDate])
        expectNoDifference(rows.map(\.item.mealSlot), [.dinner, .breakfast])
        expectNoDifference(rows.map(\.isFromMenu), [true, true])
        expectNoDifference(rows.map(\.menu?.title), ["Two Day Menu", "Two Day Menu"])
      }
    }

    @Test
    func updatesAndDeletesMenuPlacements() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 804_550_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 804_650_000)
      let originalStartDate = Date(timeIntervalSinceReferenceDate: 804_750_000)
      let movedStartDate = Date(timeIntervalSinceReferenceDate: 804_850_000)
      let secondMovedDate = try #require(
        Calendar(identifier: .gregorian)
          .date(byAdding: .day, value: 1, to: movedStartDate)
      )
      var uuids = SampleUUIDSequence(start: 12_100)

      try database.write { db in
        let menuID = try MenuRepository.addMenu(
          title: "Placement Menu",
          notes: nil,
          dayCount: 2,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )
        let firstItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "First dinner",
          notes: nil,
          dayOffset: 0,
          mealSlot: .dinner,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )
        let secondItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Second lunch",
          notes: nil,
          dayOffset: 1,
          mealSlot: .lunch,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )
        let placementID = try MenuRepository.placeMenu(
          menuID: menuID,
          startDate: originalStartDate,
          in: db,
          now: createdAt,
          uuid: { uuids.next() }
        )

        try MenuRepository.updateMenuPlacement(
          placementID: placementID,
          startDate: movedStartDate,
          in: db,
          now: modifiedAt
        )

        let movedRows = try MealCalendarRequest().fetch(db)
          .filter { $0.menuPlacement?.id == placementID }

        expectNoDifference(movedRows.map(\.id), [
          .menu(placementID: placementID, itemID: firstItemID),
          .menu(placementID: placementID, itemID: secondItemID),
        ])
        expectNoDifference(movedRows.map(\.item.scheduledDate), [movedStartDate, secondMovedDate])
        expectNoDifference(
          movedRows.map(\.menuPlacement?.dateModified),
          [modifiedAt, modifiedAt].map(Optional.some)
        )

        try MenuRepository.deleteMenuPlacement(
          placementID: placementID,
          in: db
        )

        let detailAfterDelete = try #require(try MenuDetailRequest(menuID: menuID).fetch(db))
        expectNoDifference(detailAfterDelete.placements, [])
        expectNoDifference(
          try MealCalendarRequest().fetch(db).contains { $0.menuPlacement?.id == placementID },
          false
        )
      }
    }

    @Test
    func movesMenuItemsBetweenDays() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 804_900_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 805_000_000)

      try database.write { db in
        let menuID = try MenuRepository.addMenu(
          title: "Move Menu",
          notes: nil,
          dayCount: 3,
          in: db,
          now: createdAt,
          uuid: { SampleUUIDSequence.uuid(12_200) }
        )
        _ = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Existing dinner",
          notes: nil,
          dayOffset: 2,
          mealSlot: .dinner,
          in: db,
          now: createdAt,
          uuid: { SampleUUIDSequence.uuid(12_201) }
        )
        let movedItemID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Move me",
          notes: nil,
          dayOffset: 0,
          mealSlot: .dinner,
          in: db,
          now: createdAt,
          uuid: { SampleUUIDSequence.uuid(12_202) }
        )

        try MenuRepository.moveItem(
          itemID: movedItemID,
          toDayOffset: 2,
          in: db,
          now: modifiedAt
        )

        let movedRow = try #require(
          try MenuDetailRequest(menuID: menuID).fetch(db)?.itemRows.first { $0.id == movedItemID }
        )
        expectNoDifference(movedRow.item.dayOffset, 2)
        expectNoDifference(movedRow.item.mealSlot, .dinner)
        expectNoDifference(movedRow.item.sortOrder, 1)
        expectNoDifference(movedRow.item.dateCreated, createdAt)
        expectNoDifference(movedRow.item.dateModified, modifiedAt)
      }
    }

    @Test
    func rejectsInvalidMenus() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 804_500_000)

      try database.write { db in
        do {
          _ = try MenuRepository.addMenu(
            title: " ",
            notes: nil,
            dayCount: 1,
            in: db,
            now: now,
            uuid: { SampleUUIDSequence.uuid(11_001) }
          )
          #expect(Bool(false), "Expected empty menu title to be rejected.")
        } catch let error as MenuRepositoryError {
          expectNoDifference(error, .emptyTitle)
        }

        do {
          _ = try MenuRepository.addMenu(
            title: "Broken Menu",
            notes: nil,
            dayCount: 0,
            in: db,
            now: now,
            uuid: { SampleUUIDSequence.uuid(11_002) }
          )
          #expect(Bool(false), "Expected invalid menu length to be rejected.")
        } catch let error as MenuRepositoryError {
          expectNoDifference(error, .invalidDayCount)
        }

        do {
          _ = try MenuRepository.addNoteItem(
            menuID: SampleUUIDSequence.uuid(11_003),
            title: "Missing menu",
            notes: nil,
            dayOffset: 0,
            mealSlot: .dinner,
            in: db,
            now: now,
            uuid: { SampleUUIDSequence.uuid(11_004) }
          )
          #expect(Bool(false), "Expected missing menu to be rejected.")
        } catch let error as MenuRepositoryError {
          expectNoDifference(error, .menuNotFound(SampleUUIDSequence.uuid(11_003)))
        }

        do {
          try MenuRepository.updateMenuPlacement(
            placementID: SampleUUIDSequence.uuid(11_005),
            startDate: now,
            in: db,
            now: now
          )
          #expect(Bool(false), "Expected missing placement to be rejected.")
        } catch let error as MenuRepositoryError {
          expectNoDifference(error, .placementNotFound(SampleUUIDSequence.uuid(11_005)))
        }

        do {
          try MenuRepository.moveItem(
            itemID: SampleUUIDSequence.uuid(11_006),
            toDayOffset: 0,
            in: db,
            now: now
          )
          #expect(Bool(false), "Expected missing menu item to be rejected.")
        } catch let error as MenuRepositoryError {
          expectNoDifference(error, .menuItemNotFound(SampleUUIDSequence.uuid(11_006)))
        }
      }
    }
  }
}
