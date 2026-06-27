import Foundation

public struct GrocerySourceContribution: Identifiable, Equatable, Sendable {
  public typealias ID = GrocerySourceContributionID

  public var id: ID
  public var sources: [GroceryItemSource]

  public init(id: ID, sources: [GroceryItemSource]) {
    self.id = id
    self.sources = sources
  }

  public var representativeSourceID: GroceryItemSource.ID? {
    sources.first?.id
  }

  public var representativeSource: GroceryItemSource? {
    sources.first
  }

  public var removalTitle: String? {
    representativeSource?.contributionRemovalTitle
  }
}

public enum GrocerySourceContributionID: Hashable, Sendable {
  case source(GroceryItemSource.ID)
  case recipe(Recipe.ID)
  case calendarItem(MealPlanItem.ID)
  case menuItem(Menu.ID, MenuItem.ID)
  case menuPlacementItem(MenuPlacement.ID, MenuItem.ID)
}

public extension GroceryItemRowData {
  var sourceContributions: [GrocerySourceContribution] {
    var contributionIndices: [GrocerySourceContribution.ID: Int] = [:]
    var contributions: [GrocerySourceContribution] = []

    for source in sources {
      let id = source.contributionID
      if let index = contributionIndices[id] {
        contributions[index].sources.append(source)
      } else {
        contributionIndices[id] = contributions.count
        contributions.append(
          GrocerySourceContribution(id: id, sources: [source])
        )
      }
    }

    return contributions
  }
}

public extension GroceryItemSource {
  var contributionID: GrocerySourceContributionID {
    switch origin {
    case .custom:
      .source(id)

    case .recipe:
      if let recipeID {
        .recipe(recipeID)
      } else {
        .source(id)
      }

    case .calendarItem:
      if let mealPlanItemID {
        .calendarItem(mealPlanItemID)
      } else {
        .source(id)
      }

    case .menu:
      if let menuID, let menuItemID {
        .menuItem(menuID, menuItemID)
      } else {
        .source(id)
      }

    case .menuPlacement:
      if let menuPlacementID, let menuItemID {
        .menuPlacementItem(menuPlacementID, menuItemID)
      } else {
        .source(id)
      }
    }
  }

  var contributionRemovalTitle: String? {
    switch origin {
    case .custom:
      nil
    case .recipe:
      recipeID == nil ? nil : "Remove Recipe Items"
    case .calendarItem:
      mealPlanItemID == nil ? nil : "Remove Calendar Items"
    case .menu:
      menuID == nil || menuItemID == nil ? nil : "Remove Menu Dish Items"
    case .menuPlacement:
      menuPlacementID == nil || menuItemID == nil ? nil : "Remove Placed Dish Items"
    }
  }
}
