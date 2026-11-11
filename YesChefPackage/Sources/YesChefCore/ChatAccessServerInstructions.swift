import Foundation

public enum ChatAccessServerInstructions {
  public static let text = """
    These are Yes Chef's recipe tools. Read with `search_recipes`, `get_recipe`, `list_menus`, `get_menu`, `get_meal_plan`. In a conversation with a `YC-HANDOFF:` line, finalize through `stage_handoff_return`. Without one, stage a new recipe (`stage_recipe`), changes to a recipe (`stage_recipe_return`), a new menu (`stage_menu`), one day of a menu (`stage_menu_day`), or the prep plan for some of a menu's dishes (`stage_prep_plan`). Nothing is saved until Jon reviews it in the app.

    For `stage_recipe_return`, search for the recipe first, then use these deliverable lines exactly:
    \(RecipeReturnLabels.deliverableLines)
    For `stage_menu`, stage new recipes first, wait for Jon to save them, then search again and add them by ref; unlinked dishes can be menu notes. For `stage_menu_day`, read `get_menu` first and send the whole day. For `stage_prep_plan`, read `get_menu` first, send every step for each dish you name, and keep steps to tasks.

    \(AIHandoffReturnContract.projectInstructions)

    \(RecipeJSONLDContract.projectSource)

    If a tool call fails or times out, print the return block or the JSON-LD object for Jon to paste instead.
    """
}
