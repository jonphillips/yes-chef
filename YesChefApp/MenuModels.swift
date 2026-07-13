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
    case deleteMenu(MenuDeletionContext)
    case deleteItem(MenuItemDeletionContext)
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

  func editItemButtonTapped(menu: CoreMenu, row: MenuItemRowData) {
    destination = .addItem(
      MenuItemDraftContext(
        itemID: row.id,
        menuID: menu.id,
        menuTitle: menu.title,
        dayCount: menu.dayCount,
        kind: row.item.kind,
        dayOffset: row.item.dayOffset,
        mealSlot: row.item.mealSlot,
        recipeID: row.item.recipeID,
        noteTitle: row.item.kind == .recipe ? "" : row.item.title,
        notes: row.item.notes ?? ""
      )
    )
  }

  func placeMenuButtonTapped(menu: CoreMenu, minimumDayCount: Int = 1) {
    destination = .placeMenu(
      MenuPlacementDraftContext(
        menuID: menu.id,
        menuTitle: menu.title,
        placementID: nil,
        startDate: Calendar.autoupdatingCurrent.startOfDay(for: now),
        dayCount: menu.dayCount,
        minimumDayCount: minimumDayCount
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

  func updateRecipeItemButtonTapped(
    itemID: MenuItem.ID,
    recipeID: Recipe.ID,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    notes: String
  ) -> Bool {
    do {
      try database.write { db in
        try MenuRepository.updateRecipeItem(
          itemID: itemID,
          recipeID: recipeID,
          dayOffset: dayOffset,
          mealSlot: mealSlot,
          notes: notes,
          in: db,
          now: now
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
    toDayOffset dayOffset: Int,
    mealSlot: MealPlanItemSlot? = nil
  ) -> Bool {
    do {
      try database.write { db in
        try MenuRepository.moveItem(
          itemID: itemID,
          toDayOffset: dayOffset,
          mealSlot: mealSlot,
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

  @discardableResult
  func reorderMenuItemWithinDay(
    itemID: MenuItem.ID,
    direction: MenuItemMoveDirection
  ) -> Bool {
    do {
      return try database.write { db in
        try MenuRepository.reorderItemWithinDay(
          itemID: itemID,
          direction: direction,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func deleteMenuButtonTapped(_ row: MenuRowData) {
    destination = .deleteMenu(
      MenuDeletionContext(
        menuID: row.id,
        menuTitle: row.menu.title,
        itemCount: row.itemCount,
        placementCount: row.placementCount
      )
    )
  }

  func confirmDeleteMenuButtonTapped(_ context: MenuDeletionContext) {
    destination = nil

    do {
      try database.write { db in
        try MenuRepository.deleteMenu(menuID: context.menuID, in: db)
      }
      if selectedMenuID == context.menuID {
        selectedMenuID = nil
      }
      navigationPath.removeAll { $0 == context.menuID }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteMenuItemButtonTapped(_ row: MenuItemRowData) {
    destination = .deleteItem(
      MenuItemDeletionContext(
        itemID: row.id,
        title: row.displayTitle
      )
    )
  }

  func confirmDeleteMenuItemButtonTapped(_ context: MenuItemDeletionContext) {
    destination = nil

    do {
      try database.write { db in
        try MenuRepository.deleteItem(itemID: context.itemID, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
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

  func updateNoteItemButtonTapped(
    itemID: MenuItem.ID,
    title: String,
    notes: String,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot
  ) -> Bool {
    do {
      try database.write { db in
        try MenuRepository.updateNoteItem(
          itemID: itemID,
          title: title,
          notes: notes,
          dayOffset: dayOffset,
          mealSlot: mealSlot,
          in: db,
          now: now
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

  func editPlacementButtonTapped(menu: CoreMenu, placement: MenuPlacement, minimumDayCount: Int = 1) {
    destination = .placeMenu(
      MenuPlacementDraftContext(
        menuID: menu.id,
        menuTitle: menu.title,
        placementID: placement.id,
        startDate: placement.startDate,
        dayCount: menu.dayCount,
        minimumDayCount: minimumDayCount
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
        try MenuRepository.updateMenuDayCount(
          menuID: context.menuID,
          dayCount: context.dayCount,
          in: db,
          now: now
        )
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

  /// The menu item the next chat "deposit" writes onto (ADR-0027 Amendment 1 tap-to-target). `nil`
  /// when nothing is targeted, in which case the deposit verbs don't appear. Device-local, unsynced.
  var selectedTargetItemID: MenuItem.ID?
  var errorMessage: String?
  var isShowingError = false

  init(menuID: CoreMenu.ID) {
    self.menuID = menuID
    _detail = Fetch(wrappedValue: nil, MenuDetailRequest(menuID: menuID), animation: .default)
  }

  /// The row currently marked as the deposit target, resolved against the live item set (so a stale
  /// id — e.g. the item was deleted — reads as no target).
  var selectedTargetItem: MenuItemRowData? {
    guard let selectedTargetItemID else { return nil }
    return detail?.itemRows.first { $0.id == selectedTargetItemID }
  }

  /// Toggles a menu item as the active deposit target. Tapping the current target clears it.
  func targetItemTapped(_ itemID: MenuItem.ID) {
    selectedTargetItemID = selectedTargetItemID == itemID ? nil : itemID
  }

  func prepPlanPasted(_ text: String) {
    let currentPlan = MenuPrepPlan(steps: MenuPrepPlanCoding.decode(detail?.menu.prepPlan))
    let plan = currentPlan.applyingEditableReviewText(text)

    guard !plan.steps.isEmpty else {
      errorMessage = "The pasted plan needs a session heading followed by one or more prep steps."
      isShowingError = true
      return
    }

    do {
      try commitPrepPlan(plan)
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func applyActionCatalog(for chatModel: RecipeChatModel) -> [AnyChatApplyAction] {
    @Dependency(\.menuComplementClient) var menuComplementClient
    @Dependency(\.menuNoteHarvestClient) var menuNoteHarvestClient
    @Dependency(\.menuPrepPlanClient) var menuPrepPlanClient
    @Dependency(\.menuDepositClient) var menuDepositClient

    let context = chatModel.context.serialized(for: chatModel.activeTier)
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
      commit: { _ in
      }
    )
    let harvestAction = ChatApplyAction<MenuNoteHarvestPlan>(
      title: "Capture to menu",
      extractingTitle: "Capturing…",
      reviewTitle: "Review captured note",
      commitTitle: "Add to Menu",
      committingTitle: "Adding to menu…",
      committedTitle: "Added to Menu",
      extract: { selection, messages in
        try await menuNoteHarvestClient(
          selection: selection,
          messages: messages,
          tier: chatModel.activeTier
        )
      },
      commit: { _ in
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

    var actions: [AnyChatApplyAction] = [
      AnyChatApplyAction(complementAction) { [weak self] plan in
        plan.items.map { suggestion in
          let originalEditableText = suggestion.editableReviewText()
          return ChatApplyReviewItem(
            title: suggestion.title,
            summary: suggestion.rendered(),
            editableTitle: "Complement",
            editableText: originalEditableText,
            commitTitle: complementAction.commitTitle,
            committingTitle: complementAction.committingTitle,
            committedTitle: complementAction.committedTitle,
            commit: { editedText in
              let approved = editedText == originalEditableText
                ? suggestion
                : suggestion.applyingEditableReviewText(editedText)
              try self?.commitComplementSuggestion(approved)
            }
          )
        }
      },
      AnyChatApplyAction(harvestAction, requiresSubject: false) { [weak self] plan in
        plan.notes.map { note in
          let originalEditableText = note.editableReviewText()
          return ChatApplyReviewItem(
            title: note.title,
            summary: note.rendered(),
            editableTitle: "Note",
            editableText: originalEditableText,
            commitTitle: harvestAction.commitTitle,
            committingTitle: harvestAction.committingTitle,
            committedTitle: harvestAction.committedTitle,
            commit: { editedText in
              let approved = editedText == originalEditableText
                ? note
                : note.applyingEditableReviewText(editedText)
              try self?.commitCapturedNote(approved)
            }
          )
        }
      },
      AnyChatApplyAction(
        prepPlanAction,
        emptyResultMessage: """
          No prep steps to save yet. Try asking for a work-session timeline for the menu's dishes.
          """,
        editableSummary: { plan in
          plan.editableReviewText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : plan.editableReviewText()
        },
        commitEditedSummary: { [weak self] plan, editedText in
          try self?.commitPrepPlan(plan.applyingEditableReviewText(editedText))
        }
      )
    ]

    // ADR-0027 Amendment 1 — the tap-to-target "deposit" verbs (S1 recipe-append, S2 note-revise),
    // shown only when a menu item is the active tap-to-target and matches the verb's kind.
    actions.append(contentsOf: depositToRecipeActions(chatModel: chatModel, menuDepositClient: menuDepositClient))
    actions.append(contentsOf: reviseNoteActions(chatModel: chatModel, menuDepositClient: menuDepositClient))

    return actions
  }

  /// ADR-0027 Amendment 1 S1 — reshapes chat intelligence into an appended `RecipeNote` on the
  /// recipe-kind tap-to-target; the canonical recipe body is never touched (A2).
  private func depositToRecipeActions(
    chatModel: RecipeChatModel,
    menuDepositClient: MenuDepositClient
  ) -> [AnyChatApplyAction] {
    guard
      let target = selectedTargetItem,
      target.item.kind == .recipe,
      let targetRecipeID = target.item.recipeID
    else { return [] }

    let depositAction = ChatApplyAction<DepositNotePlan>(
      title: "Add to recipe notes",
      extractingTitle: "Drafting note…",
      reviewTitle: "Review recipe note",
      commitTitle: "Add to Recipe Notes",
      committingTitle: "Adding to notes…",
      committedTitle: "Added to Recipe Notes",
      extract: { selection, messages in
        try await menuDepositClient(
          intelligence: selection,
          messages: messages,
          tier: chatModel.activeTier
        )
      },
      // The unchanged-payload commit path (editable review, committed unedited) routes through here,
      // so it must write, not no-op.
      commit: { [weak self] plan in
        try self?.commitDepositToRecipe(plan.note.text, targetRecipeID: targetRecipeID)
      }
    )
    return [
      AnyChatApplyAction(
        depositAction,
        editableSummary: { plan in
          let text = plan.note.editableReviewText()
          return text.isEmpty ? nil : text
        },
        commitEditedSummary: { [weak self] _, editedText in
          try self?.commitDepositToRecipe(editedText, targetRecipeID: targetRecipeID)
        }
      )
    ]
  }

  /// ADR-0027 Amendment 1 S2 — weaves chat intelligence into the note-kind tap-to-target's existing
  /// body; the compose surface shows the untouched original (supporting evidence) beside the
  /// LLM-woven editable draft (A3).
  private func reviseNoteActions(
    chatModel: RecipeChatModel,
    menuDepositClient: MenuDepositClient
  ) -> [AnyChatApplyAction] {
    guard let target = selectedTargetItem, target.item.kind == .note else { return [] }

    let targetItemID = target.item.id
    let currentNoteBody = target.item.notes ?? ""
    let reviseAction = ChatApplyAction<DepositNotePlan>(
      title: "Revise this note",
      extractingTitle: "Weaving note…",
      reviewTitle: "Review revised note",
      commitTitle: "Save Note",
      committingTitle: "Saving note…",
      committedTitle: "Note Updated",
      extract: { selection, messages in
        try await menuDepositClient(
          intelligence: selection,
          currentNoteBody: currentNoteBody,
          messages: messages,
          tier: chatModel.activeTier
        )
      },
      commit: { _ in }
    )
    return [
      AnyChatApplyAction(reviseAction, requiresSubject: false) { [weak self] plan in
        let draftText = plan.note.editableReviewText()
        guard !draftText.isEmpty else { return [] }
        return [
          ChatApplyReviewItem(
            title: reviseAction.reviewTitle,
            summary: draftText,
            editableTitle: "Revised note",
            editableText: draftText,
            supportingEvidenceTitle: "Original note",
            supportingEvidenceRows: currentNoteBody.isEmpty ? [] : [currentNoteBody],
            commitTitle: reviseAction.commitTitle,
            committingTitle: reviseAction.committingTitle,
            committedTitle: reviseAction.committedTitle,
            commit: { [weak self] editedText in
              try self?.commitDepositToNote(editedText, targetItemID: targetItemID)
            }
          )
        ]
      }
    ]
  }

  private func commitDepositToRecipe(_ text: String, targetRecipeID: Recipe.ID) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw MenuDetailError.emptyDepositNote
    }
    try database.write { db in
      // Deposited adaptation intelligence: `.adaptation` note type (OQ-Amd-1 lean); the recipe body
      // is never rewritten (A2 — protect the canonical recipe).
      _ = try RecipeRepository.appendRecipeNote(
        recipeID: targetRecipeID,
        text: trimmed,
        noteType: .adaptation,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }

  private func commitDepositToNote(_ text: String, targetItemID: MenuItem.ID) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw MenuDetailError.emptyDepositNote
    }
    // Resolve fresh against the live item set (not the captured row) — the item's day/slot/title may
    // have changed between extract and commit.
    guard let row = detail?.itemRows.first(where: { $0.id == targetItemID }) else {
      throw MenuDetailError.depositTargetMissing
    }
    try database.write { db in
      try MenuRepository.updateNoteItem(
        itemID: targetItemID,
        title: row.item.title,
        notes: trimmed,
        dayOffset: row.item.dayOffset,
        mealSlot: row.item.mealSlot,
        in: db,
        now: now
      )
    }
  }

  private func commitPrepPlan(_ plan: MenuPrepPlan) throws {
    guard !plan.steps.isEmpty else {
      throw MenuDetailError.emptyPrepPlan
    }
    try database.write { db in
      try MenuRepository.applyPrepPlan(plan, to: menuID, in: db, now: now)
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

  private func commitCapturedNote(_ note: HarvestedNote) throws {
    _ = try database.write { db in
      // Menu detail currently shows every day in one scroll and has no selected-day state.
      // Keep the capture placement deterministic; users can move the note after review.
      try MenuRepository.addNoteItem(
        menuID: menuID,
        title: note.title,
        notes: note.body,
        dayOffset: 0,
        mealSlot: .dinner,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }
}

private enum MenuDetailError: Error, CustomStringConvertible, LocalizedError {
  case emptyPrepPlan
  case emptyDepositNote
  case depositTargetMissing

  var description: String {
    switch self {
    case .emptyPrepPlan:
      "The assistant did not find a prep plan to save."
    case .emptyDepositNote:
      "The assistant did not find a note to add."
    case .depositTargetMissing:
      "The deposit target is no longer on this menu."
    }
  }

  var errorDescription: String? { description }
}

enum MenuListStyle {
  case navigation
  case selection
}

struct MenuItemDraftContext: Hashable, Sendable {
  var itemID: MenuItem.ID?
  var menuID: CoreMenu.ID
  var menuTitle: String
  var dayCount: Int
  var kind: MealPlanItemKind = .recipe
  var dayOffset: Int = 0
  var mealSlot: MealPlanItemSlot = .dinner
  var recipeID: Recipe.ID?
  var noteTitle: String = ""
  var notes: String = ""

  var isEditing: Bool { itemID != nil }
}

struct MenuPlacementDraftContext: Hashable, Sendable {
  var menuID: CoreMenu.ID
  var menuTitle: String
  var placementID: MenuPlacement.ID?
  var startDate: Date
  var dayCount: Int
  var minimumDayCount: Int

  var isEditing: Bool { placementID != nil }
}

struct MenuDeletionContext: Identifiable, Hashable, Sendable {
  var menuID: CoreMenu.ID
  var menuTitle: String
  var itemCount: Int
  var placementCount: Int

  var id: CoreMenu.ID { menuID }
}

struct MenuItemDeletionContext: Identifiable, Hashable, Sendable {
  var itemID: MenuItem.ID
  var title: String

  var id: MenuItem.ID { itemID }
}

struct MenuPlacementDeletionContext: Identifiable, Hashable, Sendable {
  var placementID: MenuPlacement.ID
  var menuTitle: String
  var startDate: Date

  var id: MenuPlacement.ID { placementID }
}
