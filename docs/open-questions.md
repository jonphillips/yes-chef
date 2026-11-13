# Open Questions

> **The executor never reads this file** (jon-platform ADR-0005). It is the architect's and Jon's scratch
> pad; work becomes dispatchable only when a plan PR sets `docs/NEXT_UP.md`.

## Candidates

**Per-recipe facet/tag coverage is Jon's ongoing hand work and gates nothing** — Power Browser (ADR-0050)
and everything downstream move forward without waiting on it.

**Parked briefs (ADR-0005 D10 archive sweep, 2026-10-30).** Designed but not scheduled. Each brief sits in
`efforts/archive/`. Restore one to the root, restated `Designed` or `Ready`, in the plan PR that schedules it.

- **Top `safeAreaInset` bars may hide large titles (2026-11-13)** on Workbenches, Recipes, Browsers. Check on device.
- **Ingredient parser splits inside a parenthetical (2026-11-12).** The Pumpkin Pie butter
  item's notes read "3/4 stick) cold unsalted butter, cut into 1/4-inch slices", so a line like "6 tablespoons
  (3/4 stick) cold unsalted butter, cut into…" was split inside the parentheses. Reproduce from the stored line first;
  a fix re-parses nothing by itself. Fold into the next import slice.
- **Prepared components** ([brief](efforts/archive/prepared-components.md), [ADR-0057](decisions/ADR-0057-prepared-components.md)) —
  a `Recipe.kind` and a directional dish → component edge. Additive schema, so it's safe after the cut. Nothing forces it sooner.
- **ATK "Gather Your Ingredients" repair** ([brief](efforts/archive/import-text-normalization.md)) — P1 only, a
  backup-first data pass; see the fuller candidate below.
- **Tandoor idea harvest** ([notes](efforts/archive/tandoor-idea-harvest.md)) — the alias rows graduated to
  [ADR-0069](decisions/ADR-0069-ingredient-name-fixes.md). Still parked: the `{base, form, prep}` ingredient model and
  the never-unit / transpose-words / site-scoped rules. Read before the next ADR they touch.
- **Commit authority as a typed, test-enforced property** ([review](efforts/archive/application-actions-review.md) D1) —
  the one new track from the 2026-08-02 application-actions review, never built. OQ1 (where the declaration lives) is open.
- **In-app browser Passwords autofill** ([spike](efforts/archive/browser-passwords-autofill-spike.md)) — the
  2026-07-08 spike defending ADR-0009's "never store credentials." First confirm autofill still fails.
- **Full-screen moves the app tabs to the top** ([dogfood 2026-09-21](efforts/archive/dogfood-fixes-2026-09-21.md)
  Thread F) — the one thread from that pass not confirmed in code. Check on device before scoping.

**Name-fix parameters still default to `.empty` (found 2026-11-12, reviewing #502).** ADR-0069 D6 renamed
`canonicalName` so the compiler would find every key comparison. But `PantrySuppression.evaluate`,
`WorkbenchCompare.ingredientComparison`, `GroceryPantryAssumptions.isPantryStaple`,
`GroceryIngredientChoice.isAssumedPantryStaple(pantryStaples:)`, `GroceryStoreArea.seed(for:)`,
`CanonicalIngredient.compoundParts` and `GroceryGeneratedItemDraft.init` take `fixes: IngredientNameFixes = .empty`.
So a new caller that forgets the argument compiles and silently skips your fixes. Every caller in #502 was checked and
is correct; the `seed(for:)` callers pass names that are already fixed. Fix: drop the defaults and have tests pass
`.empty` explicitly. Do it the next time a dispatch touches these files.

**A junk pantry item came from Add to Pantry on a misparsed grocery line (found 2026-11-12).** The pantry has
"red wine vinegar and 1 tablespoon warm water for ten minutes or so". Pantry items have two writers: the pantry
editor and **Add to Pantry** on a grocery item (`GroceryLibraryModel.addToPantryButtonTapped`), which copies the
grocery item's title as is. That title came from an ingredient line whose parsed `item` swallowed an instruction, so
the real producer is that recipe line. Delete the pantry row, then fix the line in its recipe (find it by searching
for "warm water for ten minutes"). If it recurs, Add to Pantry could refuse a title that doesn't look like a name.
ADR-0069 fixes don't help here: this is a bad parse, not a second spelling.

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

**Hand-edited Serve With suggestions can vanish on regeneration (found 2026-11-04, drafting ADR-0062).**
`RecipeServeWithRepository.update` leaves `provenance` at `.model`, so an edited suggestion no longer matches and
`replaceModelSuggestions` deletes it. ADR-0048 meant regeneration to keep the cook's work. ADR-0062 protects linked rows
only. Decide whether an edit should protect a row too, without misusing provenance as "touched".

**A calendar day gets a real plan (decided 2026-11-05, not scheduled).** Replaces the make-ahead note that saves the whole
strategy as one block of text. Jon chose a new date-keyed synced table that shares Menu's bands and views, and expects light
use, so keep it cheap. The design and the questions for a brief are in
[ADR-0034 Amendment 1](decisions/ADR-0034-prep-plan-work-session-timeline.md#amendment-1--a-calendar-day-gets-a-real-plan-2026-11-05).

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

## Live — Calendar complement review validation has no test through the real builders (2026-11-06)

`validateText` decides whether Add is enabled in Calendar complement review, but no test calls it on an item from
either real builder (`MealCalendarModel.makeApplyActions`, `HandoffReviewCoordinator.mealPlanComplementReviewItems`).
If it ever rejected a generated header, Add would be disabled on every complement review, and a test run wouldn't
show it. Reading the code, a generated header validates today, because both sides use the same `dayTitle`.

The small fix: in `mealCalendarChatCollectionCommitPreservesEditedComplementsThroughEditDraft` and
`externalMealPlanHandoffCommitPreservesEditedComplementThroughEditDraft`, assert that
`validationMessage(for: unmodifiedApprovedText)` is `nil` and that the text with its placement line removed returns a
message. It needs a dispatch; PR 457 merged without it.

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

