import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuChatContextPlacementTests {
    @Test
    func placedMenuChatContextIncludesAuthoritativeDates() throws {
      let calendar = Calendar.autoupdatingCurrent
      let startDate = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12))
      )
      let secondDate = try #require(calendar.date(byAdding: .day, value: 1, to: startDate))
      let menuID = SampleUUIDSequence.uuid(13_100)
      let detail = MenuDetailData(
        menu: Menu(
          id: menuID,
          title: "Beach Weekend",
          dayCount: 2,
          dateCreated: startDate,
          dateModified: startDate
        ),
        itemRows: [
          MenuItemRowData(
            item: MenuItem(
              id: SampleUUIDSequence.uuid(13_101),
              menuID: menuID,
              kind: .note,
              title: "Korean Bavette",
              dayOffset: 1,
              mealSlot: .dinner,
              sortOrder: 0,
              dateCreated: startDate,
              dateModified: startDate
            )
          )
        ],
        placements: [
          MenuPlacement(
            id: SampleUUIDSequence.uuid(13_102),
            menuID: menuID,
            startDate: startDate,
            dateCreated: startDate,
            dateModified: startDate
          )
        ]
      )

      let context = MenuChatContext(detail: detail)
      let serialized = context.serialized(for: .frontierPreferred)
      let prompt = context.prepPrompt()
      let startLabel = startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
      let secondLabel = secondDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

      #expect(context.placementStartDate == startDate)
      #expect(serialized.contains("- Dates: \(startLabel)–\(secondLabel)"))
      #expect(serialized.contains("- Day: 2 (dayOffset 1, \(secondLabel))"))
      #expect(prompt.contains("calendar dates in the menu context are authoritative"))
      #expect(prompt.contains("Saturday · ~3 hrs out"))
      #expect(prompt.contains("Saturday's Korean Bavette"))
    }

    @Test
    func unplacedMenuChatContextKeepsRelativeHorizonPrompt() {
      let context = MenuChatContext(
        title: "Unscheduled Weekend",
        dayCount: 2,
        items: [
          MenuChatItemContext(
            id: SampleUUIDSequence.uuid(13_110),
            title: "Korean Bavette",
            kind: .recipe,
            dayOffset: 1,
            mealSlot: .dinner,
            sortOrder: 0
          )
        ]
      )
      let serialized = context.serialized(for: .frontierPreferred)
      let prompt = context.prepPrompt()

      #expect(context.placementStartDate == nil)
      #expect(!serialized.contains("- Dates:"))
      #expect(serialized.contains("- Day: 2 (dayOffset 1)"))
      #expect(!serialized.contains("dayOffset 1,"))
      #expect(prompt.contains("relative-horizon wording"))
      #expect(prompt.contains("Two days ahead"))
      #expect(!prompt.contains("calendar dates in the menu context are authoritative"))
    }

    @Test
    func makeAheadWindowAppearsInContextAndCopyPrompt() {
      let context = MenuChatContext(
        title: "Thanksgiving",
        dayCount: 2,
        prepPlan: [
          PrepPlanStepRecord(
            id: SampleUUIDSequence.uuid(13_130),
            menuID: SampleUUIDSequence.uuid(13_131),
            sortOrder: 0,
            session: "Monday",
            task: "Make gravy",
            makeAheadWindow: "Up to 3 days ahead",
            timeOfDay: 15 * 60 + 15,
            workDayOffset: 0
          )
        ]
      )
      let serialized = context.serialized(for: .frontierPreferred)
      let prompt = context.prepPrompt()
      #expect(serialized.contains("Make-ahead window: Up to 3 days ahead"))
      #expect(serialized.contains("Time: 15:15"))
      #expect(prompt.components(separatedBy: MenuPrepPlanClient.makeAheadAndLeftoversGuidance).count == 2)
      #expect(prompt.components(separatedBy: MenuPrepPlanClient.timeOfDayGuidance).count == 2)
      #expect(prompt.contains("Keeps: <window>"))
    }
  }
}
