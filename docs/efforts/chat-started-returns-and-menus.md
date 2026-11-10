# Effort — Chat-started recipe returns and `stage_menu`

Status: Ready
Summary: Two new MCP staging tools for a chat that starts in ChatGPT. `stage_recipe_return` sends labeled changes back to a recipe found with `search_recipes`. `stage_menu` stages a new menu of library recipes and note rows. The helper resolves each read ref when it stages. The app lists the new inbox items, opens a recipe return in the existing `.recipe` review, and opens a menu in a review sheet that has one Create Menu button.

Origin: Jon planning a Thanksgiving dinner in ChatGPT (2026-11-10). One dispatch, one PR. **No schema change.**

Decisions: [ADR-0060 Amendment 2](../decisions/ADR-0060-chat-access-over-mcp.md#amendment-2--a-chat-that-starts-in-chatgpt-can-return-to-a-recipe-and-stage-a-menu-2026-11-10)
(D1–D6; read it first). Builds on Amd 1 (`stage_handoff_return`, the token-routed inbox) and
[ADR-0061](../decisions/ADR-0061-one-recipe-handoff.md) (the `.recipe` task and its labeled return).
Related: [archived chat-access brief](archive/chat-access-mcp.md) (S3a/S3b are the closest precedent) ·
[ADR-0036](../decisions/ADR-0036-promote-note-to-recipe.md) (note → recipe swap) ·
[[menu-item-recipe-id-invariant]] in `MenuRepository`.

## Where things are (architect, 2026-11-10, `origin/main` f29343f)

**Helper (`YesChefMCP/Sources/YesChefMCPServer/`)**
- `YesChefMCPServer.swift`: `stage_recipe` and `stage_handoff_return`, `StageContext`, the staging folder.
- `ChatAccessReadTools.swift`:
  - Read refs are `<generation>.r<index>` / `.m<index>`, and `resolveIndex` rejects an old generation.
  - `ChatAccessExportStore` is built **inside** `ChatAccessReadTools.make`. The staging tools can't see it yet.
  - `snapshot.value.recipes[i].recipe` is the full `Recipe` row, so it has `id`, `title`, `archived`,
    `makeAhead` and `chefItUp`.
- **Tests** (`YesChefMCP/Tests/YesChefMCPTests/YesChefMCPTests.swift`):
  - `stagingToolDescriptionsCarryTheHandoffRouting` is commented "ChatGPT doesn't put server instructions in
    front of the model, so the tool descriptions must route on their own." **That makes each tool's description
    the real carrier for the rules below. The instructions are the backup.**
  - `containsUUID` asserts that no tool output leaks an id.

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `ChatAccessServerInstructions.swift`: the server's instructions (Amd 2-D6 replaces the opening).
- `AIHandoffContext.swift`, about line 70, `prompt(forTask: .recipe)`: the labeled-deliverable lines
  (`YC-REVISION:` … `YC-LEARNINGS:`).
- `AIHandoffIntentImport.swift`:
  - `stageReview(handoffID:result:in:now:allowRestage:)` is at about line 86.
  - `labeledRecipeReview` parses `.recipe` returns, including the `YC-NEW-RECIPE:` must-stand-alone rule.
- `AIHandoff.swift`:
  - the `AIHandoff` row: `exportedPrompt: String` and `status`;
  - `AIHandoffRepository.create(_:in:)` at about line 438;
  - `acceptsRepeatReturns` at about line 88.
- `ChatAccessInbox.swift`: `rows(from:)` lists only `json`, and `returnRows(from:resolve:)` lists only
  `ycreturn`. Add new projections next to them.
- `ChatAccessExport.swift`: `ChatAccessExportCoding`, the versioned decode that fails loudly. Copy its pattern
  for the two new envelopes.
- `MenuCore.swift`: `MenuRepository.addMenu`, `addRecipeItem` and `addNoteItem`.
  - `addRecipeItem` already rejects a missing or archived recipe.
  - Neither item function takes `scale`. Use `RecipeScaleCore.setScale(_:for: .menuItem(id), in:)`.

**App (`YesChefApp/`)**
- `ChatAccessInboxFileClient.swift`: the `ChatInboxItemKind`s (`json`, `ycreturn`), `claim`, and `maintain`.
- `ChatAccessInboxModel.swift`:
  - `open(_ ReturnRow)` is the model for "stage, present, then claim."
  - `loadName` is the model for reading a title out of a file.
- `ChatAccessInboxView.swift`: the **From Chat** list.
- `AppIntents/HandoffIntents.swift`, about line 763: `HandoffAppOperations.stageReview` wraps Core's in
  `database.write`.
- `HandoffReviewCoordinator.presentStaged(_:toastCenter:)` presents a staged review.
- `RecipeCollectionReviewSheet.swift`: the ADR-0026 collection sheet. Follow its look for the menu review.
- `MenuModels.swift`, about line 68: `selectedMenuID` (selecting a menu).

**jon-platform `ChatAccessKit` / `LLMHandoffKit`:** `ChatInboxItemKind` matches by extension. `HandoffInbox.stage`
lowercases the slug, and `UUID(uuidString:)` still parses it. **No change to either package.**

## S4 — `stage_recipe_return` (Amd 2-D1, D2, D3, D6)

### Core

- **The shared label block.** Move the `YC-REVISION:`, `YC-MAKE-AHEAD:`, `YC-CHEF-IT-UP:`, `YC-SERVE-WITH:` and
  `YC-LEARNINGS:` lines out of `prompt(forTask: .recipe)` into one constant, for example
  `RecipeReturnLabels.deliverableLines`.
  - `YC-NEW-RECIPE:` and its stand-alone sentences stay in the prompt **only**, not in the constant.
  - The prompt composes the constant back in, and its wording must not change. Reordering lines so
    `YC-NEW-RECIPE:` sits outside the block is fine.
  - Test: the `.recipe` prompt and the `stage_recipe_return` description both contain the constant.
- **The staged envelope.** Add `ChatAccessStagedRecipeReturn`, `Codable`:
  - Fields: `format` (`"yc-recipe-return"`), `version` (1), `recipeID`, `recipeTitle`, `text`.
  - Coding fails loudly on an unknown format or a newer version, the way `ChatAccessExportCoding` does.
  - The helper and the app share it.
- **Staging the review.** Add `ChatRecipeReturnImport.stageReview(_ envelope:, in db:, now:, uuid:) throws -> AIHandoffReview`:
  1. Require that the recipe exists and isn't archived. Otherwise throw a typed `recipeUnavailable`.
  2. Create an `AIHandoff` with:
     - `sourceType .recipe`, `sourceID` the recipe, `taskType .recipe`;
     - `dayOffset nil`, `variationID nil`, `regenerates false`, `exportedPrompt ""`;
     - status `.awaitingReturn`, `createdAt now`, and the current `schemaVersion`.
  3. Call `AIHandoffIntentImport.stageReview(handoffID:, result: envelope.text, in: db, now:)`.

  The caller runs it in **one write transaction**. A body that fails to parse (for example `emptyPlan`) rolls
  back the new row too.
- **Instructions.** Use Amd 2-D6's opening verbatim. Add a short paragraph for `stage_recipe_return` (search first,
  then the label block) and one for `stage_menu` (D5's recipe-first order). Keep the existing contract text after
  them.
  - Update the 512-character opening test to require all four staging tool names.

### Helper

- **One export store.** Read and staging tools share one `ChatAccessExportStore`, so a ref resolves against the
  same cached generation that issued it. Add a resolver that reuses `resolveIndex` and returns
  `(id, title, archived)` for a recipe ref.
- **`stage_recipe_return`.** Input `{ref: string, text: string}`, both required, `additionalProperties: false`.
  Annotations `readOnly false, destructive false, openWorld false`.
  - **Description:** use it to send changes to a recipe found with `search_recipes`. Don't use it in a
    conversation with a `YC-HANDOFF:` line (that's `stage_handoff_return`). A new dish goes through
    `stage_recipe`. Then add the label block. One call per recipe; several calls are fine.
  - **Checks**, in this order. Each one returns `isError` and stages nothing.
    - **The ref is stale, missing, or isn't a recipe ref:** reuse the read tools' messages ("That reference is
      from an older export; search again." / "…isn't a recipe…").
    - **The recipe is archived:** "That recipe is archived in Yes Chef."
    - **`text` is empty after trimming:** "There's nothing to stage."
    - **A line starts with `YC-HANDOFF:`:** "This conversation has a hand-off token; finalize with
      `stage_handoff_return`."
    - **A line starts with `YC-NEW-RECIPE:`:** "A new dish goes through `stage_recipe`, not
      `stage_recipe_return`."

    The body itself isn't parsed here. The app parses it (Amd 2-D2).
  - **File:** `HandoffInbox(root: inbox, fileExtension: "ycrecipereturn")`, with slug `recipeID.uuidString` and the
    encoded envelope as its contents.
  - **Result:** `{staged: <recipe title>, next: "Jon reviews it in Yes Chef → From Chat."}`. **No id.**
- **`stage_recipe`'s description** gains one clause: changes to a recipe already in the library go through
  `stage_recipe_return`.
- **`get_recipe`** adds `makeAhead` and `chefItUp`, both optional strings, taken from the exported `Recipe` row. No
  export version change.

### App

- **The inbox kind.** Add `ycrecipereturn` as a `ChatInboxItemKind` with `expiresUnclaimed: false` and
  `datesProcessedByClaim: false`, the same as `json`, because any device may claim it. Add it to `maintain` and
  `claim`.
- **Rows.** Add `ChatAccessInbox.recipeReturnRows(from:resolve:)`, keyed by the slug's UUID.
  - **The recipe resolves (live, not archived):** the row is openable, titled **"Changes · <live recipe title>"**.
  - **It doesn't:** the row reads **"Recipe not found on this device"** and offers **Discard** only. It's never
    claimed automatically. The recipe may still be syncing in.
  - Rows sort by `stagedAt`. Every file is its own row, with no newest-per-recipe collapsing. That matches
    `.recipe`'s `acceptsRepeatReturns`.
  - `inboxCount` includes openable rows.
- **Opening a row:**
  1. Read and decode the envelope. A decode error shows on the row, and the file stays.
  2. In one `database.write`, run `ChatRecipeReturnImport.stageReview`.
  3. `presentStaged(AIHandoffReviewResult(review:, warning: nil))`.
  4. Then claim.

  This is the same order as `open(_ ReturnRow)`. A `.recipeNew` review can't happen, because the helper rejects
  `YC-NEW-RECIPE:`. Treat it as a stage error if it ever does.
- **Discard** claims the file.
- **Check every place that lists or labels `AIHandoff` rows.** A row whose `exportedPrompt` is empty must render.
  `ReturnRow.title` already falls back to `taskType.title`, and anything else must too.

### Tests

**Helper**
- Stage and decode an envelope.
- No UUID in any result.
- A stale ref.
- A menu ref given as a recipe ref.
- An archived recipe.
- Empty text.
- A `YC-HANDOFF:` line.
- A `YC-NEW-RECIPE:` line.
- `get_recipe` returns the Playbook fields.
- Extend the description-routing test to cover the new tools.

**Core**
- The envelope round-trips, and a newer version fails.
- `stageReview` against a live recipe gives `.recipeItems`, with one `AIHandoff` row created and imported.
- An archived recipe throws, and no row is created.
- An empty body rolls back the row.
- The label-block drift test.
- The new opening test.

**App**
- `recipeReturnRows`: openable vs not found, and the ordering.

## S5 — `stage_menu` (Amd 2-D4, D5)

### Core

- **The staged envelope.** Add `ChatAccessStagedMenu`, `Codable`, with `format` (`"yc-menu"`), `version` (1), `title`,
  `dayCount`, and `items`. Each item has:
  - `recipeID: UUID?`;
  - `title` (the export's title for a recipe item, the model's title for a note item);
  - `dayOffset`, `slot: MealPlanItemSlot`, `note: String?`, `scale: Double?`.

  It fails loudly the way S4's envelope does.
- **`ChatMenuImport`:**
  - `resolve(_ envelope:, in db:) -> [ResolvedItem]` marks each item as `.libraryRecipe(recipeID)`, `.newDish`, or
    `.recipeMissing`.
    - `.recipeMissing` means it had a `recipeID` but the recipe is missing or archived here. It's written as a note
      row with the recorded title.
  - `create(title:, dayCount:, items:, in db:, now:, uuid:) throws -> Menu.ID` makes one call to `addMenu` (with
    `notes: nil`), then `addRecipeItem` / `addNoteItem` for each kept item in input order, then `setScale` for each
    recipe item that has a scale. The caller wraps it in one write.
  - Never produce a `.recipe` item without a resolved id. That's the invariant.

### Helper

- **`stage_menu`.** Input `{title, days?, items}`, where each item is `{ref?, title?, day?, slot?, note?, scale?}`.
  Use `additionalProperties: false` at both levels. The `slot` schema is an enum of `MealPlanItemSlot` raw values.
  Annotations are the same as S4's.
  - **Description:** stages a **new** menu for Jon to review.
    - An item with a recipe ref from `search_recipes` is a library recipe. One without a ref is a new dish, shown
      as a note row.
    - `day` is 0-based, as in `get_menu`.
    - To get a new recipe onto the menu as a recipe: stage it with `stage_recipe`, wait for Jon to save it, search
      again, then stage the menu with its ref.
    - The menu can't add to an existing menu.
  - **Validation** (each returns `isError` and stages nothing):
    - The title isn't empty.
    - `items` has 1 to 40 entries.
    - `days` is 1–14 (default 1), and each `day` (default 0) is inside it.
    - `slot` defaults to `dinner`.
    - A note is at most 500 characters.
    - `scale` is greater than 0 and appears **only on ref items** ("Scale applies to a library recipe.").
    - An item without a ref has a non-empty `title`.
    - Every ref resolves to a live recipe in the current export, with the same messages as S4.

    Ref items ignore the model's `title`. Report every invalid item in one message, by index, so the model fixes
    them all in one retry.
  - **File:** `HandoffInbox(root: inbox, fileExtension: "ycmenu")`, with the slug taken from the title.
  - **Result:** `{staged: <title>, recipes: n, newDishes: m, next: "Jon reviews it in Yes Chef → From Chat."}`. No ids.

### App

- **The inbox kind.** Add `ycmenu`, configured like `json`.
- **Rows.** Add `ChatAccessInbox.menuRows`, titled **"Menu · <title>"**. Read the title from the file the way
  `loadName` does, and fall back to the slug.
- **Opening a row** reads and decodes the file, runs `resolve`, and presents a new `ChatMenuReviewSheet`. It
  doesn't claim. The sheet takes the collection sheet's look, but has **one** commit, because the menu is one
  write.
  - **Contents:** an editable title, and the day count, shown only when it's more than 1.
  - **Rows,** grouped by day and slot. Each row has its title, its note, its scale when it isn't 1, and a badge:
    **In your library**, **New dish**, or **Not on this device, adding as a note**. Each row has a keep toggle,
    on by default.
  - **Create Menu** is disabled when the title is empty or no rows are kept. It runs `ChatMenuImport.create` in one
    write, then claims the file, posts the toast **"Menu created."**, and selects the new menu
    (`selectedMenuID`).
  - **Cancel** leaves the file in the inbox.
- **Discard** from the inbox claims the file.

### Tests

**Helper**
- Every validation error, including the multi-item report.
- The recipe-or-note mapping in the staged file.
- No UUIDs in results.

**Core**
- The envelope round-trips, and a newer version fails.
- `resolve` gives all three cases.
- `create` writes the right kinds, days, slots, notes, and scales, keeps input order, and **never** writes a
  recipe row without an id.
- A failure partway through writes nothing.

**App**
- `ChatMenuReviewModel`, or whatever owns the sheet: keep toggles, the title rule, commit and then claim, and
  Cancel not claiming.

## Verification and completion

- **Schema:** none. The new `AIHandoff` rows go in an existing local table, and menus use existing tables.
- **Package:** focused tests, then `scripts/check-drift.sh`.
- **Helper:** `swift test --package-path YesChefMCP`.
- **App:** the generic device build, and the **`YesChefTests`** target, because inbox model code changes. Exact
  commands are in [verification.md](../verification.md). Run every build and test elevated from the first attempt.
  A sandbox-shaped failure gets one elevated rerun. If an elevated run fails, stop and report.
- **Install order** (put it in the PR body for Jon): update the app on both devices, then run
  `scripts/install-yeschef-mcp` and restart the tunnel, per `CHATGPT-SETUP.md` § reinstall. Update
  `CHATGPT-SETUP.md`'s tool list.
- **Closeout** per ADR-0005 D16. This dispatch archives the brief.
- **Gate (Jon; iPhone, then iPad):** a ChatGPT chat **outside** the `Yes Chef` Project.
  1. Search the library and pick two recipes.
  2. Send a `YC-REVISION:` and a `YC-MAKE-AHEAD:` for one of them with `stage_recipe_return`. On the iPhone, it
     opens in the `.recipe` review, and Draft the revision works.
  3. Stage one new recipe and save it. Chat searches again and stages a menu with the two library recipes, the new
     recipe by ref, and one new dish as a note. The menu review shows the right badges, and Create Menu opens the
     menu.
  4. On the iPad, those items are gone from **From Chat**.
  5. A stale ref, made by backgrounding Yes Chef between a search and a stage, comes back "search again," and the
     retry works.

## Dispatch ledger

- [ ] Dispatch 1 — S4 + S5, one PR. No schema.
