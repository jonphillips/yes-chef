import Foundation

/// The versioned Recipe product contract used by Project-aware external conversations.
///
/// This is intentionally a Recipe-specific value, not a general conversation-product envelope. The
/// app continues to accept ordinary schema.org JSON-LD without this extension through the same
/// deterministic parser.
public enum RecipeJSONLDContract {
  public static let version = "2"
  public static let marker = "YC-RECIPE-CONTRACT: v\(version)"

  /// The exact Project source the cook uploads to a Yes Chef ChatGPT Project.
  public static let projectSource = """
    # Yes Chef Recipe JSON-LD contract — v\(version)
    \(marker)

    Emit exactly one valid schema.org `Recipe` JSON-LD object. Use straight ASCII double quotes (`"`) for all JSON keys and string delimiters. Do not use a Markdown code fence or emit any text outside the JSON object.

    Use this base shape:

    \(example)

    `recipeIngredient` is always the complete, ordered flat ingredient list for ordinary schema.org consumers. Do not put section headings such as `For the sauce:` in that list.
    Never put `HowToSection`, `itemListElement`, or any other objects inside `recipeIngredient`.

    If ingredients have meaningful named groups, also include `yesChef:ingredientSections`. It is the authoritative Yes Chef grouping and intentionally repeats the ingredient lines so ordinary schema.org consumers retain the flat list:

    "yesChef:ingredientSections":[
      {"name":"For the cabbage","recipeIngredient":["one ingredient line","another ingredient line"]},
      {"name":"For the sauce","recipeIngredient":["one ingredient line"]}
    ]

    Use `HowToSection` only for named instruction groups, with its ordered `HowToStep` entries. For an unsectioned recipe, put ordered `HowToStep` entries directly in `recipeInstructions`; do not make one section per step.

    Omit a field you cannot fill confidently rather than inventing it. Do not include IDs, prices, rationale, commentary, or other application metadata.
    """

  /// The self-contained product rules for a universal handoff that cannot rely on a Project source.
  static let outputInstructions = """
    Return one valid schema.org `Recipe` JSON-LD object, and nothing else. Use straight ASCII double quotes (`"`) for every JSON key and string delimiter. Do not use a Markdown code fence.

    \(example)

    When ingredient groups matter, keep `recipeIngredient` as the complete ordered flat list and add `"yesChef:ingredientSections":[{"name":"group name","recipeIngredient":["ingredient line"]}]`. Do not put ingredient section headings, `HowToSection`, `itemListElement`, or other objects into `recipeIngredient`.

    Use `HowToSection` only for named instruction groups. For an unsectioned recipe, use ordered `HowToStep` entries directly in `recipeInstructions`; do not make one section per step. Omit any field you cannot fill confidently rather than inventing it. Do not put IDs, prices, or rationale inside the JSON.
    """

  /// A compact Project-aware request. It deliberately carries no `YC-HANDOFF` token: raw Recipe JSON-LD
  /// returns through Create Recipe, while that token names a single-use task-specific handoff row.
  public static func captureRequest(recipeName: String? = nil) -> String {
    let subject = recipeName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let target = if let subject, !subject.isEmpty {
      "Capture the current agreed version of \"\(subject)\" from this conversation for Yes Chef."
    } else {
      "Capture the current agreed recipe from this conversation for Yes Chef. If more than one recipe is in play, ask me which recipe to capture rather than guessing."
    }
    return """
    YC-PRODUCT: Recipe
    \(marker)

    \(target)
    Use the current Yes Chef Recipe JSON-LD contract available in this Project.
    Return only the structured product.
    """
  }

  private static let example = """
    {"@context":["https://schema.org",{"yesChef":"https://yeschef.app/ns#"}],"@type":"Recipe","yesChef:recipeContractVersion":"\(version)","name":"recipe title","description":"one- or two-sentence summary","recipeCuisine":"cuisine or omit","recipeCategory":"course or omit","recipeYield":"servings or yield, or omit","prepTime":"ISO 8601 duration like PT20M, or omit","cookTime":"ISO 8601 duration like PT35M, or omit","totalTime":"ISO 8601 duration or omit","recipeIngredient":["one ingredient line each"],"recipeInstructions":[{"@type":"HowToStep","text":"one method step each"}]}
    """
}
