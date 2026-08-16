# Yes Chef ChatGPT Project setup

This is the canonical operator guide for Jon's personal Yes Chef ChatGPT Project. It configures the shared external conversation surface used on iPhone, iPad, and the web; it does not change the app or authorize ChatGPT to save anything directly.

## The installed artifacts

Use one shared Project named exactly **`Yes Chef`**. Do not make per-menu or per-recipe Projects: the stable behavior belongs here, while the menu, recipe, and conversation stay in the chat.

| Install location | Version-controlled artifact | Current version |
| --- | --- | --- |
| Project Instructions | [`docs/chatgpt/PROJECT-INSTRUCTIONS.md`](chatgpt/PROJECT-INSTRUCTIONS.md) — paste the entire file, unchanged | hand-off `YC-CONTRACT: v3` |
| Project source file | [`docs/chatgpt/RECIPE-CONTRACT.md`](chatgpt/RECIPE-CONTRACT.md) — upload this file, unchanged | Recipe JSON-LD `v2`; `YC-RECIPE-CONTRACT: v2` |

`RECIPE-CONTRACT.md` is the only required uploaded Project source. `PROJECT-INSTRUCTIONS.md` is pasted into Project Instructions; do not upload it instead of setting the instructions.

The two markers have different jobs. `YC-CONTRACT: v3` is the return-contract marker for routed Yes Chef hand-offs; the app checks it and reports stale Project Instructions. `YC-RECIPE-CONTRACT: v2` identifies the Recipe capture contract. A Recipe capture returns raw schema.org JSON-LD through **Create Recipe**, not a `YC-HANDOFF` response, and does not echo `YC-CONTRACT` or carry a `YC-HANDOFF` token. The v2 extension preserves named ingredient groups in `yesChef:ingredientSections` while retaining the ordinary schema.org flat `recipeIngredient` list.

## Prerequisites

- A signed-in personal ChatGPT account with access to Projects and the ChatGPT app on the devices you use. Projects keep their chats, files, and Project Instructions together and can be continued across devices; see OpenAI's [Projects guide](https://help.openai.com/en/articles/10169521-using-projects-in-chatgpt).
- A current Yes Chef checkout or release that contains the two artifacts above. Do not configure from an old Notes copy, a prior upload, or remembered text.
- The current Yes Chef app, so the **AI** settings screen can provide its two matching copy buttons and Create Recipe can review the result.
- The two `.md` files available in Files/iCloud Drive or on a Mac for the initial upload. They are tiny text files; no export, PDF conversion, or code file upload is needed.

## Set up the Project

1. In ChatGPT, create a Project and name it exactly `Yes Chef`. Give it an icon/color if useful, but do not vary the name.
2. Open the Project's menu, choose **Project settings**, and replace the Project Instructions with the complete contents of [`docs/chatgpt/PROJECT-INSTRUCTIONS.md`](chatgpt/PROJECT-INSTRUCTIONS.md). Save the setting. Do not prepend personal instructions or retain an older Yes Chef instruction block.
3. In the Project's sources/files area, upload [`docs/chatgpt/RECIPE-CONTRACT.md`](chatgpt/RECIPE-CONTRACT.md). This is the required Project source. If an older Recipe contract is present, remove it first rather than leaving both versions available.
4. Open the uploaded source and confirm its first two lines are `# Yes Chef Recipe JSON-LD contract — v2` and `YC-RECIPE-CONTRACT: v2`. Re-open Project settings and confirm the pasted instructions contain `YC-CONTRACT: v3`.
5. Start a new chat from inside the `Yes Chef` Project. Chats created outside the Project do not automatically acquire its files and instructions; move an existing chat into the Project only if it is genuinely part of this cooking conversation.

Project Instructions override global ChatGPT custom instructions inside that Project. If the ChatGPT UI's labels move, use the Project's settings/menu and sources/files area; do not substitute global Custom Instructions.

## iPhone and iPad

The configuration is shared through the ChatGPT account, so it is reasonable to do the initial paste/upload on an iPad or web browser and then use the Project on iPhone. [iPhone and iPad are both supported](https://help.openai.com/en/articles/7993396-chatgpt-ios-app-ipad-support), and Project chats can be continued across devices.

- On iPad, Split View is the least fussy path: Files or this repository on one side, ChatGPT on the other. Long-press a ChatGPT result to copy it; iPad also [supports dragging a generated response into another app](https://help.openai.com/en/articles/7993487-chatgpt-ios-app-ipad-drag-drop).
- On iPhone, keep the Project selected before starting the conversation. When importing, copy the complete JSON response, switch to Yes Chef, and use Create Recipe's **Paste recipe text** control; clipboard permission prompts are expected.
- Do the initial source replacement on the larger screen when possible. A partial selection or a duplicate old file is much harder to notice on the phone.

## Smoke test

Run this once after setup or after an update. It proves the Project source, thin capture request, deterministic import, review gate, and continued conversation all work together.

1. Inside the `Yes Chef` Project, start a chat and agree on a tiny recipe with two ingredient groups and two named method groups.
2. In Yes Chef, open a Menu, choose **Copy Recipe Capture Request**, return to that same ChatGPT chat, and paste/send the request.
3. The response must be exactly one JSON object: no prose or code fence; `@type` is `Recipe`; `yesChef:recipeContractVersion` is `2`; `recipeIngredient` is flat; and `yesChef:ingredientSections` plus `HowToSection` preserve the two named groups.
4. Copy the entire response. In Yes Chef, open **Create Recipe**, use **Paste recipe text**, choose **Extract Recipe**, and review the editable fields. Confirm the title, ingredient groups, instruction groups, times, yield, cuisine/course, and summary that were actually supplied. Save only after the review looks right.
5. Return to the same ChatGPT chat and continue the discussion normally. The successful capture is a durable Recipe product; it does not end or consume the conversation.

If ChatGPT asks which recipe to capture when several are in play, choose one. That is expected and preferable to a guessed import.

## Normal use

1. Start or reopen a chat inside the shared `Yes Chef` Project.
2. Discuss freely: compare approaches, revise quantities, or settle a menu. The conversation has no special output shape while you are deliberating.
3. When the recipe is agreed, use Yes Chef's **Copy Recipe Capture Request** action, paste it into the current Project chat, and send it. It is intentionally thin: it identifies a Recipe and contract version, then relies on the installed Project source for the stable JSON-LD rules.
4. Copy the JSON-only response into **Create Recipe** → **Paste recipe text** → **Extract Recipe**. Yes Chef takes a schema.org Recipe JSON-LD paste through its deterministic extractor first, then opens the ordinary editable review draft.
5. Correct anything needed, accept/reject any suggested categories, and tap **Save**. Nothing is canonical until that save.
6. Return to the same Project chat and keep talking. Capture creates a reviewable recipe; it is not a terminal chat turn.

Expected Project behavior: normal discussion stays conversational; a capture request produces one valid JSON-LD Recipe object and nothing else; uncertain fields are omitted rather than invented; ingredient headings are not fake ingredient rows; and a recipe with no named method groups has direct ordered `HowToStep` values rather than one one-step section per instruction.

## Faster return path with Shortcuts

Create a Shortcut named **Send to Yes Chef** with two actions: **Get Clipboard**, then **Capture a recipe from text** (Yes Chef). Copy a recipe response, run the Shortcut, and Yes Chef opens on Create Recipe with the text extracted for review. Review and tap Save; the Shortcut never creates a recipe by itself.

The ordinary fallback is unchanged: copy the response, open Yes Chef, choose Create Recipe, paste the text, and extract it. The App Intent also makes the action available from Shortcuts, Home Screen, Action Button, and Control Center without a separate Yes Chef UI.

## Outside the Project / universal fallback

Do not rely on the thin **Copy Recipe Capture Request** outside the `Yes Chef` Project: it explicitly expects the Recipe source to be available there. The Project is the preferred durable setup.

For a one-off, non-Project conversation, paste the complete contents of [`docs/chatgpt/RECIPE-CONTRACT.md`](chatgpt/RECIPE-CONTRACT.md) into that chat first, then state which agreed recipe to capture and request only the structured product. Treat that context as single-use: start over with the complete contract in any new chat. Paste the returned JSON into Create Recipe and use the same review flow.

The existing self-contained workbench hand-off prompt remains a separate, task-specific fallback. It is not a substitute for installing the shared Project source for Menu recipe capture.

## Updating an existing Project

When a Yes Chef release or checkout changes either artifact, update both ChatGPT settings deliberately:

1. Pull/open the current repository artifacts; never reconstruct text from memory.
2. Compare the new markers with the Project's installed Instructions and source. If either differs, replace it.
3. In Project settings, select all Project Instructions and paste the entire current [`PROJECT-INSTRUCTIONS.md`](chatgpt/PROJECT-INSTRUCTIONS.md). Save.
4. Remove the old Recipe contract source, then upload the current [`RECIPE-CONTRACT.md`](chatgpt/RECIPE-CONTRACT.md). Do not retain two similarly named versions.
5. Re-run the smoke test before using the Project for a recipe you care about.

The app's **Settings → AI** copy buttons are a useful cross-check: their contents must agree with these artifacts for the matching release. The repository artifacts are the operator install inputs; the app does not reach into ChatGPT to update an already-configured Project.

## Troubleshooting

### Contract mismatch

- For a routed hand-off error saying the instructions are out of date, `YC-CONTRACT: v3` is missing or stale. Replace Project Instructions from [`PROJECT-INSTRUCTIONS.md`](chatgpt/PROJECT-INSTRUCTIONS.md), not just the source file.
- For Recipe capture, check the Project source's `YC-RECIPE-CONTRACT: v2` and JSON field `yesChef:recipeContractVersion":"2"`. The Recipe extractor continues to accept ordinary schema.org JSON-LD, so an old but valid object may import; it can still lose v2-only editorial grouping. Replace the source and capture again before saving.
- Recipe capture is not a routed hand-off. A response starting `YC-HANDOFF:` is the wrong format for Create Recipe; re-send the Recipe capture request in the configured Project.

### Malformed JSON-LD

Copy the complete object, including its opening and closing braces. The contract requires ASCII double quotes and no code fence. Yes Chef can salvage typographic quotes in some pasted JSON, but that is a recovery path, not a format to rely on. If Extract Recipe does not produce the expected deterministic review, ask ChatGPT to re-emit the Recipe using the installed contract, then paste the new object. Do not hand-edit a large malformed payload unless the correction is obvious; review fields remain editable after a successful extraction.

### Missing Project source

If ChatGPT replies with commentary, emits a fence, omits `yesChef:ingredientSections` for a clearly sectioned recipe, or cannot follow the thin request, inspect Project sources. Upload [`RECIPE-CONTRACT.md`](chatgpt/RECIPE-CONTRACT.md), remove old copies, verify its v2 marker, and repeat the capture in a new or continued Project chat.

### Stale Project configuration

Projects can retain both old instructions and old uploaded files. Replace both parts together, then run the smoke test. If ChatGPT presents a same-name upload choice, do not assume it replaced the old source—confirm the source list contains one current Recipe contract. If the problem persists, create a fresh Project named `Yes Chef`, install the two artifacts, smoke-test it, and retire the stale Project only after the new one works.

## Maintainer update rule

Update the Project artifacts and this guide in the same change when any of these change:

- `AIHandoffReturnContract.version`, marker, `projectInstructions`, return ordering, required/forbidden hand-off content, or routed hand-off behavior exposed to the operator.
- `RecipeJSONLDContract.version`, marker, `projectSource`, example, capture-request wording/markers, required Recipe fields, `yesChef:` extensions, or rules for ingredient/instruction grouping.
- `RecipeJSONLDExtractor` or the Create Recipe JSON-LD import/review path changes the operator-visible fields, accepted structure, recovery behavior, or the result that must be reviewed before save.
- The location/name of the Project artifacts, Project naming convention, ChatGPT setup workflow, or device-specific operator flow changes.

For a contract change, update `docs/chatgpt/PROJECT-INSTRUCTIONS.md` and/or `docs/chatgpt/RECIPE-CONTRACT.md` as the exact installable text, keep the matching Core-generated text in sync, revise this guide's versions and smoke test, and update the focused contract/import tests. A code-only parser change that does not alter the operator contract still requires this guide if it changes what the smoke test or troubleshooting promises.
