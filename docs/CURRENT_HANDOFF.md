# Current Handoff

Last updated: July 2, 2026 (**Reader Feedback Slice 3 (PR #56) architect-approved — Slice 4 is now
the Codex dispatch target.** Slice 3 shipped the host-keyed "Load Comments" browser action + bounded
NYT playbook (JS clicks Most Helpful, then "Show more comments" ≤4×) and a pure, fixture-tested
`RecipeReaderCommentExtractor` producing `[RawComment { text, helpfulCount }]`. Architect verified the
substance, not just the green run: the fixture has exactly 76 `note_note__` cards / bodies /
recommendation-count spans (1:1), full-integer counts matching the test's expected values, the single
nested reply keys on a distinct class so it isn't double-counted, and anonymization is *structural* —
the extractor only reads `note_noteBody__ > p` and never touches the `note_noteOwner__` name span.
Keys on stable structure (`#notes_section` + `note_note__` prefix), not drift-prone hash suffixes, as
flagged. Three **non-blocking** notes deferred to Slice 5: (a) the anonymization test is weak —
whole-text `==` to a name, essentially never true; assert `contains` a placeholder substring instead;
(b) `helpfulCount`'s digit-filter would misparse abbreviated `"6.3K"`-style counts — fine for today's
full-integer NYT render, wants a one-line comment on the assumption; (c) the extractor is dormant
(test-only) until Slice 5 wires it into review — expected, not dead code. Prior context: **Reader
Feedback Slice 2 fixture landed** (2026-07-01) — the architect sanitized Jon's authenticated "Most
Helpful, fully loaded" NYT capture (Lemony White Bean Soup) into
`Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/nyt-comments.html` (recipe JSON-LD +
verbatim `<section id="notes_section">`, 76 cards, synthetic commenter names, JSON-LD `review` PII
array dropped, no auth material present). **Reader Feedback Slice 1
(PR #55) architect-approved and merged** —
confirmation-dialog-gated Cancel plus `interactiveDismissDisabled`/`isModalInPresentation` for the
in-app capture sheet and share-extension review, keyed off a new `hasUnsavedReviewChanges`.
Architect review caught a gap before sign-off: the dismiss-guard excluded `isCommitting`, so
swipe-to-dismiss stayed unlocked during the in-flight save/CloudKit-sync-wait even though the
toolbar Cancel button was independently disabled for that state. **The fix (commit `51cfed1`) was
pushed directly to `main` as a follow-up** — it was committed locally but not pushed before PR #55's
merge button was clicked, so the merged PR briefly shipped without it; confirmed fixed on `main` now,
108 tests green. **Next up is Slice 2** — harvesting a real NYT "Most Helpful, fully loaded"
comment-thread DOM fixture — but it's **not yet a Codex dispatch target**: it needs Jon to capture
the post-interaction DOM and hand it to the architect for sanitization first, same pattern as every
prior authenticated-site fixture. Two-device sync dogfooding stays parked — blocked on Apple shipping
iOS Beta 3 and Jon's simulator-pass feedback still marinating — so it isn't gating the next dispatch.)

Use this as the short entry point when starting a fresh Yes Chef conversation.
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**Single dispatch target.** Dispatch to the coding agent with:
*"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."* If this section is empty,
missing, or ambiguous, the agent must **STOP and ask Jon — never infer the next
task.** See `docs/AGENTS.md` § Work Intake & Dispatch.

- **Reader Feedback Slice 4 — Claude API client + Keychain key storage.**
  `docs/efforts/reader-feedback-comment-ingestion.md` §Slice 4. **Now a real Codex dispatch
  target** — Slice 3 landed (see below). First LLM integration and first network-calling,
  key-bearing component in the app. Per `docs/FUTURE_INTELLIGENCE_AND_PLANNING.md` §7.4 the app
  has no server (ADR-0002), so this is a direct client-side call with a personal API key:
  1. A **minimal Claude API client** — plain HTTP call; check whether a package dependency is
     already vendored before adding one. Build it **generically** (reusable infra for other §7.2
     "good AI uses" — make-ahead extraction, substitutions — not comment-triage-specific).
     Default to the latest capable Claude model.
  2. **Personal API key in Keychain**, entered via a new field in the existing `SettingsView`
     (`YesChefApp/RecipeLibraryView.swift:593`).

  **Open question to confirm at dispatch:** whether the client belongs in `YesChefCore`
  (host-testable, no network in tests) or app-layer only, given it's the first network/key-bearing
  component. Lean `YesChefCore` for the pure request/response shaping (testable) with the actual
  `URLSession` call injected, so tests never hit the network — but let the implementer justify.

  **Still parked (not dispatched):**
  - **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook
    from them (phone captures / iPad cooks, which also exercises the untested multi-device
    dedup-on-read convergence). Blocked on Apple shipping iOS Beta 3 (Jon isn't installing an
    earlier beta on his phone); separately, Jon's existing simulator-pass feedback needs a few more
    days to marinate before it should drive scope. Revisit once both land — the most annoying gaps
    found here still choose the real next milestone after Reader Feedback.
  - **Recipe → grocery list w/ pantry checking** — make it slick early (canonical-key merge, static
    pantry thresholds, dialog-free); spec = [[grocery-pantry-threshold-design]] (Phase E). Lower
    priority than Reader Feedback per Jon's stated intent (2026-07-01).
  - Full context in the `post-sync-next-tracks` memory.

Reader Feedback Slice 3 — NYT comment capture playbook + host-keyed extractor — **DONE** (PR #56,
`codex/reader-feedback-comment-playbook`; architect-approved 2026-07-02): host-keyed **"Load
Comments"** action in `BrowserWorkspaceView` (separate from Capture) driving a bounded NYT playbook
(`BrowserCommentLoadingPlaybook` in `RecipeModels.swift` — clicks Most Helpful, then "Show more
comments" ≤4×, keyed on `cooking.nytimes.com`), plus a pure, fixture-tested
`RecipeReaderCommentExtractor` (`YesChefCore`, SwiftSoup, no WebKit) producing
`[RawComment { text, helpfulCount }]`. Architect verified the fixture math (76 cards/bodies/count
spans 1:1, full-integer counts matching the test, distinct-class reply not double-counted) and that
anonymization is structural (reads only `note_noteBody__ > p`, never the owner span). Keys on stable
structure, not hash suffixes. Extractor is intentionally dormant (test-only) until Slice 5 wires it
into review. **Non-blocking follow-ups deferred to Slice 5:** (a) strengthen the anonymization test
(`contains` a placeholder substring, not whole-text `==`); (b) comment the `helpfulCount` digit-filter
assumption that counts render as full integers, not abbreviated `"6.3K"`.

Reader Feedback Slice 2 — harvest the real NYT comment-thread fixture — **DONE** (architect
sanitization step, not a PR/Codex slice; 2026-07-01): Jon captured the authenticated "Most Helpful,
fully loaded" DOM for Lemony White Bean Soup off-device; the architect sanitized it into
`Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/nyt-comments.html` (recipe JSON-LD
+ verbatim `<section id="notes_section">`, 76 cards, synthetic commenter names, JSON-LD `review` PII
array dropped, no auth material present). Real Slice 3 selectors are captured in Next Up above.

Reader Feedback Slice 1 — review-sheet dismiss-fragility hardening — **DONE** (PR #55,
`codex/reader-feedback-review-dismiss-hardening`; architect-approved and merged 2026-07-01):
destructive-confirmation `confirmationDialog` on Cancel plus `interactiveDismissDisabled` (in-app) /
`isModalInPresentation` (share extension) while a draft is under review, both driven by a new
`hasUnsavedReviewChanges` on `RecipeCaptureModel`/`ShareCaptureModel`. Architect review found
`hasUnsavedReviewChanges` excluded `isCommitting`, leaving swipe-to-dismiss enabled during the async
save (and, in the share extension, through the `waitForPendingRecordZoneChanges` sync wait) even
though the toolbar Cancel button was independently disabled for that state — a mid-save swipe could
let the user dismiss while the import still completed in the background and later popped an
unexpected `.captureSummary` sheet. Fixed by dropping the redundant `!isCommitting` clause (it can
only be `true` while `draft != nil`, so it added no protection, only the gap) — landed as commit
`51cfed1` directly on `main` since it was committed locally but not pushed before the PR merge
button was clicked. 108 tests pass, swiftlint clean.

Web-capture cleanup slice — **DONE** (PR #54, `codex/web-capture-cleanup-nits`; architect-approved
and merged 2026-07-01): `WebRecipeCaptureClient.fetchImageData` now streams the hero-image download
via `URLSession.bytes(for:)`, rejecting on a declared-oversized `Content-Length` before reading the
body and enforcing the 12 MB cap against actual bytes received (covers unknown/inaccurate
Content-Length too, not just the declared-header case the original ask specified).
`RecipeMilkStreetExtractor.extractPrintIngredients`/`extractBodyIngredients` collapsed into one
`extractIngredients` helper parameterized by an `IngredientExtractionSelectors` struct; heading/item
lines are buffered and only committed to the builder once a real item is found in that pass, closing
the orphan-heading-leaks-into-body-fallback gap from the PR #53 review. Also picked up the
`RecipePrintTemplate_ingredientRow__*` print-row markup fallback alongside `ingredientItem__*`. Non-
blocking follow-up noted in review (not filed as a task): the hero-image download iterates
`URLSession.AsyncBytes` one byte at a time, which is slower than a chunked read — worth revisiting
if hero-image hydration is ever visibly slow in practice.

Milk Street print-template ingredient headings — **DONE** (PR #53,
`codex/milk-street-print-ingredient-headings`; architect-approved and merged 2026-07-01): the
print-template ingredient path now recognizes `RecipePrintTemplate_ingredientHeading__*` rows
interleaved with `ingredientItem__*` rows, walking heading/item elements in DOM order so section
names attach before their items instead of silently falling through to body-only heading support.
`milk-street-chicken-peanut.html` extended with real-shape print-template markup so the existing
section assertion exercises this branch. Architect review found two non-blocking nits (orphan-
heading fallback gap, extract-print/extract-body duplication) — folded into Next Up above rather
than blocking merge.

Milk Street sections/Tip/summary/time — **DONE** (PR #52, `codex/milk-street-sections-tip-summary`;
architect-approved 2026-07-01, merged): real per-recipe summary (`RecipeSummaryContent_body__*`)
outranking site-boilerplate meta description, Tip callout captured as an editorial block
(`[role=note][aria-label=Tip]`), servings/prep/cook/total time from `ItemLabelList_item__*`, and a
`RecipeDurationParser` unicode-vulgar-fraction normalizer (`"1½ hours"` → 90 min) — all fixture-
tested against a sanitized `milk-street-chicken-peanut.html`. **Architect review found the fourth
gap (ingredient subsection headings) was a branch-selection bug, not a missing-markup limitation** —
fixed in PR #53 above.

Revive DEBUG DOM export — **DONE** (PR #51, `codex/revive-debug-dom-export`; architect-approved
2026-07-01, merged): `preserveRawImportHTML: true` gated `#if DEBUG` at both production capture call
sites, Release stays lean (PR #45 intent preserved).

Milk Street parser hardening — **DONE** (PR #50, `codex/milk-street-parser-hardening`;
architect-approved 2026-07-01, merged): meta-tag JSON-LD reading gated on truncation-sentinel
detection, a `RecipePrintTemplate_*`/`RecipeBodyContent_*` DOM fallback extractor
(`RecipeMilkStreetExtractor`, amount+description join, empty-amount tolerant), the new
`truncatedStructuredData` warning, and sanitized recovered/truncated-only fixtures. Correctly
scoped to the original gochujang reference capture; NYT teaser regression stays green.

M4 — share-extension iCloud sync (producer wait + consumer re-drain + enablement persistence) —
**DONE** (PR #49, `codex/m4-share-extension-pending-upload`; architect-approved 2026-07-01, round-trip
confirmed on device). Three defects, one landable unit:
  1. **Producer race (Codex):** stopped extension engine defers the `PendingRecordZoneChange` insert to
     a fire-and-forget `Task` that `completeRequest` killed → row lost. `ShareCaptureModel.saveButtonTapped`
     now bounded-polls `pendingRecordZoneChangeCount` until the row lands before completing. No
     `start()`/networking/`aps-environment` in the extension (guardrail intact).
  2. **Consumer drain (Codex):** the pending table only drains inside `start()`
     (`enqueueLocallyPendingChanges`, `SyncEngine.swift:645`), which no-ops when already `isRunning`.
     Added a scene-`.active` foreground re-drain that cycles `stop()`+`start()` when pending rows exist.
  3. **Enablement gate (folded in directly, 2026-07-01):** the real reason device testing kept failing —
     `isManuallyEnabled` was set only by the volatile Xcode launch-arg, so an icon-tap / extension-handoff
     launch had sync OFF and neither the cold-launch `start()` nor the re-drain ever ran. Proven by reading
     the sim metadatabase: 81 undrained `PendingRecordZoneChange` rows == 81 metadata rows with NULL
     `lastKnownServerRecord`, table never cleared → `start()` had not run since the extension wrote.
     `persistManualEnablementFromLaunchEnvironment()` (called in `YesChefApp.init()` before
     `startIfManuallyEnabled`) mirrors the dev flag into persistent `UserDefaults` so non-Xcode launches
     stay enabled. See [[extension-sync-construct-not-run]].
  Follow-ups deferred (not blocking): file the upstream SQLiteData issues — (a) persist the pending change
  in the trigger synchronously (existing `// TODO` at `SyncEngine.swift:823-838`), (b) expose a public
  "drain persisted pending changes into a running engine" entrypoint so consumers needn't stop/start.
  Before the S4 Production flip, replace the dev launch-arg gate with a real persisted opt-in (the
  enablement fix is a dev-ergonomics bridge, not the GA toggle).

M4 — share-extension iCloud entitlement hotfix — **DONE** (PR #48 merged, `5e8be14`):

- Added the iCloud container + CloudKit-service entitlements to `YesChefShareExtension` (app group
  preserved; no `aps-environment` / background modes). Fixes the launch crash: `SyncEngine.init`
  eagerly builds `CKContainer(identifier:)` even with `startImmediately: false`, and an unentitled
  container threw an uncatchable ObjC exception (blank share sheet → hang → dismiss). Entitlement-only,
  no bootstrap-mode change; stable across `xcodegen` (referenced via `CODE_SIGN_ENTITLEMENTS`).
- **Crash fixed, but round-trip still broken** — device testing during review found the extension
  saves locally but never uploads (see Next Up: the stopped-engine `PendingRecordZoneChange` is
  deferred to a Task that `completeRequest` kills). #48 was the necessary first half, not the whole
  slice.

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

- **Dogfood fixes — batch 1 (bugs + near-term UX)** —
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md). Jon's first
  dogfooding pass (2026-07-02): 3 verified bugs (add-sheet-doesn't-present-over-full-screen-recipe,
  add-to-meal has no confirmation / wrong target, archived recipes invisible with no restore/purge)
  + 6 small self-contained UX wins (browser clear-URL, recipe-list search reachability, share
  grocery as text, edit a grocery item, direct ×2/×3 recipe multiplier, add image to a manual
  recipe). **Jon's instruction (2026-07-02): this whole batch is the next set of efforts once
  Reader Feedback Slice 4 is architect-approved** — promote it into Next Up then, bugs (Slices 1–3)
  first. Not a dispatch target until that approval lands.

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
