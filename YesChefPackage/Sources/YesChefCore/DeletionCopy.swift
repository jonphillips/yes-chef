import Foundation

public struct MenuDeletionContext: Identifiable, Hashable, Sendable {
  public var menuID: Menu.ID
  public var menuTitle: String
  public var itemCount: Int
  public var placementCount: Int

  public init(menuID: Menu.ID, menuTitle: String, itemCount: Int, placementCount: Int) {
    self.menuID = menuID
    self.menuTitle = menuTitle
    self.itemCount = itemCount
    self.placementCount = placementCount
  }

  public var id: Menu.ID { menuID }
}

public struct WorkbenchDeletionContext: Identifiable, Hashable, Sendable {
  public var workbenchID: Workbench.ID
  public var title: String
  public var candidateCount: Int
  public var workingRecipeTitle: String?

  public init(
    workbenchID: Workbench.ID,
    title: String,
    candidateCount: Int,
    workingRecipeTitle: String?
  ) {
    self.workbenchID = workbenchID
    self.title = title
    self.candidateCount = candidateCount
    self.workingRecipeTitle = workingRecipeTitle
  }

  public var id: Workbench.ID { workbenchID }
}

public func deleteMenuMessage(_ context: MenuDeletionContext) -> String {
  var details: [String] = []
  if context.itemCount > 0 {
    details.append(context.itemCount == 1 ? "1 dish" : "\(context.itemCount) dishes")
  }
  if context.placementCount > 0 {
    details.append(
      context.placementCount == 1 ? "1 calendar placement" : "\(context.placementCount) calendar placements"
    )
  }
  guard !details.isEmpty else {
    return "Delete \(context.menuTitle)?"
  }
  return "Delete \(context.menuTitle) and its \(details.joined(separator: " and "))?"
}

public func deleteWorkbenchMessage(_ context: WorkbenchDeletionContext) -> String {
  let candidateText = context.candidateCount == 1 ? "1 candidate" : "\(context.candidateCount) candidates"
  if context.candidateCount > 0 {
    return "Delete \(context.title) and its \(candidateText)? The recipes stay in your library."
  }
  if let workingRecipeTitle = context.workingRecipeTitle {
    return "Delete \(context.title)? The working recipe \(workingRecipeTitle) stays in your library."
  }
  return "Delete \(context.title)? No recipes will be deleted."
}
