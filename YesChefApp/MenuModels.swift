import CasePaths
import Dependencies
import Foundation
import Observation
import SQLiteData
import SwiftUI
import YesChefCore

typealias CoreMenu = YesChefCore.Menu

@Observable
@MainActor
final class MenuLibraryModel {
  @CasePathable
  enum Destination {
    case addMenu
    case addItem(MenuItemDraftContext)
    case placeMenu(MenuPlacementDraftContext)
    case deletePlacement(MenuPlacementDeletionContext)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(MenuListRequest(), animation: .default) var menuRows: [MenuRowData] = []
  @ObservationIgnored
  @Fetch(RecipeListRequest(), animation: .default) var recipeRows: [RecipeListRowData] = []

  var destination: Destination?
  var navigationPath: [CoreMenu.ID] = []
  var selectedMenuID: CoreMenu.ID?
  var errorMessage: String?
  var isShowingError = false

  var availableRecipeRows: [RecipeListRowData] {
    recipeRows
      .filter { !$0.recipe.archived }
      .sorted {
        $0.recipe.title.localizedStandardCompare($1.recipe.title) == .orderedAscending
      }
  }

  func reloadAfterExternalChange() async {
    try? await $menuRows.load()
    try? await $recipeRows.load()
  }

  func addMenuButtonTapped() {
    destination = .addMenu
  }

  func selectMenu(_ menuID: CoreMenu.ID) {
    selectedMenuID = menuID
    navigationPath = [menuID]
  }

  func addItemButtonTapped(
    menu: CoreMenu,
    kind: MealPlanItemKind = .recipe,
    dayOffset: Int = 0,
    mealSlot: MealPlanItemSlot = .dinner,
    recipeID: Recipe.ID? = nil
  ) {
    destination = .addItem(
      MenuItemDraftContext(
        menuID: menu.id,
        menuTitle: menu.title,
        dayCount: menu.dayCount,
        kind: kind,
        dayOffset: dayOffset,
        mealSlot: mealSlot,
        recipeID: recipeID
      )
    )
  }

  func placeMenuButtonTapped(menu: CoreMenu) {
    destination = .placeMenu(
      MenuPlacementDraftContext(
        menuID: menu.id,
        menuTitle: menu.title,
        placementID: nil,
        startDate: Calendar.autoupdatingCurrent.startOfDay(for: now)
      )
    )
  }

  func saveMenuButtonTapped(title: String, notes: String, dayCount: Int) -> Bool {
    do {
      let menuID = try database.write { db in
        try MenuRepository.addMenu(
          title: title,
          notes: notes,
          dayCount: dayCount,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      selectedMenuID = menuID
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func saveRecipeItemButtonTapped(
    menuID: CoreMenu.ID,
    recipeID: Recipe.ID,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    notes: String
  ) -> Bool {
    do {
      _ = try database.write { db in
        try MenuRepository.addRecipeItem(
          menuID: menuID,
          recipeID: recipeID,
          dayOffset: dayOffset,
          mealSlot: mealSlot,
          notes: notes,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func addRecipesToMenu(
    recipeIDs: [Recipe.ID],
    menuID: CoreMenu.ID,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot = .dinner
  ) -> Bool {
    do {
      try database.write { db in
        for recipeID in recipeIDs {
          try MenuRepository.addRecipeItem(
            menuID: menuID,
            recipeID: recipeID,
            dayOffset: dayOffset,
            mealSlot: mealSlot,
            notes: nil,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func moveMenuItem(
    itemID: MenuItem.ID,
    toDayOffset dayOffset: Int
  ) -> Bool {
    do {
      try database.write { db in
        try MenuRepository.moveItem(
          itemID: itemID,
          toDayOffset: dayOffset,
          in: db,
          now: now
        )
      }
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func saveNoteItemButtonTapped(
    menuID: CoreMenu.ID,
    title: String,
    notes: String,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot
  ) -> Bool {
    do {
      _ = try database.write { db in
        try MenuRepository.addNoteItem(
          menuID: menuID,
          title: title,
          notes: notes,
          dayOffset: dayOffset,
          mealSlot: mealSlot,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func editPlacementButtonTapped(menu: CoreMenu, placement: MenuPlacement) {
    destination = .placeMenu(
      MenuPlacementDraftContext(
        menuID: menu.id,
        menuTitle: menu.title,
        placementID: placement.id,
        startDate: placement.startDate
      )
    )
  }

  func deletePlacementButtonTapped(menu: CoreMenu, placement: MenuPlacement) {
    destination = .deletePlacement(
      MenuPlacementDeletionContext(
        placementID: placement.id,
        menuTitle: menu.title,
        startDate: placement.startDate
      )
    )
  }

  func savePlacementButtonTapped(context: MenuPlacementDraftContext, startDate: Date) -> Bool {
    do {
      let startDate = Calendar.autoupdatingCurrent.startOfDay(for: startDate)
      _ = try database.write { db in
        if let placementID = context.placementID {
          try MenuRepository.updateMenuPlacement(
            placementID: placementID,
            startDate: startDate,
            in: db,
            now: now
          )
        } else {
          try MenuRepository.placeMenu(
            menuID: context.menuID,
            startDate: startDate,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func confirmDeletePlacementButtonTapped(_ context: MenuPlacementDeletionContext) {
    destination = nil

    do {
      try database.write { db in
        try MenuRepository.deleteMenuPlacement(
          placementID: context.placementID,
          in: db
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func clearPrepPlanButtonTapped(menuID: CoreMenu.ID) {
    do {
      try database.write { db in
        try MenuRepository.clearPrepPlan(menuID: menuID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}

@Observable
@MainActor
final class MenuDetailModel {
  let menuID: CoreMenu.ID

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Fetch var detail: MenuDetailData?

  init(menuID: CoreMenu.ID) {
    self.menuID = menuID
    _detail = Fetch(wrappedValue: nil, MenuDetailRequest(menuID: menuID), animation: .default)
  }

  func applyActionCatalog(for chatModel: RecipeChatModel) -> [AnyChatApplyAction] {
    @Dependency(\.menuComplementClient) var menuComplementClient
    @Dependency(\.menuPrepPlanClient) var menuPrepPlanClient

    let context = chatModel.context.serialized()
    let complementAction = ChatApplyAction<MenuComplementPlan>(
      title: "What complements this? -> Menu items",
      extractingTitle: "Finding complements...",
      reviewTitle: "Review complement",
      commitTitle: "Add to Menu",
      committingTitle: "Adding to menu...",
      committedTitle: "Added to Menu",
      extract: { selection, messages in
        try await menuComplementClient(
          selection: selection,
          messages: messages,
          context: context,
          tier: chatModel.activeTier
        )
      },
      commit: { [weak self] plan in
        try self?.commitComplementPlan(plan)
      }
    )
    let prepPlanAction = ChatApplyAction<MenuPrepPlan>(
      title: "Build prep plan -> Prep Plan section",
      extractingTitle: "Building prep plan...",
      reviewTitle: "Review prep plan",
      commitTitle: "Commit to Prep Plan",
      committingTitle: "Saving prep plan...",
      committedTitle: "Saved to Prep Plan",
      extract: { selection, messages in
        try await menuPrepPlanClient(
          selection: selection,
          messages: messages,
          context: context,
          tier: chatModel.activeTier
        )
      },
      commit: { [weak self] plan in
        try self?.commitPrepPlan(plan)
      }
    )

    return [
      AnyChatApplyAction(complementAction) { [weak self] plan in
        plan.items.map { suggestion in
          ChatApplyReviewItem(
            title: suggestion.title,
            summary: suggestion.rendered(),
            commitTitle: complementAction.commitTitle,
            committingTitle: complementAction.committingTitle,
            committedTitle: complementAction.committedTitle,
            commit: {
              try self?.commitComplementSuggestion(suggestion)
            }
          )
        }
      },
      AnyChatApplyAction(prepPlanAction) { plan in
        plan.rendered().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil
          : plan.rendered()
      }
    ]
  }

  private func commitPrepPlan(_ plan: MenuPrepPlan) throws {
    guard !plan.steps.isEmpty else {
      throw MenuDetailError.emptyPrepPlan
    }
    try database.write { db in
      try MenuRepository.applyPrepPlan(plan, to: menuID, in: db, now: now)
    }
  }

  private func commitComplementPlan(_ plan: MenuComplementPlan) throws {
    guard !plan.items.isEmpty else {
      throw MenuDetailError.emptyComplementSuggestion
    }
    try database.write { db in
      for suggestion in plan.items {
        try MenuRepository.addComplementItem(
          suggestion,
          to: menuID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
    }
  }

  private func commitComplementSuggestion(_ suggestion: MenuComplementSuggestion) throws {
    _ = try database.write { db in
      try MenuRepository.addComplementItem(
        suggestion,
        to: menuID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }
}

private enum MenuDetailError: Error, CustomStringConvertible, LocalizedError {
  case emptyComplementSuggestion
  case emptyPrepPlan

  var description: String {
    switch self {
    case .emptyComplementSuggestion:
      "The assistant did not find a menu item to add."
    case .emptyPrepPlan:
      "The assistant did not find a prep plan to save."
    }
  }

  var errorDescription: String? { description }
}

enum MenuListStyle {
  case navigation
  case selection
}

struct MenuItemDraftContext: Hashable, Sendable {
  var menuID: CoreMenu.ID
  var menuTitle: String
  var dayCount: Int
  var kind: MealPlanItemKind = .recipe
  var dayOffset: Int = 0
  var mealSlot: MealPlanItemSlot = .dinner
  var recipeID: Recipe.ID?
}

struct MenuPlacementDraftContext: Hashable, Sendable {
  var menuID: CoreMenu.ID
  var menuTitle: String
  var placementID: MenuPlacement.ID?
  var startDate: Date

  var isEditing: Bool { placementID != nil }
}

struct MenuPlacementDeletionContext: Identifiable, Hashable, Sendable {
  var placementID: MenuPlacement.ID
  var menuTitle: String
  var startDate: Date

  var id: MenuPlacement.ID { placementID }
}
