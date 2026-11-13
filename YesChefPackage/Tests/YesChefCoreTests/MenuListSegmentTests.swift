import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuListSegmentTests {
    @Test
    func sortsDatedMenusByLatestPlacementAndUndatedByTitle() throws {
      let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
      let early = now
      let late = now.addingTimeInterval(86_400)
      let menus = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"].enumerated().map { index, title in
        MenuRowData(
          menu: Menu(
            id: SampleUUIDSequence.uuid(90_500 + index),
            title: title,
            dayCount: 1,
            dateCreated: now,
            dateModified: now
          ),
          latestPlacementDate: [early, late, nil, nil, late][index]
        )
      }

      expectNoDifference(
        MenuListSegment.dated.rows(from: menus).map(\.menu.title),
        ["Beta", "Epsilon", "Alpha"]
      )
      expectNoDifference(
        MenuListSegment.undated.rows(from: menus).map(\.menu.title),
        ["Delta", "Gamma"]
      )
    }

    @Test
    func requestUsesTheLatestPlacementDate() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_010_000)
      let menuID = SampleUUIDSequence.uuid(90_510)
      let earlier = now.addingTimeInterval(-86_400)
      let later = now

      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Dated", dayCount: 1, dateCreated: now, dateModified: now)
        }.execute(db)
        for (index, date) in [earlier, later].enumerated() {
          try MenuPlacement.insert {
            MenuPlacement(
              id: SampleUUIDSequence.uuid(90_511 + index),
              menuID: menuID,
              startDate: date,
              dateCreated: now,
              dateModified: now
            )
          }.execute(db)
        }
      }

      let rows = try database.read { db in try MenuListRequest().fetch(db) }
      expectNoDifference(rows.first?.latestPlacementDate, later)
    }
  }
}
