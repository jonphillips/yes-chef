import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MealCalendarTests {
    @Test
    func addsRecipeAndNoteItemsToMealCalendar() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 803_000_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 803_100_000)
      let recipeID = SampleUUIDSequence.uuid(5_001)
      let ingredientSectionID = SampleUUIDSequence.uuid(5_002)
      var uuids = SampleUUIDSequence(start: 5_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Planner Chicken",
            dateCreated: now,
            dateModified: now
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
            id: SampleUUIDSequence.uuid(5_003),
            recipeID: recipeID,
            sectionID: ingredientSectionID,
            originalText: "1 pound chicken thighs",
            sortOrder: 0
          )
        }
        .execute(db)

        let recipeItemID = try MealCalendarRepository.addRecipeItem(
          recipeID: recipeID,
          on: scheduledDate,
          mealSlot: .dinner,
          notes: "Serve with slaw",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let noteItemID = try MealCalendarRepository.addNoteItem(
          title: "Use leftovers",
          notes: "Fold into lunch bowls.",
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let rows = try MealCalendarRequest().fetch(db)
          .filter { $0.item.scheduledDate == scheduledDate }

        expectNoDifference(rows.map(\.item.id), [recipeItemID, noteItemID])
        expectNoDifference(rows.map(\.item.kind), [.recipe, .note])
        expectNoDifference(rows.map(\.displayTitle), ["Planner Chicken", "Use leftovers"])
        expectNoDifference(rows.map(\.item.sortOrder), [0, 1])
        expectNoDifference(rows.first?.recipe?.id, recipeID)
        expectNoDifference(rows.first?.recipeIngredientLines, ["1 pound chicken thighs"])
        expectNoDifference(rows.first?.item.title, "Planner Chicken")
        expectNoDifference(rows.last?.recipe, nil)
      }
    }

    @Test
    func mealPlanChatContextSerializesSelectedDaySummariesAndMakeAhead() {
      let recipeID = SampleUUIDSequence.uuid(5_401)
      let recipeItemID = SampleUUIDSequence.uuid(5_402)
      let noteItemID = SampleUUIDSequence.uuid(5_403)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 805_500_000)
      let now = Date(timeIntervalSinceReferenceDate: 805_600_000)
      let context = MealPlanChatContext(
        title: "Tuesday, July 8",
        rows: [
          MealPlanItemRowData(
            item: MealPlanItem(
              id: noteItemID,
              kind: .note,
              title: "Buy ice",
              scheduledDate: scheduledDate,
              mealSlot: .snack,
              notes: "For drinks.",
              sortOrder: 1,
              dateCreated: now,
              dateModified: now
            )
          ),
          MealPlanItemRowData(
            item: MealPlanItem(
              id: recipeItemID,
              kind: .recipe,
              recipeID: recipeID,
              title: "Soy Chicken",
              scheduledDate: scheduledDate,
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
            ]
          )
        ]
      )

      let serialized = RecipeChatContext.mealPlan(context).serialized()

      #expect(serialized.contains("- Date: Tuesday, July 8"))
      #expect(serialized.contains("- Meal plan item ID: meal:\(recipeItemID.uuidString)"))
      #expect(serialized.contains("- Kind: Recipe"))
      #expect(serialized.contains("- Meal slot: Dinner"))
      #expect(serialized.contains("- Prep time: 20 minutes"))
      #expect(serialized.contains("    - 2 pounds chicken thighs"))
      #expect(serialized.contains("- Meal plan item notes: Serve sliced."))
      #expect(serialized.contains("- Buy ice"))
      #expect(serialized.contains("- Kind: Note"))
      #expect(!serialized.contains("For drinks.\n  - Existing recipe make-ahead note"))
      #expect(
        serialized.contains(
          "Existing recipe make-ahead note, verbatim:\n"
            + "Marinate the chicken overnight.\n"
            + "Bring to room temperature before grilling."
        )
      )
    }

    @Test
    func mealPlanChatContextNotesBudgetTruncation() {
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 805_650_000)
      let now = Date(timeIntervalSinceReferenceDate: 805_660_000)
      let rows = (0..<10).map { index in
        let recipeID = SampleUUIDSequence.uuid(5_500 + index)
        return MealPlanItemRowData(
          item: MealPlanItem(
            id: SampleUUIDSequence.uuid(5_600 + index),
            kind: .recipe,
            recipeID: recipeID,
            title: "Dish \(index)",
            scheduledDate: scheduledDate,
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
      let context = MealPlanChatContext(
        title: "Tuesday, July 8",
        rows: rows
      )

      let serialized = context.serialized(characterBudget: 900)

      #expect(serialized.count <= 900)
      #expect(serialized.contains("Ingredient lists were omitted to stay within the context budget."))
      #expect(
        serialized.contains("lower-priority meal plan item(s) were omitted to stay within the context budget.")
      )
      #expect(serialized.contains("- Dish 0"))
      #expect(!serialized.contains("- Dish 9"))
    }

    @Test
    func addsMultipleRecipeItemsToMealCalendar() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 803_050_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 803_150_000)
      let firstRecipeID = SampleUUIDSequence.uuid(5_201)
      let secondRecipeID = SampleUUIDSequence.uuid(5_202)
      var uuids = SampleUUIDSequence(start: 5_300)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: firstRecipeID,
            title: "Planner Chicken",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try Recipe.insert {
          Recipe(
            id: secondRecipeID,
            title: "Rice Pilaf",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let itemIDs = try MealCalendarRepository.addRecipeItems(
          recipeIDs: [firstRecipeID, secondRecipeID],
          on: scheduledDate,
          mealSlot: .dinner,
          notes: "Company dinner",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let rows = try MealCalendarRequest().fetch(db)
          .filter { itemIDs.contains($0.item.id) }

        expectNoDifference(rows.map(\.item.id), itemIDs)
        expectNoDifference(rows.map(\.item.recipeID), [firstRecipeID, secondRecipeID].map(Optional.some))
        expectNoDifference(rows.map(\.displayTitle), ["Planner Chicken", "Rice Pilaf"])
        expectNoDifference(rows.map(\.item.notes), ["Company dinner", "Company dinner"])
        expectNoDifference(rows.map(\.item.sortOrder), [0, 1])
      }
    }

    @Test
    func updatesMealCalendarItems() throws {
      @Dependency(\.defaultDatabase) var database
      let createdAt = Date(timeIntervalSinceReferenceDate: 803_600_000)
      let modifiedAt = Date(timeIntervalSinceReferenceDate: 803_700_000)
      let secondModifiedAt = Date(timeIntervalSinceReferenceDate: 803_800_000)
      let originalDate = Date(timeIntervalSinceReferenceDate: 803_900_000)
      let movedDate = Date(timeIntervalSinceReferenceDate: 804_000_000)
      let originalRecipeID = SampleUUIDSequence.uuid(8_001)
      let updatedRecipeID = SampleUUIDSequence.uuid(8_002)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: originalRecipeID,
            title: "Original Chicken",
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)
        try Recipe.insert {
          Recipe(
            id: updatedRecipeID,
            title: "Updated Chicken",
            dateCreated: createdAt,
            dateModified: createdAt
          )
        }
        .execute(db)

        _ = try MealCalendarRepository.addNoteItem(
          title: "Existing lunch",
          notes: nil,
          on: movedDate,
          mealSlot: .lunch,
          in: db,
          now: createdAt,
          uuid: { SampleUUIDSequence.uuid(8_100) }
        )
        let itemID = try MealCalendarRepository.addRecipeItem(
          recipeID: originalRecipeID,
          on: originalDate,
          mealSlot: .dinner,
          notes: "Old notes",
          in: db,
          now: createdAt,
          uuid: { SampleUUIDSequence.uuid(8_101) }
        )

        try MealCalendarRepository.updateRecipeItem(
          itemID: itemID,
          recipeID: updatedRecipeID,
          on: movedDate,
          mealSlot: .lunch,
          notes: "  Serve with rice  ",
          in: db,
          now: modifiedAt
        )

        let recipeRow = try #require(try MealCalendarRequest().fetch(db).first { $0.item.id == itemID })
        expectNoDifference(recipeRow.item.kind, .recipe)
        expectNoDifference(recipeRow.item.recipeID, updatedRecipeID)
        expectNoDifference(recipeRow.item.title, "Updated Chicken")
        expectNoDifference(recipeRow.item.scheduledDate, movedDate)
        expectNoDifference(recipeRow.item.mealSlot, .lunch)
        expectNoDifference(recipeRow.item.notes, "Serve with rice")
        expectNoDifference(recipeRow.item.sortOrder, 1)
        expectNoDifference(recipeRow.item.dateCreated, createdAt)
        expectNoDifference(recipeRow.item.dateModified, modifiedAt)
        expectNoDifference(recipeRow.recipe?.id, updatedRecipeID)

        try MealCalendarRepository.updateNoteItem(
          itemID: itemID,
          title: "  Leftovers  ",
          notes: "   ",
          on: originalDate,
          mealSlot: .snack,
          in: db,
          now: secondModifiedAt
        )

        let noteRow = try #require(try MealCalendarRequest().fetch(db).first { $0.item.id == itemID })
        expectNoDifference(noteRow.item.kind, .note)
        expectNoDifference(noteRow.item.recipeID, nil)
        expectNoDifference(noteRow.item.title, "Leftovers")
        expectNoDifference(noteRow.item.scheduledDate, originalDate)
        expectNoDifference(noteRow.item.mealSlot, .snack)
        expectNoDifference(noteRow.item.notes, nil)
        expectNoDifference(noteRow.item.sortOrder, 0)
        expectNoDifference(noteRow.item.dateCreated, createdAt)
        expectNoDifference(noteRow.item.dateModified, secondModifiedAt)
        expectNoDifference(noteRow.recipe, nil)
      }
    }

    @Test
    func rejectsInvalidMealCalendarItems() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 803_200_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 803_300_000)

      try database.write { db in
        do {
          _ = try MealCalendarRepository.addRecipeItem(
            recipeID: SampleUUIDSequence.uuid(6_001),
            on: scheduledDate,
            mealSlot: .dinner,
            notes: nil,
            in: db,
            now: now,
            uuid: { SampleUUIDSequence.uuid(6_100) }
          )
          #expect(Bool(false), "Expected missing recipe to be rejected.")
        } catch let error as MealCalendarRepositoryError {
          expectNoDifference(error, .recipeNotFound(SampleUUIDSequence.uuid(6_001)))
        }

        do {
          _ = try MealCalendarRepository.addNoteItem(
            title: "   ",
            notes: "No title",
            on: scheduledDate,
            mealSlot: .snack,
            in: db,
            now: now,
            uuid: { SampleUUIDSequence.uuid(6_101) }
          )
          #expect(Bool(false), "Expected empty note title to be rejected.")
        } catch let error as MealCalendarRepositoryError {
          expectNoDifference(error, .emptyTitle)
        }

        do {
          try MealCalendarRepository.updateNoteItem(
            itemID: SampleUUIDSequence.uuid(6_002),
            title: "Missing",
            notes: nil,
            on: scheduledDate,
            mealSlot: .snack,
            in: db,
            now: now
          )
          #expect(Bool(false), "Expected missing meal plan item to be rejected.")
        } catch let error as MealCalendarRepositoryError {
          expectNoDifference(error, .itemNotFound(SampleUUIDSequence.uuid(6_002)))
        }
      }
    }

    @Test
    func deletesMealCalendarItems() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 803_400_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 803_500_000)

      try database.write { db in
        let itemID = try MealCalendarRepository.addNoteItem(
          title: "Freezer dinner",
          notes: nil,
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { SampleUUIDSequence.uuid(7_001) }
        )

        try MealCalendarRepository.deleteItem(itemID: itemID, in: db)

        let rows = try MealCalendarRequest().fetch(db)
        expectNoDifference(rows.contains { $0.item.id == itemID }, false)
      }
    }

    @Test
    func dayOrderOverlayInterleavesManualItemsAmongMenuRowsWithoutTouchingMenu() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 804_000_000)
      let scheduledDate = Date(timeIntervalSinceReferenceDate: 804_100_000)
      let menuID = SampleUUIDSequence.uuid(8_000)
      let placementID = SampleUUIDSequence.uuid(8_001)
      let menuItem1ID = SampleUUIDSequence.uuid(8_010)
      let menuItem2ID = SampleUUIDSequence.uuid(8_011)
      var uuids = SampleUUIDSequence(start: 8_100)

      try database.write { db in
        // Two manual dinner items.
        let manualAID = try MealCalendarRepository.addNoteItem(
          title: "Manual A",
          notes: nil,
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let manualBID = try MealCalendarRepository.addNoteItem(
          title: "Manual B",
          notes: nil,
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        // A two-item menu placed on the same day + slot.
        try Menu.insert {
          Menu(id: menuID, title: "Dinner Menu", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try MenuItem.insert {
          MenuItem(
            id: menuItem1ID,
            menuID: menuID,
            kind: .note,
            title: "Menu 1",
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
          MenuItem(
            id: menuItem2ID,
            menuID: menuID,
            kind: .note,
            title: "Menu 2",
            dayOffset: 0,
            mealSlot: .dinner,
            sortOrder: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try MenuPlacement.insert {
          MenuPlacement(
            id: placementID,
            menuID: menuID,
            startDate: scheduledDate,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let manualAKey = MealPlanItemRowID.manual(manualAID).rawValue
        let manualBKey = MealPlanItemRowID.manual(manualBID).rawValue
        let menu1Key = MealPlanItemRowID.menu(placementID: placementID, itemID: menuItem1ID).rawValue
        let menu2Key = MealPlanItemRowID.menu(placementID: placementID, itemID: menuItem2ID).rawValue

        // Baseline: with no overlay, the comparator interleaves manual and menu rows by
        // their (independent) sortOrder, breaking ties toward manual rows.
        let baseline = try MealCalendarRequest().fetch(db)
          .filter { $0.item.scheduledDate == scheduledDate }
        expectNoDifference(
          baseline.map(\.id.rawValue),
          [manualAKey, menu1Key, manualBKey, menu2Key]
        )

        // Interleave a manual item between the two menu rows, and drop "Manual A" to the end
        // by leaving it out of the overlay (unlisted rows follow the listed ones).
        try MealCalendarRepository.setDayOrder(
          orderedRowKeys: [menu1Key, manualBKey, menu2Key],
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let reordered = try MealCalendarRequest().fetch(db)
          .filter { $0.item.scheduledDate == scheduledDate }
        expectNoDifference(
          reordered.map(\.id.rawValue),
          [menu1Key, manualBKey, menu2Key, manualAKey]
        )

        // The underlying menu is untouched.
        let menuItems = try MenuItem.where { $0.menuID.eq(menuID) }
          .order { $0.sortOrder }
          .fetchAll(db)
        expectNoDifference(menuItems.map(\.id), [menuItem1ID, menuItem2ID])
        expectNoDifference(menuItems.map(\.sortOrder), [0, 1])

        // Re-saving keeps a single overlay row for the slot.
        try MealCalendarRepository.setDayOrder(
          orderedRowKeys: [manualAKey, manualBKey, menu1Key, menu2Key],
          on: scheduledDate,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let overlays = try MealPlanDayOrder
          .where { $0.scheduledDate.eq(scheduledDate) && $0.mealSlot.eq(MealPlanItemSlot.dinner) }
          .fetchAll(db)
        expectNoDifference(overlays.count, 1)
      }
    }
  }
}
