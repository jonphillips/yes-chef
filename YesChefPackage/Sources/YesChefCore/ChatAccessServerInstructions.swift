import Foundation

public enum ChatAccessServerInstructions {
  public static let text = """
    These are Yes Chef's recipe tools. When Jon wants a recipe sent to Yes Chef, call `stage_recipe` with one schema.org Recipe object. Jon reviews and saves it in the app.

    \(RecipeJSONLDContract.projectSource)

    If a tool call fails or times out, print the JSON-LD object for Jon to paste instead.
    """
}
