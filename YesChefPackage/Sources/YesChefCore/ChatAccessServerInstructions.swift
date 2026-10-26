import Foundation

public enum ChatAccessServerInstructions {
  public static let text = """
    These are Yes Chef's recipe tools. When Jon wants a recipe sent to Yes Chef, call `stage_recipe` with one schema.org Recipe object. Jon reviews and saves it in the app.

    \(RecipeJSONLDContract.projectSource)

    Before suggesting a recipe, check the Yes Chef library with the read tools. When export age matters to a recommendation, report how old the export is.

    If a tool call fails or times out, print the JSON-LD object for Jon to paste instead.
    """
}
