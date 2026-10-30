# Open Questions

> **The executor never reads this file** (jon-platform ADR-0005). It is the architect's and Jon's scratch
> pad; work becomes dispatchable only when a plan PR sets `docs/NEXT_UP.md`.

## Candidates

**Per-recipe facet/tag coverage is Jon's ongoing hand work and gates nothing** — Power Browser (ADR-0050)
and everything downstream move forward without waiting on it.

**Parked briefs (ADR-0005 D10 archive sweep, 2026-10-30).** Designed but not scheduled. Each brief sits in
`efforts/archive/`. Restore one to the root, restated `Designed` or `Ready`, in the plan PR that schedules it.

- **Prepared components** ([brief](efforts/archive/prepared-components.md), [ADR-0057](decisions/ADR-0057-prepared-components.md)) —
  a `Recipe.kind` and a directional dish → component edge. Additive schema, so it's safe after the cut. Nothing forces it sooner.
- **ATK "Gather Your Ingredients" repair** ([brief](efforts/archive/import-text-normalization.md)) — P1 only, a
  backup-first data pass; see the fuller candidate below.
- **Tandoor idea harvest** ([notes](efforts/archive/tandoor-idea-harvest.md)) — reference notes mined from Tandoor
  Recipes. Nothing ratified; read before the next ADR they touch.
- **Commit authority as a typed, test-enforced property** ([review](efforts/archive/application-actions-review.md) D1) —
  the one new track from the 2026-08-02 application-actions review, never built. OQ1 (where the declaration lives) is open.
- **In-app browser Passwords autofill** ([spike](efforts/archive/browser-passwords-autofill-spike.md)) — the
  2026-07-08 spike defending ADR-0009's "never store credentials." First confirm autofill still fails.
- **Full-screen moves the app tabs to the top** ([dogfood 2026-09-21](efforts/archive/dogfood-fixes-2026-09-21.md)
  Thread F) — the one thread from that pass not confirmed in code. Check on device before scoping.

From the old Next Up:

- **"Up to date" can't see inbound records that never arrived (found 2026-10-27, PROD-CUTOVER Step 4 audit).**
  The iPhone read "Up to date" while missing 199 `ingredientLines` (19 recipes from the 2026-07-08 import) that
  the iPad had. Sync status counts only a device's own unsent or unapplied rows, so a record that was never
  delivered is invisible to it. The cut repairs this iPhone, because Step 11 fresh-installs it from Production.
  The open question is whether status should also compare against the server (per-type server counts, as
  Reference B does by hand) or offer a "check for missing records" pass like Slice 5's leftover check. Decide
  after the cut. Related: [[no-dead-data]] (sync status must never stay quietly green).
  **Three more blind spots (found 2026-10-28, PROD-CUTOVER Step 9),** all in CloudSyncKit's status inputs:
  - The pending count reads `sqlitedata_icloud_pendingRecordZoneChanges`, which SQLiteData fills only while the
    engine is stopped. While it runs, the queue lives in CKSyncEngine's own state, so a full re-seed reads 0 pending.
  - The not-uploaded scan is skipped while the engine is sending, and it ignores rows changed in the last 30
    minutes. A skipped scan reports nothing, which reads as "Up to date".
  - `nextRecordZoneChangeBatch` stores the locally built record as `lastKnownServerRecord` before sending (no
    change tag), so a save CloudKit later drops looks sent to any check that doesn't require a change tag.

  The fix is a jon-platform CloudSyncKit slice (Galavant shares it): show "Syncing…" or the last scan's result
  instead of green when the scan is skipped, and count the engine's real queue. Do it after the cut.

- **Launch-time repair passes run on the main thread on every launch (found 2026-10-28).** `bootstrapDatabase`
  (`Schema.swift`, the `runsPostEngineDataPasses` block) runs in `YesChefApp.init`, before the first frame:
  `reparseIngredientRanges` loads and parses all ~27,600 lines, `RecipeSyncRepair` decodes every recipe's
  `lastKnownServerRecord`, and the cuisine/course and variation-anchor backfills scan every recipe. All of it runs
  in one write transaction. The app is unresponsive for 5 seconds or more at launch. Make each pass run once
  (gated by a stored version) or retire the finished ones, and run what's left off the main thread. Do it after
  the cut, with a TestFlight build.

- **Settings' Sync detail sheet slides up, then straight back down (Jon, 2026-10-29; long-standing).** Tapping
  the Sync row usually takes a second tap. The likely cause: `SyncStatusSection` hangs `.sheet(isPresented:)` on
  its `Section` inside the Settings `Form` (`SyncStatusSection.swift`), so the presentation lives on a lazy,
  List-backed row. The row re-renders whenever `SyncHealthModel` ticks, which is often while the engine runs,
  and that can dismiss the sheet. Fix: hoist the sheet's state and `.sheet` out to the `Form` in `SettingsView`,
  and leave the row as a plain button. It's the only sheet in Settings; the other detail views push and are
  fine. Small, post-cut; bundle with the next polish dispatch.

- **Drop the vendored SQLiteData when upstream fixes #547.** `Vendor/sqlite-data` (ADR-0056 Amd 2) exits when a
  SQLiteData release keeps children of parents the server never confirmed. Watch
  [pointfreeco/sqlite-data#548](https://github.com/pointfreeco/sqlite-data/pull/548). Return to the remote package
  then, and remove the `project.yml` override.

- **Migration baseline squash — optional, post-cut, both apps (deferred by ADR-0056 Amd 1).** Use GRDB
  `registerMigration(_:merging:)`. The precondition is that every device is at the final legacy migration.
  Also raise `declaredSchemaVersion` so older backups still restore. It's tidiness only: fresh installs stop
  replaying the repair migrations and the ones that call live app code. Galavant (43 migrations) would do the
  same.


- **iPad recipe editor as a cookbook page (2026-10-13).** Ingredients and Instructions side by side on wide layouts,
  instead of stacked `Form` sections. It needs a custom layout (not `Form`), so it was kept out of
  `calendar-rail-and-editor-columns`. It pairs naturally with that effort's adaptive-row helper.

- **ADR-0045 cold-start starters are still open, no longer time-gated:** S2 rearranged the Calendar day-header
  Chat and the Workbench Chat into inspectors and left them passing `.none`. Whether they want their own starters
  ("Plan this week" / "What should I prep tonight?") is Jon's call whenever — it no longer blocks anything.


**Prior candidates (queue — not the designated target).** Per-recipe facet/tag coverage is Jon's ongoing hand
work (Edit Tags + DEBUG Facet Coverage) that **gates nothing**.

The ATK grocery-bug slice ([`efforts/archive/import-text-normalization.md`](efforts/archive/import-text-normalization.md)) is a
**data migration wanting backup-first + a device pass** — hold it until Jon is local. D3's settled
hidden-vocabulary rule lives in ADR-0049 D11.

Drawn into **Next Up** as needed; not itself a dispatch target. Completed efforts live in
[`docs/DONE-LOG.md`](DONE-LOG.md).

**[`efforts/archive/import-text-normalization.md`](efforts/archive/import-text-normalization.md) — ATK's "Gather Your
Ingredients" is a latent grocery bug (scoped 2026-07-28). P1 only; **no schema**.** 101 shoppable ingredient
lines + 70 section names across **171 recipes** are page chrome captured as content, all canonicalizing to
one key, so any of those recipes on a menu puts "Gather your ingredient" on the grocery list.
- **Delete, do not de-cap.** Lines: delete the row. Sections: **clear the name, keep the section**
  (`sectionID` is `ON DELETE CASCADE` — dropping it takes every ingredient with it).
- **⚠️ Needs the post-engine pass** ADR-0014 Amd1-D3 described and dodged at 10 rows: a repair in the migrator
  uploads nothing and each device diverges, and **the 101 deletes are unrepeatable** — a delete that never
  uploads stays alive in CloudKit and any full-zone fetch resurrects it
  ([[migration-writes-bypass-sync-triggers]]). Back up first.
- **P2 (Milk Street's all-caps) is DECLINED**; P3's Amd1-D1 dependency is now discharged (shipped 2026-07-28)
  but it stays parked behind the declined P2. Don't build either on momentum.

**ADR-0045 leftovers — two cold-start entry points, each its own small slice.** The meal-calendar day-header
Chat and the Workbench Chat, same dead end, no section to carry. Recorded in the ADR, deliberately not folded
into V1. **Open for Jon:** now that starters are host-supplied, do the Calendar and Workbench want starters of
their own ("Plan this week", "What should I prep tonight?")? **ADR-0046 S2 has now rearranged both into
inspectors and left them passing `.none`** — an explicit answer, not an omission — so the timing pressure is
gone; decide whenever, it blocks nothing.

**ADR-0041 deferred follow-ons** (on the record, **not** dispatchable without Jon scoping them) — the **menu**
Playbook sections getting the same per-section toolbar, and section-selection checkboxes on the whole-recipe
hand-off (the scoped per-section verbs make these *less* necessary, not more).

**Meal-Planner chat verbs** (ADR-0013 + `efforts/archive/cooking-workspace.md`) — the one remaining named
actionable-chat verb instance. Classify each verb's commit shape first ([[chat-verb-commit-shapes]]) — likely
no-commit advisory or a per-day note, not a per-recipe write; respect [[llm-curation-not-synthesis]].
**Confirm with Jon what verb scope remains.**

**Recipe text normalization** — strip manual instruction numbers now that we auto-number (Milk Street
all-caps de-cap is the DECLINED P2 above). **Unscoped**; parked in
[`docs/open-questions.md`](open-questions.md). Interacts with ADR-0014, so sequence them.

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) leftovers — two unbuilt slices.** The measurement
arc is closed (OQ1/5/6/7 → DONE-LOG + [[restore-is-authoritative]]); the net covers a lost/blank zone and
restore is authoritative **only against settled peer state**. Do **not** re-run the measurement. Two things
remain to build, plus one upstream loose end:
- **⚠️ NEW SLICE — enforce the restore procedure (scope with Jon).** Naive restore is unsafe: a peer's
  unsent/held delete that syncs *after* a restore silently re-deletes the restored record on every peer (OQ6,
  measured E2E). Restore must gate on / walk the user through *quiesce every peer (delete the app → drops its
  unsent CKSyncEngine queue) → restore + re-enable on one device → reinstall the peers.* Verify once (throwaway
  install) that deleting the app clears the app-group container — the whole mitigation rests on it.
- **S3 — automatic snapshots.** Cadence/trigger + retention (keep N), local-only. **Build the pre-migration
  snapshot first** (D4): a rolling local snapshot taken right before `migrator.migrate` runs, so a bad/erasing
  migration is always recoverable from the step before it — the single cheapest catch for the
  [[debug-erase-vs-sync-triggers]] class of bug. App-update-boundary and periodic snapshots follow.
- **Loose end — file a point-free bug report:** upstream SQLiteData tombstone handling never clears
  `_isDeleted` in `upsertFromServerRecord` (and `syncChanges` sends before it fetches), which is the root of the
  OQ6 data-loss path above.

**Small nits — not urgent, fold into a passing dispatch:**
- **The S4 brief extractor's prompt is framed for a conversation, but S4 hands it a decision** (silent-failure
  risk). `instructions` says *"extract … from a cooking conversation … the user is asking to review"* while
  `HandoffReviewCoordinator.draftRecipeAdjustment` wraps a finished brief as one fake `.user` message
  (`selection: ""`) — so a **decided** revision reads as an **in-progress ask** and the extractor hedges, and
  under-extraction is silent (a 3-change brief yielding 2 ops just looks shorter). *Fix:* a task-specific
  framing for the brief path, **not** a second client, and **not** taste profile / known-learnings into the
  extractor (those belong to the outbound ask).
- **Workbench log-editor** (ADR-0042 S2 review): the `canSave` / `normalizedLogEntryDraft` mismatch when a body
  is combined with partially-filled typed fields, the dead save spinner, the compare `.menuPrepPlan` mislabel.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip);
  spec in [`efforts/archive/recipe-workbench.md`](efforts/archive/recipe-workbench.md). ⚠️ Re-read against ADR-0042 D2/OQ5
  first: it is an *in-app* draft verb and the draft is a structured write.
- **`stageReaderFeedback` defaults `unparsedLines` to `[]`**, so accepting a single tip through the *in-app*
  path clears the evidence banner (cosmetic).

**Still-deferred, separate future efforts:** ADR-0027 **OQ4** (a note-worthiness taste preference);
**ADR-0036 S3** — promote a `RecipeNote` deposited *on a recipe*; **ADR-0038 Amd 4 — smart Learning
curation** (an LLM pass reconciling incoming-vs-existing learnings; the deterministic exact-dedup *floor*
already shipped, so this is the paraphrase-aware ceiling, not urgent —
[[handoff-stateless-both-directions]]). Comment ingestion stays in `docs/open-questions.md`.

**Parked to `docs/open-questions.md` (decide with Jon before build):** multi-bubble / whole-transcript chat
selection (per-bubble `UITextView` caps the payload).

---

Live ambiguities and recently-resolved decisions. Resolved items stay here briefly
(dated) so the reasoning is durable, then graduate into the relevant doc or ADR.

## Live — production cutover: keep-or-drop the never-set synced columns

- **Decide per column before the Production deploy** ([`PROD-CUTOVER.md`](PROD-CUTOVER.md) Reference A). Jon (2026-10-26):
  some of the 23 never-set columns on the missing list have no UI. Compare the lists and decide, column by
  column, what we still care about.
- **The rule.** A missing Production field fails an upload only when the app writes a non-nil value to it. A
  column with no UI and no write path can never fail, but it is dead schema ([[no-dead-data]]).
  - **Keep:** create the field in Development before the deploy.
  - **Drop:** an appended migration before the cut, while dropping is still free. After the deploy the field is
    permanent in Production.
- **How to decide.** For each column, grep the model and its writers for any code path that writes it. A write
  path means keep (and create it); none means drop. Record the verdict per column in Reference A's table. The two
  empty tables (`equipment`, `recipeEquipment`) take the same test.
- **Decided 2026-10-26: Jon approved every verdict as proposed** (Reference A's table, after diffing the Development export). Of the 17 fields
  Development lacks, 9 have a write path and are kept: `pageNumber`, `mealPlanItems.notes`, `menus.notes`,
  `workbenchLog.outcome`/`relatedRecipeID`, `remindersListName`, `pantryItems.threshold*`, and
  `groceryItemSources.menuPlacementID`. 8 have none and are dropped, along with both equipment tables:
  `activeTimeMinutes`, `restTimeMinutes`, `shoppingCategory`, `cookingSessionID`, `tags.color`, `categories.color`,
  and `mealPlanItems.startTime`/`endTime`. `categories.color` was on the Prod-schema promotion list, but no UI
  sets or shows it; its only writer copies `tags.color`, which nothing sets. **Jon confirmed the drop
  (2026-10-26):** re-add it additively if a color UI is ever built. Jon also retired the dormant `tags`/`recipeTags`
  tables (ADR-0049 Amd 5). All of it ships as one slice,
  [`efforts/archive/prod-never-set-drop.md`](efforts/archive/prod-never-set-drop.md), dispatched after chat-access S2. Remove this
  item once that slice merges.
- These drops are the only synced-schema change allowed to merge before the cut (the cutover's Rules).

## Dormant — variation ↔ Workbench overlap (watch)

The 2026-07-11 two-device pass raised three variation/Workbench-overlap forks; all three were answered by
[ADR-0021](decisions/ADR-0021-recipe-variations.md) Amendments 1 + 2 (shipped, device-passed) — the
position is **distinct surfaces, shared primitives** (the diff engine and the promote writer), *not* a
"Workbench of one." Reopen only if a *third* instance appears that neither amendment covers.

## Live — web-capture engine convergence

- **Converge YesChef + Galavant onto a shared capture-engine package (ADR-0007).** YesChef
  is already the second consumer; harvest-first only defers the abstraction until two working
  implementations exist. **Trigger: M2 close** (or Galavant's next capture-engine change).
  Tracked so it isn't forgotten — do not let the two engines drift permanently.

## Foundation / audit

- Did the Pass-1 P0/P1 fixes actually land in the code before grocery/menu/
  meal-planning were built on top, or is that debt still present under the newer
  features? (The audit answers this.)
- Are the grocery, menu, and meal-plan reads observed (`@Fetch`/`@FetchAll`) or
  hand-pulled into `@State`? Are their saves identity-preserving?
- How much feature logic lives in views vs. `@Observable` models in the newer
  subsystems?

## Import / Paprika parity

- What is the concrete Paprika feature-parity gap list, derived from the live app
  rather than memory? (To be built when authoring Phase B.)
- Which Paprika export path is canonical for the real library import — HTML export,
  `.paprikarecipes` backup, or both reconciled? Which preserves the most fidelity
  (dates, categories, image resolution)?
- Does any high-value source need authenticated capture (ATK, Milk Street), and if
  so, when does that enter scope vs. the manual-HTML fallback?

## House layer

- Any of these resolutions that generalize beyond Yes Chef (e.g. the
  "import-before-sync gate") — do they belong as a jon-platform note rather than an
  app-only one?

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

