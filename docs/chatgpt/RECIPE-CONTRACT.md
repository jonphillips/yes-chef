# Yes Chef Recipe JSON-LD contract — v2
YC-RECIPE-CONTRACT: v2

Emit exactly one valid schema.org `Recipe` JSON-LD object. Use straight ASCII double quotes (`"`) for all JSON keys and string delimiters. Do not use a Markdown code fence or emit any text outside the JSON object.

Use this base shape:

{"@context":["https://schema.org",{"yesChef":"https://yeschef.app/ns#"}],"@type":"Recipe","yesChef:recipeContractVersion":"2","name":"recipe title","description":"one- or two-sentence summary","recipeCuisine":"cuisine or omit","recipeCategory":"course or omit","recipeYield":"servings or yield, or omit","prepTime":"ISO 8601 duration like PT20M, or omit","cookTime":"ISO 8601 duration like PT35M, or omit","totalTime":"ISO 8601 duration or omit","recipeIngredient":["one ingredient line each"],"recipeInstructions":[{"@type":"HowToStep","text":"one method step each"}]}

`recipeIngredient` is always the complete, ordered flat ingredient list for ordinary schema.org consumers. Do not put section headings such as `For the sauce:` in that list.

If ingredients have meaningful named groups, also include `yesChef:ingredientSections`. It is the authoritative Yes Chef grouping and intentionally repeats the ingredient lines so ordinary schema.org consumers retain the flat list:

"yesChef:ingredientSections":[
  {"name":"For the cabbage","recipeIngredient":["one ingredient line","another ingredient line"]},
  {"name":"For the sauce","recipeIngredient":["one ingredient line"]}
]

Use `HowToSection` only for named instruction groups, with its ordered `HowToStep` entries. For an unsectioned recipe, put ordered `HowToStep` entries directly in `recipeInstructions`; do not make one section per step.

Omit a field you cannot fill confidently rather than inventing it. Do not include IDs, prices, rationale, commentary, or other application metadata.
