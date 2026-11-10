import Foundation
import YesChefCore

struct MenuEditPlacementDraft: Identifiable, Hashable, Sendable {
  var id = UUID()
  var placementID: MenuPlacement.ID?
  var originalStartDate: Date?
  var startDate: Date

  init(placementID: MenuPlacement.ID? = nil, startDate: Date) {
    self.placementID = placementID
    self.originalStartDate = placementID == nil ? nil : startDate
    self.startDate = startDate
  }
}

struct MenuEditDraftContext: Identifiable {
  var menuID: CoreMenu.ID
  var title: String
  var notes: String
  var dayCount: Int
  var minimumDayCount: Int
  var placements: [MenuEditPlacementDraft]
  var bringInOffer: MenuBringInOffer?

  var id: CoreMenu.ID { menuID }
}

struct MenuPlacementDeletionContext: Identifiable, Hashable, Sendable {
  var placementID: MenuPlacement.ID
  var menuTitle: String
  var startDate: Date

  var id: MenuPlacement.ID { placementID }
}
