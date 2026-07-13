import Foundation
import SQLiteData

/// Grocery generation: build grocery items + provenance sources from recipes,
/// planned meals, menus, and menu placements. Split out of GroceryCore.swift to keep
/// the GroceryRepository declaration within house size limits (no behavior change).
extension GroceryRepository {
  @discardableResult
  public static func addRecipe(
    recipeID: Recipe.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let recipe = try requireRecipe(recipeID, in: db)

    return try addRecipeIngredients(
      recipe: recipe,
      groceryListID: groceryListID,
      source: GroceryItemSourceDraft(
        origin: .recipe,
        sourceTitle: recipe.title
      ),
      in: db,
      now: now,
      uuid: uuid,
      includedIngredientLineIDs: includedIngredientLineIDs
    )
  }

  @discardableResult
  public static func addMealPlanItem(
    itemID: MealPlanItem.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let item = try requireMealPlanItem(itemID, in: db)
    guard item.kind == .recipe, let recipeID = item.recipeID else {
      throw GroceryRepositoryError.mealPlanItemHasNoRecipe(itemID)
    }
    let recipe = try requireRecipe(recipeID, in: db)

    return try addRecipeIngredients(
      recipe: recipe,
      groceryListID: groceryListID,
      source: GroceryItemSourceDraft(
        origin: .calendarItem,
        mealPlanItemID: item.id,
        scheduledDate: item.scheduledDate,
        mealSlot: item.mealSlot,
        sourceTitle: recipe.title,
        sourceSubtitle: item.mealSlot.title
      ),
      in: db,
      now: now,
      uuid: uuid,
      includedIngredientLineIDs: includedIngredientLineIDs
    )
  }

  @discardableResult
  public static func addMenuItem(
    itemID: MenuItem.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    guard let item = try MenuItem.find(itemID).fetchOne(db) else {
      throw GroceryRepositoryError.menuItemNotFound(itemID)
    }
    guard item.kind == .recipe, let recipeID = item.recipeID else {
      throw GroceryRepositoryError.menuItemHasNoRecipe(itemID)
    }
    let menu = try requireMenu(item.menuID, in: db)
    let recipe = try requireRecipe(recipeID, in: db)

    return try addRecipeIngredients(
      recipe: recipe,
      groceryListID: groceryListID,
      source: GroceryItemSourceDraft(
        origin: .menu,
        menuID: menu.id,
        menuItemID: item.id,
        mealSlot: item.mealSlot,
        sourceTitle: menu.title,
        sourceSubtitle: recipe.title
      ),
      in: db,
      now: now,
      uuid: uuid,
      includedIngredientLineIDs: includedIngredientLineIDs
    )
  }

  @discardableResult
  public static func addMealPlanRows(
    _ rows: [MealPlanItemRowData],
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)

    var itemIDs: [GroceryItem.ID] = []
    for row in rows {
      guard row.item.kind == .recipe, let recipeID = row.item.recipeID else { continue }
      let recipe = try requireRecipe(recipeID, in: db)
      let source: GroceryItemSourceDraft

      if let menu = row.menu,
         let menuPlacement = row.menuPlacement,
         let menuItem = row.menuItem {
        source = GroceryItemSourceDraft(
          origin: .menuPlacement,
          mealPlanItemID: nil,
          menuID: menu.id,
          menuItemID: menuItem.id,
          menuPlacementID: menuPlacement.id,
          scheduledDate: row.item.scheduledDate,
          mealSlot: row.item.mealSlot,
          sourceTitle: menu.title,
          sourceSubtitle: recipe.title
        )
      } else {
        source = GroceryItemSourceDraft(
          origin: .calendarItem,
          mealPlanItemID: row.item.id,
          scheduledDate: row.item.scheduledDate,
          mealSlot: row.item.mealSlot,
          sourceTitle: recipe.title,
          sourceSubtitle: row.item.mealSlot.title
        )
      }

      do {
        itemIDs += try addRecipeIngredients(
          recipe: recipe,
          groceryListID: groceryListID,
          source: source,
          in: db,
          now: now,
          uuid: uuid,
          includedIngredientLineIDs: includedIngredientLineIDs
        )
      } catch GroceryRepositoryError.noShoppableIngredients {
        continue
      }
    }

    guard !itemIDs.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }
    return itemIDs
  }

  @discardableResult
  public static func addMenu(
    menuID: Menu.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let menu = try requireMenu(menuID, in: db)
    let menuItems = try MenuItem
      .where { $0.menuID.eq(menuID) }
      .fetchAll(db)
    let items = menuItems
      .filter { $0.kind == .recipe && $0.recipeID != nil }
      .sorted(by: areMenuItemsInIncreasingOrder)

    var itemIDs: [GroceryItem.ID] = []
    for menuItem in items {
      guard let recipeID = menuItem.recipeID else { continue }
      let recipe = try requireRecipe(recipeID, in: db)
      do {
        itemIDs += try addRecipeIngredients(
          recipe: recipe,
          groceryListID: groceryListID,
          source: GroceryItemSourceDraft(
            origin: .menu,
            menuID: menu.id,
            menuItemID: menuItem.id,
            mealSlot: menuItem.mealSlot,
            sourceTitle: menu.title,
            sourceSubtitle: recipe.title
          ),
          in: db,
          now: now,
          uuid: uuid,
          includedIngredientLineIDs: includedIngredientLineIDs
        )
      } catch GroceryRepositoryError.noShoppableIngredients {
        continue
      }
    }

    guard !itemIDs.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }
    return itemIDs
  }

  @discardableResult
  public static func addMenuPlacement(
    placementID: MenuPlacement.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let placement = try requireMenuPlacement(placementID, in: db)
    let menu = try requireMenu(placement.menuID, in: db)
    let menuItems = try MenuItem
      .where { $0.menuID.eq(menu.id) }
      .fetchAll(db)
    let items = menuItems
      .filter { $0.kind == .recipe && $0.recipeID != nil }
      .sorted(by: areMenuItemsInIncreasingOrder)
    let calendar = Calendar(identifier: .gregorian)

    var itemIDs: [GroceryItem.ID] = []
    for menuItem in items {
      guard let recipeID = menuItem.recipeID else { continue }
      let recipe = try requireRecipe(recipeID, in: db)
      let scheduledDate = calendar.date(
        byAdding: .day,
        value: menuItem.dayOffset,
        to: placement.startDate
      )
      do {
        itemIDs += try addRecipeIngredients(
          recipe: recipe,
          groceryListID: groceryListID,
          source: GroceryItemSourceDraft(
            origin: .menuPlacement,
            menuID: menu.id,
            menuItemID: menuItem.id,
            menuPlacementID: placement.id,
            scheduledDate: scheduledDate,
            mealSlot: menuItem.mealSlot,
            sourceTitle: menu.title,
            sourceSubtitle: recipe.title
          ),
          in: db,
          now: now,
          uuid: uuid,
          includedIngredientLineIDs: includedIngredientLineIDs
        )
      } catch GroceryRepositoryError.noShoppableIngredients {
        continue
      }
    }

    guard !itemIDs.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }
    return itemIDs
  }
}
