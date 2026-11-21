# Open Questions

> **The executor never reads this file** (jon-platform ADR-0005). It is the architect's and Jon's scratch
> pad; work becomes dispatchable only when a plan PR sets `docs/NEXT_UP.md`.

## Candidates

**Siri AI tool intents — wait for the release, not the beta (Jon and the architect, 2026-11-16).** Apple's Siri AI
developer preview ([news](https://developer.apple.com/news/?id=gdk2umrf),
[docs](https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri)) lets Siri
call an App Intent marked `@AppIntent(.tool)` from natural speech, across apps. It's 27.3-beta only, and only for
dev-signed and internal-TestFlight builds. Jon isn't running betas, so revisit when Siri AI ships to customers ("a few
months" from 2026-11-03) and App Store submission opens (spring 2027). Re-read the docs first, because the API may change.
- **Cheap:** mark `CaptureRecipeFromText` as a tool and add a description to `rawText`, so "save this recipe to Yes
  Chef" works from Safari or Messages.
- **A milestone, not cheap:** "what's for dinner Tuesday?" or "find my chili recipe" need real recipe, menu and
  meal-plan entities, indexed in Spotlight, with a description on each property. The MCP tools (`search_recipes`,
  `get_meal_plan`, …) already map out that surface.
- **Not tools:** `ExportHandoffContext`, `ImportHandoffResult` and the handoff entities. They're ChatGPT-handoff plumbing.

**Per-recipe facet/tag coverage is Jon's ongoing hand work and gates nothing** — Power Browser (ADR-0050)
and everything downstream move forward without waiting on it.

**Parked briefs (ADR-0005 D10 archive sweep, 2026-10-30).** Designed but not scheduled. Each brief sits in
`efforts/archive/`. Restore one to the root, restated `Designed` or `Ready`, in the plan PR that schedules it.

- **Import-review warnings share IDs, so rows drop (from the #31 review, 2026-06-29; still on `main` 2026-11-21).**
  `PaprikaImportReviewView` uses `ForEach(…, id: \.message)`, but the `titleOnlyCollision` and
  `ambiguousImportIdentity` messages don't name the recipe. So two or more collisions in one export get duplicate IDs,
  and SwiftUI drops rows. Fix: key the rows by `title` plus `kind`, or something unique. In the same file's
  `rollbackImportedRecipes`, the category loop calls `RecipeCategory.fetchAll(db)` once per category. Fetch it once,
  and add a comment saying that "batch-created" means `importDates.contains(dateCreated)`.
- **Cookbook payload photo columns are hand-listed (2026-11-14, #519).** `CookbookPayloadPhotoRow` names every
  `RecipePhoto` column but `displayData`; a new column silently misses cookbook payloads. Add it there, or add a guard.
- **Flaky `CookbookPublishModelTests.publishWaitsForLibrarySyncThenRunsOnceRescheduled` (2026-11-15, #530).** It
  checks `progressText == nil` as soon as the fake's profile save lands, but the model still awaits
  `client.fetchProfile()` before clearing it. Failed 2 of 3 isolated runs on #530's branch, which doesn't touch
  publishing. Wait for the model's own completion instead of the fake's save count.
- **Top `safeAreaInset` bars may hide large titles (2026-11-13)** on Workbenches, Recipes, Browsers. Check on device.
- **Ingredient parser splits inside a parenthetical (2026-11-12).** The Pumpkin Pie butter
  item's notes read "3/4 stick) cold unsalted butter, cut into 1/4-inch slices", so a line like "6 tablespoons
  (3/4 stick) cold unsalted butter, cut into…" was split inside the parentheses. Reproduce from the stored line first;
  a fix re-parses nothing by itself. Fold into the next import slice.
- **Prepared components** ([brief](efforts/archive/prepared-components.md), [ADR-0057](decisions/ADR-0057-prepared-components.md)) —
  a `Recipe.kind` and a directional dish → component edge. Additive schema, so it's safe after the cut. Nothing forces it sooner.
- **ATK "Gather Your Ingredients" repair** ([brief](efforts/archive/import-text-normalization.md), parked by Jon
  2026-11-15) — 101 ingredient lines and 70 section names across 171 recipes are page chrome, so any of them on a
  menu puts "Gather your ingredient" on the grocery list. Delete the lines; clear the section names but keep the
  sections (`ON DELETE CASCADE`). It must be a backup-first, post-engine pass: a repair in the migrator uploads
  nothing ([[migration-writes-bypass-sync-triggers]]). P2 (Milk Street all-caps) is declined. Revisit after
  Thanksgiving; until then, delete a stray grocery line by hand.
- **Tandoor idea harvest** ([notes](efforts/archive/tandoor-idea-harvest.md)) — the alias rows graduated to
  [ADR-0069](decisions/ADR-0069-ingredient-name-fixes.md). Still parked: the `{base, form, prep}` ingredient model and
  the never-unit / transpose-words / site-scoped rules. Read before the next ADR they touch.
- **In-app browser Passwords autofill** ([spike](efforts/archive/browser-passwords-autofill-spike.md)) — the
  2026-07-08 spike defending ADR-0009's "never store credentials." First confirm autofill still fails.
- **iPad recipe editor as a cookbook page (2026-10-13).** Ingredients and Instructions side by side on wide layouts,
  instead of stacked `Form` sections. It needs a custom layout (not `Form`), so it was kept out of
  `calendar-rail-and-editor-columns`. It pairs naturally with that effort's adaptive-row helper.

**Name-fix parameters still default to `.empty` (found 2026-11-12, reviewing #502).** ADR-0069 D6 renamed
`canonicalName` so the compiler would find every key comparison. But `PantrySuppression.evaluate`,
`WorkbenchCompare.ingredientComparison`, `GroceryPantryAssumptions.isPantryStaple`,
`GroceryIngredientChoice.isAssumedPantryStaple(pantryStaples:)`, `GroceryStoreArea.seed(for:)`,
`CanonicalIngredient.compoundParts` and `GroceryGeneratedItemDraft.init` take `fixes: IngredientNameFixes = .empty`.
So a new caller that forgets the argument compiles and silently skips your fixes. Every caller in #502 was checked and
is correct; the `seed(for:)` callers pass names that are already fixed. Fix: drop the defaults and have tests pass
`.empty` explicitly. Do it the next time a dispatch touches these files.

**Make-ahead dishes pull their groceries onto the Advance trip (ADR-0068, Later).** A dish whose prep starts before the Fresh trip needs its perishables bought on the Advance trip (pie, stock). The prep plan knows each dish's work days. It needs a Fresh-trip date: take it from the menu's calendar placement plus a "Fresh trip: N days before" setting on the split (ADR-0039 Amd 1, date over toggle), not calendar entries for trips. Pick up after Jon's Thanksgiving 2026 shop shows whether it's needed.

**Add Menu and Bring In don't place copied steps by time (found 2026-11-11, reviewing #490).** `MenuBringIn` appends
copied prep steps after the target's existing steps instead of placing them with `PrepPlanPlacement`. So when a target
day already has timed steps, the copied ones read after them, out of time order, until the next weave re-sorts the
plan. The #490 brief left this path out. Fix: place each copied step in turn, as `replace` does. It matters once a
timed menu is added into another timed menu.

**A staged menu opened on both devices at once can be created twice (found 2026-11-10, reviewing #473).**
Create Menu writes the menu and then claims the `.ycmenu` file, as the brief specified. Claiming first would lose the
staged menu if the write then failed. If the iPhone and iPad both open the review before either claims, both can
create the menu; the second device's `alreadyClaimed` is swallowed. It needs one person reviewing on two devices in
the same minute. Revisit if a duplicate menu ever shows up: claim first and restore the file on a failed write.

**Editing a Serve With suggestion should protect it from regeneration (Jon decided 2026-11-15).**
`RecipeServeWithRepository.update` leaves `provenance` at `.model`, so an edited suggestion no longer matches and
`replaceModelSuggestions` deletes it on the next regeneration. ADR-0048 meant regeneration to keep the cook's work;
ADR-0062 protects linked rows only. An edit now protects the row too. The design question for the brief: how a row
records "edited", without misusing provenance as "touched".

**A calendar day gets a real plan (decided 2026-11-05, not scheduled).** Replaces the make-ahead note that saves the whole
strategy as one block of text. Jon chose a new date-keyed synced table that shares Menu's bands and views, and expects light
use, so keep it cheap. The design and the questions for a brief are in
[ADR-0034 Amendment 1](decisions/ADR-0034-prep-plan-work-session-timeline.md#amendment-1--a-calendar-day-gets-a-real-plan-2026-11-05).

**"Up to date" can't see inbound records that never arrived (found 2026-10-27, PROD-CUTOVER Step 4 audit).**
The iPhone read "Up to date" while missing 199 `ingredientLines` that the iPad had. Sync status counts only a
device's own unsent or unapplied rows, so a record that was never delivered is invisible to it. The open question
is whether status should also compare against the server (per-type server counts) or offer a "check for missing
records" pass. Related: [[no-dead-data]] (sync status must never stay quietly green).
**Three more blind spots (found 2026-10-28, PROD-CUTOVER Step 9),** all in CloudSyncKit's status inputs:
- The pending count reads `sqlitedata_icloud_pendingRecordZoneChanges`, which SQLiteData fills only while the
  engine is stopped. While it runs, the queue lives in CKSyncEngine's own state, so a full re-seed reads 0 pending.
- The not-uploaded scan is skipped while the engine is sending, and it ignores rows changed in the last 30
  minutes. A skipped scan reports nothing, which reads as "Up to date".
- `nextRecordZoneChangeBatch` stores the locally built record as `lastKnownServerRecord` before sending (no
  change tag), so a save CloudKit later drops looks sent to any check that doesn't require a change tag.

The fix is a jon-platform CloudSyncKit slice (Galavant shares it): show "Syncing…" or the last scan's result
instead of green when the scan is skipped, and count the engine's real queue.

**Can SQLiteData 1.13.0 replace the vendored copy? (updated 2026-11-19).** The patched copy (ADR-0056 Amd 2) keeps
children of parents the server never confirmed. Since #532 (2026-11-18) it's the shared one in jon-platform's
`Vendor/sqlite-data` (its notes are in `PATCH.md`), which Urbane overrides with too. It was waiting on
[pointfreeco/sqlite-data#548](https://github.com/pointfreeco/sqlite-data/pull/548), which closed **unmerged**
on 2026-11-04; issue #547 is still open, and point-free said they're reworking quota detection. 1.13.0 (2026-11-09)
ships `quotaExceeded` handling (#335), batch sorting against reference violations (#571) and a `@Fetch` load
cancellation fix (#536). Next step: check whether 1.13.0 covers #547's repro; if it does, return to the remote
package and remove the `project.yml` override (and Urbane's, in the same change).

**Migration baseline squash — optional, post-cut, both apps (deferred by ADR-0056 Amd 1).** Use GRDB
`registerMigration(_:merging:)`. The precondition is that every device is at the final legacy migration.
Also raise `declaredSchemaVersion` so older backups still restore. It's tidiness only: fresh installs stop
replaying the repair migrations and the ones that call live app code. Galavant (43 migrations) would do the
same.

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) leftovers — two unbuilt slices.** The measurement
arc is closed ([[restore-is-authoritative]]); restore is authoritative **only against settled peer state**. Do
**not** re-run the measurement.
- **Enforce the restore procedure (scope with Jon).** A peer's unsent or held delete that syncs *after* a restore
  silently re-deletes the restored record on every peer (OQ6). Restore must walk the user through *quiesce every
  peer (delete the app) → restore and re-enable on one device → reinstall the peers.* Verify once that deleting the
  app clears the app-group container; the whole mitigation rests on it.
- **S3 — automatic snapshots.** Local-only, keep N. **Build the pre-migration snapshot first** (D4): a rolling
  snapshot taken right before `migrator.migrate` runs, the cheapest catch for the
  [[debug-erase-vs-sync-triggers]] class of bug. App-update and periodic snapshots follow.
- **Loose end — file a point-free bug report:** SQLiteData never clears `_isDeleted` in `upsertFromServerRecord`
  (and `syncChanges` sends before it fetches), the root of OQ6. Check 1.13.0's conflict fix (#574) first.

**Small follow-ups — fold into a passing dispatch:**
- **The Adjust extractor's prompt is framed for a conversation, but it's handed a decision** (silent
  under-extraction). `HandoffReviewCoordinator.draftRecipeAdjustment` wraps a finished brief as one `.user`
  message, while the instructions describe a cooking conversation the user is asking to review, so a decided
  revision reads as an in-progress ask; a 3-change brief yielding 2 ops just looks shorter. *Fix:* a task-specific
  framing for the brief path, not a second client.
- **`stageReaderFeedback` defaults `unparsedLines` to `[]`**, so accepting a single tip through the *in-app*
  path clears the evidence banner (cosmetic).
- **Calendar complement review validation has no test through the real builders (2026-11-06).** `validateText`
  decides whether Add is enabled, but no test calls it on an item from `MealCalendarModel.makeApplyActions` or
  `HandoffReviewCoordinator.mealPlanComplementReviewItems`. In
  `mealCalendarChatCollectionCommitPreservesEditedComplementsThroughEditDraft` and
  `externalMealPlanHandoffCommitPreservesEditedComplementThroughEditDraft`, assert that
  `validationMessage(for: unmodifiedApprovedText)` is `nil` and that the text without its placement line returns a
  message.

## Parked topic notes

Long topic threads moved out of this file on 2026-10-30, so it stays readable whole. Each
link opens the notes as written.

- **Comment ingestion** — [parked notes](efforts/archive/comment-ingestion.md). Pull top-ranked reader comments into a recipe as tips, NYT first. The capture DOM doesn't carry them, and comments are third-party content with PII constraints.
- **Recipe relationships** — [parked notes](efforts/archive/recipe-relationships.md). Suppression, variation, and collection are three primitives, not one. Open: split §22A into two entities or keep one, with list multi-select as the shared prerequisite.
- **Recipe normalization ("normalize recipe")** — [parked notes](efforts/archive/recipe-normalization.md). A one-tap normalize that strips manual instruction numbers (the all-caps de-cap is the declined P2). Unscoped; sequence it with ADR-0014.
- **In-app capture: per-site playbooks and review-UX sturdiness** — [parked notes](efforts/archive/in-app-capture-playbooks.md). Two linked threads anchored to the in-app `WebPage` browser (ADR-0009). Post-sync.
- **Sync: migration writes bypass the sync triggers** — [parked notes](efforts/archive/sync-migration-writes.md). A migration write to a new table duplicates per device; to an existing table it never uploads. Unverified on device: whether the 2026-07-14 prep-plan move duplicated steps. Read it before any migration that writes rows.
- **Dogfood notes, July 2026** — [parked notes](efforts/archive/dogfood-notes-2026-07.md). Findings from the 2026-07-02/03 and 07-09 passes: ingredient authoring, the chat and reader, the menu planner. Some have shipped since, so check DONE-LOG.md before acting on one.
- **Menus and the planning model** — [parked notes](efforts/archive/menus-planning-model.md). Menu vs meal plan vs cooking plan, and the 2026-07-02 dogfood asks: dated menus on the planner, searchable guests, multi-add groceries from a calendar day.
