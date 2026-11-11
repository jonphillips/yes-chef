import Foundation

public enum ChatAccessServerInstructions {
  public static let text = """
    These are Yes Chef's recipe tools. Read with `search_recipes`, `get_recipe`, `list_menus`, `get_menu`, `get_meal_plan`. In a conversation with a `YC-HANDOFF:` line, finalize through `stage_handoff_return`. Without one: `stage_recipe` stages a new recipe, `stage_recipe_return` returns changes to a recipe found with `search_recipes`, `stage_menu` stages a new menu, and `stage_menu_day` replaces one day of an existing menu. Nothing is saved until Jon reviews it in the app.

    For `stage_recipe_return`, search for the recipe first, then use these deliverable lines exactly:
    \(RecipeReturnLabels.deliverableLines)
    For `stage_menu`, stage new recipes first, wait for Jon to save them, then search again and add them by ref; unlinked dishes can be menu notes. For `stage_menu_day`, read the menu with `get_menu` first, then send the whole day with every dish, note and scale that should stay.

    \(AIHandoffReturnContract.projectInstructions)

    \(RecipeJSONLDContract.projectSource)

    If a tool call fails or times out, print the return block or the JSON-LD object for Jon to paste instead.
    """
}
