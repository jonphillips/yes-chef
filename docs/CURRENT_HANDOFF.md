# Current Handoff

Last updated: July 1, 2026 (**PR #47 architect-approved → M4 Slice 3 (logical-uniqueness
hardening) is DONE**; on-device sync round-trip now **confirmed** for the main-app capture path
(sim in-app browser capture → device). Next Up = **M4 share-extension iCloud entitlement hotfix**
— the extension crashes on every share because it constructs a `SyncEngine` for a container it
isn't entitled to; must land before the S4 Production flip.

Use this as the short entry point when starting a fresh Yes Chef conversation.
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**Single dispatch target.** Dispatch to the coding agent with:
*"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."* If this section is empty,
missing, or ambiguous, the agent must **STOP and ask Jon — never infer the next
task.** See `docs/AGENTS.md` § Work Intake & Dispatch.

- **M4 (iCloud sync) — share-extension iCloud entitlement hotfix (P1, pre-S4)** — the
  `YesChefShareExtension` crashes on launch on device: the share sheet slides up blank, hangs, and
  dismisses. Root cause: `bootstrapDatabaseForShareExtension()` uses `.configured(startImmediately:
  false)`, which in SQLiteData's `SyncEngine.init` **eagerly** constructs `CKContainer(identifier:)`
  + two `CKSyncEngine`s (`startImmediately:false` only skips the network `start()`, not the
  container build). But `YesChefShareExtension/YesChefShareExtension.entitlements` carries **only the
  app group** — no `com.apple.developer.icloud-container-identifiers`. Building CloudKit objects for
  an unentitled container raises an **ObjC exception**, which the Swift `do/catch` in
  `ShareViewController.viewDidLoad` cannot catch → process crash. This is a **latent S2 gap, not a
  #47 regression** (the extension entitlements haven't changed since M2 S4). Fires on **every** share
  regardless of the sync opt-in, since the extension builds the engine unconditionally.
  **Fix:** add to the extension entitlements the same iCloud keys the app already has
  (`com.apple.developer.icloud-container-identifiers` = `iCloud.com.jonphillips.yeschef`,
  `com.apple.developer.icloud-services` = `[CloudKit]`); keep the app group; **do not** add
  `aps-environment` or a remote-notification background mode (the extension must never take push).
  Confirm the extension's App ID has the CloudKit container capability enabled in the portal (the
  `iCloud.com.jonphillips.yeschef` container already exists — verified in the Dev dashboard).
  `xcodegen generate`, confirm `CODE_SIGN_ENTITLEMENTS` still points at the extension entitlements.
  **Preserve the guardrail:** the extension still constructs with `startImmediately: false` and must
  never call `start()` / network (**construct ≠ run**) — this is entitlement-only, no bootstrap-mode
  change. **Verify (device):** share a recipe from Safari → sheet renders and saves (no crash);
  foreground the app with sync enabled → the shared recipe lands in the Dev Private DB custom zone
  (`co.pointfree.SQLiteData.defaultZone`) and round-trips to a second device. `swift test` +
  `check-drift.sh` (both should be unaffected). Dispatchable now.

M4 Slice 3 — logical-uniqueness hardening (upsert + dedup-on-read) — **DONE** (PR #47,
architect-approved):

- Source-backed `recipeImportRef` duplicates converge on read: pick the earliest ref
  deterministically (`dateCreated` → `id` → `recipeID`), delete duplicate imported recipes, and
  repoint `MealPlanItem`/`MenuItem` (`ON DELETE SET NULL`) + `GroceryItemSource` (no FK) `recipeID`
  references to the survivor before deleting losers (FK cascade cleans the losers' child rows).
  Title-only collisions stay data-preserving (title alone too weak to prove identity). Same
  converge-on-read pattern for duplicate default `GroceryList` (`isDefault`), `PantryItem` titles,
  `Tag` names, and sibling `Category` names (children re-parented to the survivor). Preview path is
  non-mutating. 100 tests green incl. seeded-duplicate `LogicalUniquenessTests`.
- **Non-blocking follow-ups noted in review** (fold into a later slice, not dispatched): default-list
  convergence only self-heals via `ensureDefaultList` (direct `isDefault` readers can briefly show
  two default badges post-sync); the merge relies on GRDB's default `foreign_keys = ON` to clean
  loser child rows (worth a one-line comment at the delete site); the `default:` (>1 matching ref)
  branch in `importBundle` is now dead for source-backed keys.

M4 Slice 2 — CloudKit `SyncEngine` wiring (started OFF) — **DONE** (PR #46, architect-approved):

- Additive CloudKit **dev** entitlements (iCloud container `iCloud.com.jonphillips.yeschef`, CloudKit
  service, `aps-environment`, `UIBackgroundModes = remote-notification`) via XcodeGen.
  `attachMetadatabase()` + `SyncEngine(startImmediately: false)` in `bootstrapDatabase` enumerating
  all 23 synced `@Table`s; iCloud account-status launch gate; sync opt-in defaults **OFF**. Share
  extension **constructs a stopped engine** (`.configured(startImmediately: false)`) purely to
  install triggers / write `SyncMetadata` — it never starts or networks (**construct ≠ run**;
  `bootstrapDatabase` and `bootstrapDatabaseForShareExtension` now differ only by store path).
  `categories.parentCategoryID` loosened from a self-referential FK to a plain UUID column
  (SQLiteData rejects the self-FK as a schema cycle). Drift test derives both sides from the live DB
  (installed sync triggers vs. `sqlite_master` tables) so a new unsynced `@Table` fails the test.
- **On-device dev round-trip — partially confirmed (2026-07-01):** main-app **in-app browser
  capture** round-trips (2 recipes captured on the sim appeared on a second device; record types
  materialized in the Dev Private DB). Enablement is opt-in only (no in-app toggle): set
  UserDefaults `YesChefCloudKitSyncEnabled` / env `YES_CHEF_CLOUDKIT_SYNC_ENABLED=1` / launch arg
  `-YesChefCloudKitSyncEnabled`, on a device signed into iCloud. Dashboard note: synced rows live in
  the **Private** DB custom zone `co.pointfree.SQLiteData.defaultZone` (not Public/`_defaultZone`);
  the console's "Type is not marked indexable" is a query-UI limitation, not a sync failure — record
  types appearing = a successful push.
- **Still owed before S4:** the **share-extension** capture round-trip — blocked on the entitlement
  hotfix above (extension currently crashes before it can write). This is the one link no unit test
  covers: that the main app actually uploads extension-written metadata.

M4 Slice 1 — lean original-provenance — **DONE** (PR #45 merged):

- `RecipeBundleCoding.snapshotData` now strips `originalImportText` and photo `displayData`/
  `thumbnailData` from the snapshot blob (metadata + `imageDataReference` retained); import/capture
  bundle creation defaults `originalImportText == nil` via a test-only `preserveRawImportHTML` seam.
  Transfer `RecipeBundle` untouched (photo bytes still transfer). Snapshot is passive provenance —
  no production consumer of `decodeSnapshot`. Compare-to-original view still deferred to a later slice.

M3 authenticated browser capture — **DONE** (PR #44 merged, `2f5b588`):

- **Capture editorial prose blocks** ("Why This Recipe Works" / "Before You Begin") —
  `docs/efforts/editorial-prose.md`. Scoped DOM scrape (`RecipeEditorialProseExtractor`) mapping the
  blocks to labeled recipe notes, schema-first parser untouched; `WebRecipeEditorialProseTests`.
- **Show & curate notes + hero image in the review UIs** —
  `docs/efforts/share-review-notes-and-image.md`. Notes shown with inline edit + per-block delete,
  plus a read-only hero preview, in **both** the share-extension review (`ShareViewController`) and
  the in-app browser capture review (`RecipeCaptureView`). Emptied notes drop at save/bundle time.

## Ready Efforts (queue)

Drawn into **Next Up** one at a time; this is not a dispatch target.

1. **Early `expectedContentLength` guard on hero download** — `WebRecipeCaptureClient.fetchImageData`
   (`WebRecipeCaptureClient.swift:227`) enforces the 12 MB `maxImageResponseBytes` cap only *after*
   `URLSession.shared.data` has fully buffered the response (`:233→:240`), so it doesn't bound peak
   download memory in the ~120 MB share extension — an oversized body is downloaded in full, then
   rejected. Add a one-line `response.expectedContentLength` pre-check to bail before buffering an
   oversized image. Small, deterministic, no device testing needed. (Supersedes the earlier
   "real-device jetsam check": the decode itself is already memory-safe via
   `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` downsampling in
   `RecipePhotoProcessor`, which never materializes the full-resolution bitmap, so the residual gap
   is the unbounded *download* buffer, not the decode.) Standalone; not on the sync critical path.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort.

**Fork resolved (2026-06-30):** M3 capture is done and the pivot to the **iCloud sync gate** is
made — it's now the active milestone ([`milestones/M4-icloud-sync.md`](milestones/M4-icloud-sync.md),
Phase E). The full build order is authored (S1 lean provenance → S2 CloudKit setup + `SyncEngine`
wiring, off → S3 dedup-on-read hardening → S4 clean cutover/flip → S5 two-device verification).
Modeling stays sync-safe and deferred (no canonical-ingredient work before the flip). Ratified by
[ADR-0010](decisions/ADR-0010-cloudkit-sync-enablement.md); M3 recorded in
[ADR-0009](decisions/ADR-0009-in-app-authenticated-browser-capture.md).

## Current Checkpoint

The current slice scaffolds meal planning, menus, and grocery lists with
source-preserving generated grocery items, a review step before adding generated
ingredients, and first-pass menu/calendar planning polish.

Implemented behavior:

- A durable `mealPlanItems` SQLite table and `MealPlanItem` core model.
- Meal plan items support recipes and freeform notes now, with a reserved
  `reservation` kind and optional start/end time fields for later restaurant or
  iCal-style work.
- A month-first Meal Calendar workspace in the existing app shell, with month,
  week, and day display modes.
- Add recipe/add note flows from the calendar, plus a `Plan` toolbar button on
  recipe detail that starts a preselected recipe plan item.
- A durable menu schema with `menus`, `menuItems`, and `menuPlacements`.
- Menus can contain recipe dishes and freeform notes, be placed on the calendar,
  shifted to a new start date, and removed from the calendar without deleting the
  menu.
- Calendar rows projected from a menu preserve provenance through menu placement
  data and show as menu-derived instead of editable standalone meal plan items.
- A minimal Menus section in the app shell for creating menus, adding dishes, and
  placing a menu on the calendar.
- Menu detail now has a single navigation title, a slide-in recipe browser
  inspector with search/filter controls, day-header add buttons, recipe drops
  from the browser onto a day, and drag-to-move support for menu recipes between
  days.
- Tapping a recipe from menus or the meal-calendar agenda opens the recipe in a
  full-screen presentation.
- The meal calendar now optimistically reflects item date edits/deletes while
  SQLiteData observation catches up, avoiding stale month and agenda counts after
  moving items between days.
- Week calendar cells are taller on wide layouts and allow longer recipe/note
  titles to display.
- A durable grocery schema with `groceryLists`, `groceryItems`, and
  `groceryItemSources`.
- Grocery sources preserve recipe, menu, menu placement, calendar item, and
  custom origins, including source titles/subtitles and original ingredient text.
- A minimal Groceries section in the app shell supports list creation, custom
  items, purchased state, add-from-calendar-range, add-menu, and add-recipe
  flows.
- Recipe detail groups the `Plan` and `Groceries` actions in the toolbar, and the
  groceries action opens a shoppable-ingredient review sheet before adding
  selected lines to the selected/default grocery list.
- Recipe detail shows the `Start Cooking` flame action in the recipe body near
  servings/time instead of in the toolbar.
- Generated grocery ingredients consolidate conservatively when title, unit,
  aisle, notes, and quantity shape are compatible. Compatible numeric quantities
  are added together, while each contributing origin remains represented as its
  own `GroceryItemSource` row.
- Purchased items and prep/comment-sensitive rows stay separate when generating
  groceries.
- Grocery rows expose their source breakdown in the list. Each source now has an
  actions menu that can remove only that source; the repository deletes the
  grocery row when its last source is removed and recalculates generated numeric
  quantities when a consolidated recipe/menu/calendar contribution is removed.
- Recipe detail `Shop`, grocery add-from-calendar-day, and grocery add-menu flows
  now open an ingredient-selection sheet before generating grocery rows. All
  shoppable lines start selected, and the repository can restrict generation to
  selected `IngredientLine` IDs while preserving source provenance and
  consolidation behavior.
- The ingredient-selection sheet now applies conservative pantry assumptions:
  likely staples such as salt, pepper, water, ice, common cooking oils, and
  cooking spray remain visible in a "Skipped Pantry Staples" review section but
  start deselected and can be added back with a tap.
- Settings exposes an editable Pantry list backed by app storage; one item per
  line controls which pantry staples are skipped by default in grocery selection.
- Pantry items sort alphabetically. Pantry quantity tracking remains explicitly
  out of scope; a possible future "Inventory Confirm" grocery-list section would
  need a real measurement normalization layer rather than general pantry
  inventory.
- The meal-calendar recipe picker supports adding multiple recipes in one save.
- Ingredient parsing avoids treating food words like red/celery/anchovy as units,
  splits comma preparations into notes, and normalizes anchovy fillets into the
  shoppable title "anchovies".
- Core tests cover meal calendar, menus, grocery source provenance, generated
  grocery consolidation/source-removal/ingredient-selection/pantry-assumption/
  ingredient-parsing behavior, menu item moves, and alphabetical pantry sorting.

Deferred from this slice:

- Drag/drop or direct manipulation inside the calendar grid.
- Restaurant reservation-specific UI.
- iCal import/export/sync.
- Rich menu editing: editing existing menu dishes, duplicating menus, and
  fine-grained ordering within a day.
- Higher-level source-aware grocery removal flows, such as removing a recipe's
  full contribution from a grocery list without deleting unrelated sources.
- Quantity-based pantry inventory.
- App Intents/Shortcuts implementation. Current low-hanging candidates are:
  open today's calendar, open a recipe, start cooking mode, add a recipe to a
  date defaulting to dinner, add selected recipe ingredients to groceries, and
  add a pantry assumption by name.
- Reminders/Siri integration, store/category learning, and shopping workflow
  polish.
- Importing Paprika menus or grocery lists from backup/export data, if that data
  is recoverable.

## Verification Pattern

Before checkpointing UI work:

- Run `xcodegen generate` after adding Swift source files.
- Build `YesChef` for `iPad Air 13-inch (M4)`.
- Run `scripts/check-drift.sh`.
- Install and launch on both active iOS 27 simulators:
  - `iPad Air 13-inch (M4)`
  - `iPhone 17 Pro`

Jon performs the primary UI testing pass.

Latest verification:

- `swift test --package-path YesChefPackage` passed.
- `xcodebuild -scheme YesChef -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M4)' -skipMacroValidation build` passed.
- Installing/running on both active simulators still needs a follow-up pass;
  `CoreSimulatorService`/`simdiskimaged` became unavailable during the last
  attempt after the iPad build succeeded.

## Strategic Context (not a dispatch target)

> Background only — **not** what the coding agent works on next. Dispatch always comes from
> **Next Up** above. This section captures where the larger work is heading so the architect
> can curate Next Up; it never instructs the agent directly.

Do Jon's primary UI pass on the new menu/calendar planning interactions, then
return to grocery generation and shopping workflow polish around the visible
source model.

Suggested next scope:

- Jon should do the primary UI pass on iPad and iPhone.
- Create a multi-day menu, add recipes via the day header, drag recipes from the
  browser onto days, drag menu recipes between days, place the menu on the
  calendar, shift the placement, remove the placement, and confirm the
  calendar/source relationship remains legible.
- Confirm full-screen recipe presentation from menu rows and meal-calendar agenda
  rows works naturally with the current navigation setup.
- Re-test calendar move/edit flows on adjacent days to confirm the optimistic
  refresh behavior matches the visible month, week, and agenda state.
- Polish the grocery source breakdown if Jon's UI pass finds the per-source
  actions too subtle or too noisy.
- Broaden source-aware removal from the current per-source action into higher-level
  "remove this recipe/menu/calendar contribution" flows where useful.
- Continue pantry polish if Jon's UI pass finds the conservative staple list too
  narrow or too aggressive. Do not build quantity-based pantry inventory as part
  of this slice.
- Treat Grocy as inspiration for shopping locations/assortments and product/barcode
  workflows, but keep Yes Chef recipe/planning-first rather than inventory-first.
- Revisit drag/drop from recipe rows into the calendar or groceries after the
  source model is visible to users.

Reasoning:

- The storage model can now represent multiple origins for one grocery row, and
  the UI has a first review step before generation. The next pressure point is
  making source-aware removal and skipped pantry staples equally legible.
- Paprika's grocery flow allows recipe ingredients to be chosen before adding and
  recipes to be removed from the grocery list later; Yes Chef now has the
  ingredient-selection affordance and still needs the broader removal/review
  affordances while keeping richer provenance intact.
- Source-aware removal is the next pressure test for consolidation because a
  single row may contain quantities from several recipes, menu placements, and
  calendar items.
- Pantry value comes first from making skipped known staples reviewable and easy
  to add back, not from tracking exact on-hand quantities.
- Menu drag/drop is now implemented for menus, but still needs Jon's hands-on UI
  pass across iPad and iPhone before treating it as settled.
