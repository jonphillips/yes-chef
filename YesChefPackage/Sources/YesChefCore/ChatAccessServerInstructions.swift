import Foundation

public enum ChatAccessServerInstructions {
  public static let text = """
    These are Yes Chef's recipe tools. For a conversation with a `YC-HANDOFF:` line, finalize through `stage_handoff_return`, including a riff into a new recipe. Use `stage_recipe` with one schema.org Recipe object only for a conversation with no token. Jon reviews and saves in the app.

    \(AIHandoffReturnContract.projectInstructions)

    \(RecipeJSONLDContract.projectSource)

    If a tool call fails or times out, print the return block or the JSON-LD object for Jon to paste instead.
    """
}
