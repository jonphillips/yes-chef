import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct DeletionCopyTests {
    @Test
    func menuDeletionDescribesEachAffectedResource() {
      let menuID = UUID()

      expectNoDifference(
        deleteMenuMessage(
          MenuDeletionContext(menuID: menuID, menuTitle: "Weekend Feast", itemCount: 0, placementCount: 0)
        ),
        "Delete Weekend Feast?"
      )
      expectNoDifference(
        deleteMenuMessage(
          MenuDeletionContext(menuID: menuID, menuTitle: "Weekend Feast", itemCount: 1, placementCount: 0)
        ),
        "Delete Weekend Feast and its 1 dish?"
      )
      expectNoDifference(
        deleteMenuMessage(
          MenuDeletionContext(menuID: menuID, menuTitle: "Weekend Feast", itemCount: 2, placementCount: 0)
        ),
        "Delete Weekend Feast and its 2 dishes?"
      )
      expectNoDifference(
        deleteMenuMessage(
          MenuDeletionContext(menuID: menuID, menuTitle: "Weekend Feast", itemCount: 0, placementCount: 1)
        ),
        "Delete Weekend Feast and its 1 calendar placement?"
      )
      expectNoDifference(
        deleteMenuMessage(
          MenuDeletionContext(menuID: menuID, menuTitle: "Weekend Feast", itemCount: 0, placementCount: 2)
        ),
        "Delete Weekend Feast and its 2 calendar placements?"
      )
      expectNoDifference(
        deleteMenuMessage(
          MenuDeletionContext(menuID: menuID, menuTitle: "Weekend Feast", itemCount: 1, placementCount: 1)
        ),
        "Delete Weekend Feast and its 1 dish and 1 calendar placement?"
      )
    }

    @Test
    func workbenchDeletionDescribesCandidateAndWorkingRecipeRetention() {
      let workbenchID = UUID()

      expectNoDifference(
        deleteWorkbenchMessage(
          WorkbenchDeletionContext(
            workbenchID: workbenchID,
            title: "Weeknight Dinners",
            candidateCount: 2,
            workingRecipeTitle: "Lemon Chicken"
          )
        ),
        "Delete Weeknight Dinners and its 2 candidates? The recipes stay in your library."
      )
      expectNoDifference(
        deleteWorkbenchMessage(
          WorkbenchDeletionContext(
            workbenchID: workbenchID,
            title: "Weeknight Dinners",
            candidateCount: 0,
            workingRecipeTitle: "Lemon Chicken"
          )
        ),
        "Delete Weeknight Dinners? The working recipe Lemon Chicken stays in your library."
      )
      expectNoDifference(
        deleteWorkbenchMessage(
          WorkbenchDeletionContext(
            workbenchID: workbenchID,
            title: "Weeknight Dinners",
            candidateCount: 0,
            workingRecipeTitle: nil
          )
        ),
        "Delete Weeknight Dinners? No recipes will be deleted."
      )
    }
  }
}
