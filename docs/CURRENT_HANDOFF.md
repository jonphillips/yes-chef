# Current Handoff

Last updated: August 10, 2026. **No designated Next Up target — Jon picks from the queue;** the live candidates are
**ADR-0052 S3**, **ADR-0054** (extraction fidelity), and the **ADR-0053 Amd 2 Shortcuts return path** (Ready
Efforts). Newly-merged work has moved to [`DONE-LOG.md`](DONE-LOG.md); the device passes it owes are in their own
section below.
⚠️ **A standing Codex-env gotcha:** the simulator-hosted `YesChefTests` target cannot run in Codex's sandbox (no CoreSimulator), so its "couldn't run
the app tests" is structural, not a regression — and it once *masked two genuinely red tests* (missing
`bootstrapDatabase()` → `RecipeEditorModel`'s eager `@Fetch` tripped SQLiteData's blank-DB reporter), fixed by
the architect running the target locally ([[codex-build-excuse-reproduce]]). **Filling in per-recipe
facet/tag coverage is Jon's ongoing hand work and gates nothing** — Power Browser (ADR-0050) and everything
downstream move forward without waiting on it.

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate is **crossed and holding**. We stay in
CloudKit **Development** by design; prod-schema promotion is the held ops step in its own section below.

The **short entry point** for a fresh Yes Chef conversation — Next Up, Standing guards, Ready Efforts,
prod-schema promotion list, Verification Pattern, nothing else. Completed-slice history and strategic
background live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

**Invariant — no completed work in Next Up or Ready Efforts.** The moment a slice merges, its blurb is
**deleted here** and the record moves to [`DONE-LOG.md`](DONE-LOG.md); an item may keep at most its *one live
follow-on thread* (trimmed to that thread, not the recap). Shipped work is **named** only in two places:
**Standing guards** (as "don't re-queue this") and **Device passes owed** (the pass *is* the work). "Clean up
this file" **means run that sweep** — `grep -niE 'complete|shipped|done|device-passed' docs/CURRENT_HANDOFF.md`,
and every hit outside those two sections is a removal candidate — not merely fix statuses in place.

## Next Up

**No designated target — Jon picks from the queue.**

- **ADR-0045 cold-start starters are still open, no longer time-gated:** S2 rearranged the Calendar day-header
  Chat and the Workbench Chat into inspectors and left them passing `.none`. Whether they want their own starters
  ("Plan this week" / "What should I prep tonight?") is Jon's call whenever — it no longer blocks anything.

---

**Prior candidates (queue — not the designated target).** Per-recipe facet/tag coverage is Jon's ongoing hand
work (Edit Tags + DEBUG Facet Coverage) that **gates nothing**. Live candidates:

- **[ADR-0052](decisions/ADR-0052-grocery-learned-area-table.md) S3 (not designated):** repoint ADR-0037's
  seed-coverage view to **audit** the `.model` rows (amends, never deletes). The rest of ADR-0052 is shipped and
  device-passed (DONE-LOG).

The ATK grocery-bug slice ([`efforts/import-text-normalization.md`](efforts/import-text-normalization.md)) is a
**data migration wanting backup-first + a device pass** — hold it until Jon is local. D3's settled
hidden-vocabulary rule lives in ADR-0049 D11.

## Standing guards

Closed decisions that stay closed, here only so a dispatch does not re-queue them. **Nothing in this
section is work.**

- **⚠️ The ADR-0042 return contract is v2.1** (`AIHandoffReturnContract.version`) — re-copy the project
  instructions from AI Settings or every verb fails the marker gate. (Operational: it bites on any hand-off
  dogfooding session.)
- **⚠️ [ADR-0051](decisions/ADR-0051-text-to-recipe-extraction-strategy.md) — text→recipe has ONE strategy; do
  not fork a new parser.** Any new "turn this text/markup into a recipe" path (paste, photo→OCR, another
  hand-off return, …) MUST route LLM extraction through **`RecipeExtractionClient`**, reuse the existing
  deterministic extractors for structured sources (schema.org → `RecipeJSONLDExtractor`), and terminate in
  **`RecipeEditorDraft`**. **A fifth bespoke parser, a second "text→recipe" model call, a new terminal draft
  type, or a third save path is a review block** (D7, as restated by Amd1-D3). The four existing front-ends stay
  plural *by design* (web/schema.org, menu-note heading heuristic, workbench synthesis, JSON-LD return) —
  consolidate the sink and the engine, not the parsers. **The D5 lift is DONE** — `RecipeExtractionClient` now
  lives in a source-neutral home (out of `WebRecipeCapture`), lifted at paste-text, the second real consumer
  (ADR-0053 S1, PR #290); `structuredPageText` → `text`.
  - **⚠️ [Amd 1](decisions/ADR-0051-text-to-recipe-extraction-strategy.md#amendment-1--d1-was-wrong-about-capture-there-are-two-save-paths-and-the-review-surface-is-source-specific-2026-08-07)
    corrected D1 — do not read the old wording as "capture uses the sink."** It does not: `RecipeCaptureView`
    reviews on **`ParsedRecipePage`** and commits through a **second** canonical save path
    (`importCapturedRecipe` → `importBundle`), which Paprika import shares. The enforceable rule is **one sink
    type; ONE SAVE PATH PER IDENTITY CLASS** — a source with a stable external identity (URL, Paprika record)
    commits through `importBundle` and gets `RecipeImportRef` dedupe/warnings/rollback; a source authored in the
    app (paste, typed, menu-note, workbench) commits through `save(draft:)`. **Review surfaces may be
    source-specific but must edit the sink**; capture is a *named grandfathered exception*, **not a precedent**
    to cite. **Converging the two save paths is not queued work** — it needs a source that is both authored and
    externally identified, which does not exist yet.
- **ADR-0021 (variations) is COMPLETE — V1–V3, Amendment 4 (V4a/V4b/V4c + Delete), and anchor-repair
  Dispatch 0/1/2 all shipped (DONE-LOG).** ADR-0023 (recipe edit proposals) has nothing queued: its
  *iterative refine loop* is **WITHDRAWN** (ADR-0042 D7 — it happens in the live external thread; **do not
  rebuild it**); per D2 the in-app adjust verb is the **only** path that writes a structured delta. **Expected,
  not a bug to patch (ADR-0014 Amd1-D4):** adding a header inside a recipe that has variations mints a new
  section, so `derivingVariation` hits `.ingredientSectionAdded` → `variationNeedsReview`. Fixing it needs a
  delta-vocabulary decision and it is **ADR-0021's** — do not extend the delta ops on this momentum. **Note:
  Amd4-D4's two step ops (`stepInsert`/`stepRemove`) were the sanctioned widening and have now shipped (V4c);
  the vocabulary is closed again, so a *section* op still needs its own ADR decision, not this momentum.**
- **ADR-0042 S3 (`workbenchDraft`) is DONE — S3a + S3b built, device-passed 2026-08-07 (PR #289),
  recorded in [`DONE-LOG.md`](DONE-LOG.md).** The return is **extraction, not synthesis** (schema.org JSON-LD
  → the deterministic `RecipeJSONLDExtractor`); **do not build a new recipe-text parser** (Amd2-D2/D5). There
  is no S5. Amd2-OQ1/OQ3/OQ4 are resolved (see the ADR). It is the first path built to ADR-0051.
- **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it.** ADR-0041 closed at S2.6, S3
  withdrawn ([Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).
  If section provenance is ever wanted it designs its own storage against its own consumer
  ([[withdraw-not-defer-orphaned-schema]]).
- **Both candidates Jon named 2026-07-21 are discharged** — variations (ADR-0021 V1–V3, shipped + device-passed;
  Amd 4 is a *later* 2026-08-01 reopening, queued separately in Next Up) and "Menu is under-served by hand-off
  verbs" (ADR-0043's load test). Parked **ADR-0013** meal-planner verbs are separate and unscoped — see Ready
  Efforts.
- **The Recipe Workbench store/curate/compare arc (ADR-0019) is complete**, S1–S4 shipped. Parked follow-ons
  live in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md), not here.
- **The workbench's experiment-outcome verb is NOT scoped** — only its *placement* is ratified (ADR-0042 D8's
  corollary: a conjecture suppresses learnings, a **cooked** experiment is findings, so learnings come back
  on). That amendment gets written when that half is scoped, **deliberately not now.**
- **Chat entry points are unified and closed** ([`efforts/chat-ask-uniformity.md`](efforts/chat-ask-uniformity.md),
  PR #244), and **ADR-0046 S2 (PR #298) closed the presentation half too** — every wide-width surface (Recipe,
  Calendar, Workbench Detail, Workbench Compare) is now the **`.inspector`** presentation; compact stays a modal
  sheet. Uniformity is **cross-surface, not cross-device**: modal sheets keep the iOS nav bar, embedded/inspector
  presentations keep the in-panel header row. **That divergence is intended — do not "unify" it.** The old
  `ChatWorkspaceSplit` detent/divider and the `.column`/`DetentIdentity` contract are **deleted; do not resurrect
  them.**

## Ready Efforts (queue)

Drawn into **Next Up** as needed; not itself a dispatch target. Completed efforts live in
[`docs/DONE-LOG.md`](DONE-LOG.md).

**[ADR-0054](decisions/ADR-0054-extraction-preserves-structure-and-identity.md) — extraction preserves structure
and identity (Proposed 2026-08-10, from the Codex Semantic Fidelity Audit).** Four **no-schema** slices at the
`RecipeParseBuilder`/model boundary, all governed by ADR-0040 lossless-or-loud ([[editable-at-the-grain-stored]]):
**D1** carry named instruction sections end-to-end (retire the flat `WorkbenchDraftRecipe.instructionLines` narrow
point — both source and sink are already section-aware); **D2** one builder per candidate, so multiple
materially-complete JSON-LD Recipe nodes never blend (deterministic primary + `.multipleRecipeCandidates` warning,
user selection later); **D3** nested `HowToSection` is **declared-lossy** — flatten but preserve the child name and
warn, no recursive schema; **D4** ingredient dedup is section-scoped, not global. No effort doc yet. The same
audit's **P0** (destructive import convergence) already shipped (PR #304, DONE-LOG).

**[ADR-0053 Amd 2 / S3](decisions/ADR-0053-create-recipe-destination.md#amendment-2--a-headless-transport-shortcuts--app-intent-into-create-recipe-2026-08-10)
— Shortcuts return path** ([`efforts/shortcuts-return-path-create-recipe-2026-08-10.md`](efforts/shortcuts-return-path-create-recipe-2026-08-10.md)).
A headless `CaptureRecipeFromText` App Intent + a `Get Clipboard` Shortcut lands clipboard text (usually a ChatGPT
return) in the **resident Create Recipe** session for review — collapsing copy→open→paste→Extract. **No schema**
(the session is D4-transient). ⚠️ **Amd2-D2 is the trap:** wire it to Create Recipe / `save(draft:)`, **never** the
routed handoff importer (the clipboard text has no `handoffID` and no subject). Seed **non-destructively** —
`pastedTextReceived` overwrites `composeText`, so it must never clobber unsaved work. Designed; independent of any
branch. App-layer, so `YesChefTests` applies ([[app-test-target-in-verification]]).

**[`efforts/import-text-normalization.md`](efforts/import-text-normalization.md) — ATK's "Gather Your
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

**Drag recipes from Browse into a meal (BLOCKED on iPadOS Beta 4).** The pipeline is **already wired**
(`.draggable`/`.dropDestination` between `MenuRecipeBrowserPanel` and `MenuDishDayList`, slide-over stays
interactive) but drag-and-drop is not firing reliably in the current betas. **Retry after Beta 4;** then it's
confirm-E2E + polish, no schema.

**Meal-Planner chat verbs** (ADR-0013 + `efforts/cooking-workspace.md`) — the one remaining named
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
  spec in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md). ⚠️ Re-read against ADR-0042 D2/OQ5
  first: it is an *in-app* draft verb and the draft is a structured write.
- **`stageReaderFeedback` defaults `unparsedLines` to `[]`**, so accepting a single tip through the *in-app*
  path clears the evidence banner (cosmetic).
- **From the PR #244 review, all one-liners:** `MenuDetailModel.tool`'s `didSet` and
  `recipeBrowserButtonTapped` both clear `activeChatStarterID` — say it once; `MenuDetailReader`'s
  `isAskActive`/`askButtonTapped`/`regeneratePrepPlan` closure params are now pure passthroughs (fine to leave
  for ADR-0046); `namesStarterContractsForEveryHost` asserts `.starters == .starters` and proves nothing.

**Still-deferred, separate future efforts:** ADR-0027 **OQ4** (a note-worthiness taste preference);
**ADR-0036 S3** — promote a `RecipeNote` deposited *on a recipe*; **ADR-0038 Amd 4 — smart Learning
curation** (an LLM pass reconciling incoming-vs-existing learnings; the deterministic exact-dedup *floor*
already shipped, so this is the paraphrase-aware ceiling, not urgent —
[[handoff-stateless-both-directions]]). Comment ingestion stays in `docs/open-questions.md`.

**Parked to `docs/open-questions.md` (decide with Jon before build):** multi-bubble / whole-transcript chat
selection (per-bubble `UITextView` caps the payload).

## Device passes owed

Not work, a checklist.

**ADR-0050 S3 + S3.5 — Power Browser typed filters + compact-list convergence (PR
[#303](https://github.com/jonphillips/yes-chef/pull/303)), no schema.** In the Power Browser, exercise the new
**Attributes / Usage / Source** filters (time-at-most, servings-at-least, rating, make-ahead, never-cooked,
cooked-more-than-5×, added-after, and the per-field source pickers) and confirm active-selection chips add and
remove correctly. Then confirm the **compact recipe list and the browser now agree** on what a selection means
(S3.5 routed both through the one engine), and that the editor's **Cuisine/Course** are now single-select facet
pickers (freeform fields retired). Check that an un-migrated free-text cuisine still turns up in text search.

**Import P0 — preserve divergent import duplicates (PR
[#304](https://github.com/jonphillips/yes-chef/pull/304)), no schema.** Capture a recipe, edit it (add a note and a
photo), then re-import the same source and confirm the edited copy **survives** and the ambiguous-identity
**warning** appears — no third copy, no silent delete. (Already-shipped convergence damage is unrecoverable in
code; this is forward-looking protection.)

**ADR-0050 OQ5(a) — Cuisine/Course facet backfill (PR
[#305](https://github.com/jonphillips/yes-chef/pull/305)), no schema.** On a library with imported/hand-entered
cuisines, launch once → recipes that had free-text Cuisine/Course now surface under the facet filters with the old
Fields value gone (moved, not doubled); unmatched values stay put and show in the log summary. Confirm a second
launch changes nothing, and that a facet assignment you *remove* stays removed across relaunch.

**ADR-0050 S2 — Power Browser surface (PR [#301](https://github.com/jonphillips/yes-chef/pull/301)), no
schema.** On wide iPad, open the dedicated **Power Browser** sidebar tab: the top-ranked facet should be expanded
with contextual counts, chip selection/removal and Clear should update the available values and result list,
search and every sort should work, and a result should open its recipe detail. Confirm the tab remains a peer of
the Safari web-capture Browser and can be focused with the system sidebar controls. Exercise an empty library and
a library containing a parent/descendant facet value.

**ADR-0042 Amd 3 — Recipe JSON-LD v2 capture (PR [#302](https://github.com/jonphillips/yes-chef/pull/302)), no
schema.** In AI Settings, **Copy Recipe Contract Source**, and from the Menu, **Copy Recipe Capture Request** — each
should copy the expected text. Then paste a v2 JSON-LD block (carrying `yesChef:ingredientSections` plus both a
`HowToSection`-named and an unsectioned-`HowToStep` instruction shape) into Create Recipe and confirm it reviews and
saves with cuisine/course, the named ingredient groups, and a single unnamed instruction section (never one section
per step). Re-check that an ordinary schema.org paste still imports unchanged.

**ADR-0046 S1 — the sidebar-adaptable app shell (PR [#297](https://github.com/jonphillips/yes-chef/pull/297)), no
schema.** Both physical devices × both orientations × **sidebar and tab-bar modes**; the system sidebar⇄tab-bar
toggle; `TabViewCustomization` reorder/hide/pin **persisting across launches**; the ADR-0039 third-glyph check.
Exercise the S1 review-fix surfaces specifically: **Calendar** renders (was blank on iPhone / empty pane on iPad),
**Create Recipe** shows its Save/Clear and a save round-trips, the menu/workbench deep-links + `openMenuFromCalendar`
land, and the full-screen cook/recipe covers still present over the `TabView`. Jon's early check looked good;
this confirms it.

**ADR-0046 S2 — the chat presentation merge (PR [#298](https://github.com/jonphillips/yes-chef/pull/298)), no
schema.** On **wide iPad**, open Ask in **Recipe, Calendar (workspace + day header), Workbench Detail, and
Workbench Compare** — each should open the **inspector** (never a modal sheet on top), close cleanly, and
propagate the workbench tier to Compare; on **compact iPhone** each still opens the modal sheet. **Exercise the
review fix directly:** on wide iPad tap Ask in **Workbench Detail** and confirm you get the inspector *only* (the
double-presentation bug was the compact sheet firing alongside it). Verify the live-context refresh — edit a
workbench while its chat inspector is open and the chat's context updates without dropping the transcript. Both
physical devices × both sidebar and tab-bar modes.

**ADR-0021 Amendment 4 V4b (PR [#293](https://github.com/jonphillips/yes-chef/pull/293)) — the two-device
`recipeRelatedRecipes` sync pass.** A new synced table: verify a link/unlink round-trips across
`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro` and that offline-duplicate convergence holds. **Also verify the
delete-cascade follow-up (PR [#296](https://github.com/jonphillips/yes-chef/pull/296)):** permanently deleting a
recipe removes its related-recipe edges, so no orphaned link is resurrected by a full-zone fetch. **Back up first.**

**ADR-0021 anchor-repair Dispatch 2 (PR [#294](https://github.com/jonphillips/yes-chef/pull/294)) — the repair-UI
pass, no schema.** Open a previously orphaned variation → **Edit Variation → Repair Anchors**, re-anchor an
orphaned op to the intended current row (and exercise **Discard**), and verify the fold holds after the base
wording changes and that Save unblocks once the queue is empty.

*(Device-passed 2026-08-08 and removed: **ADR-0053 S1 (PR #290) + S2 (PR #291)** — the combined Create Recipe
pass (sidebar → paste → review cues → Save → lands on the new recipe, Clear, resident session, tier/labels-on-save,
web-capture re-check); the S2 cue-volume and `unattributedSource` notes did not warrant an S2.1. **ADR-0052 S1+S2
(PR #292)** — the grocery learned-area two-device correction-sync and the high-effort budget stress both cleared.)*

*(The full ADR-0049 facet/labeling arc — PRs #270/#272/#274 (D1–D3), #275 (D5), #276 (F1/F2), #277 (OQ4 seed),
#278 (S5/S6+D8 backfill tooling), #281 (Amd-4 floor), #282 (Edit Tags refine) — is device-passed 2026-08-05 and
removed. D4 hand pass done.)*

*(All other owed passes are **device-passed 2026-08-05 and removed** (Jon): variation-anchor-repair Dispatch 0
(PR #284) + Dispatch 1, ADR-0021 V4a (PR #285), prep-plan Slice 2 (PR #262), Recipe section grain S1 (PR #246),
ADR-0032 S3, and the combined PRs #243+#244 four-chat-surface pass. They had been bundled — strangely — into one
paragraph with ADR-0030 S2, which is why they are cleared together.)*

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) S2 — the only outstanding pass, and deliberately
held.** The export → restore → re-enable-sync round-trip **passed on two simulators 2026-07-29** (isolated test
container), which also closed OQ1. OQ6 is now diagnosed (Amendment 3): a naive real-device restore can be
**silently clobbered by any peer's in-flight delete**, so **hold the real-device pass until the enforced restore
procedure gates it** (quiesce peers → restore on one → reinstall peers). When it runs, follow that procedure —
and **Undo Last Restore** is untested at all and rode the same broken binding as restore, so exercise it too.

## Prod-schema promotion list

**Standing release follow-up — not a dispatch. A pre-cut ops step Jon runs.** We stay in the CloudKit
**Development** environment so the schema keeps evolving freely; promoting to **Production** is
additive-only and **permanently locks those record types**, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy the following to the production schema:

- Phase E Slice 3 **pantry-policy + `canonicalName`** fields
- **`Recipe.coverPhotoID`** (reader photo affordances, PR #87)
- **`Category.color`**, **`Category.facetID`**, and **`Category.hidden`**, plus the synced **`facets`**
  table (ADR-0049 Amendment 2)
- The synced **`aiSettings`** table (ADR-0018, PR #96), **including** its additive `readerFeedbackPreference`
  (ADR-0025 D6) and `captureToNotePreference` (ADR-0027 S1, PR #141) columns
- The synced **`recipeVariations`** table (ADR-0021 / recipe edit proposals S2)
- The synced **`recipeServeWith`** table (ADR-0048 S3)
- **`Menu.externalProjectName`** (ADR-0038 S2)
- The synced **`learnings`** table, **including** its `sortOrder` column (ADR-0038 Amd 1 / Amd 5)
- The synced **`prepPlanSteps`** table (ADR-0040 S2)
- The synced **`workbenchLog`** table, **including** its nullable `hypothesis` / `change` / `rationale`
  columns (ADR-0042 S2)
- **`workbenches.dateCompleted`** (Dogfood ferry Dispatch 3)
- The synced **`workbenchReferences`** table (ADR-0032 S1)
- The synced **`recipeDeliberationLog`** table (ADR-0021 V3 / [Amd 3](decisions/ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23))
- The synced **`groceryAreaAssignments`** table (ADR-0052 S1+S2)
- The synced **`recipeRelatedRecipes`** table (ADR-0021 Amendment 4 V4b)

*The `Menu.prepPlan` BLOB is **not** on this list and must not be re-added — it was dropped outright, so the
dead CKAsset field never enters the prod schema.*

**The check is the registration list, in both directions.** A column on a synced table is on this list; a
column on a table that is *not* registered in `CloudSync` is local and belongs nowhere near it. Both
mistakes have been made — verify against `CloudSync.swift`, not against intuition.

## Verification Pattern

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the device pass
regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files — `project.yml` globs the source dirs, so a new
  `.swift` file is invisible to the **app target** until the `pbxproj` is regenerated (hand-editing the
  `pbxproj` is a fragile workaround, not the pattern). **This is a build-claim tripwire:** ADR-0021 V4a's
  first push added two `YesChefApp/` extension files without regenerating, so the app target could not have
  compiled (their symbols would be undefined) — yet the PR claimed a green generic build. A "passing" app
  build that omits newly-added files is proof the build was never actually run ([[codex-build-excuse-reproduce]]);
  the architect re-runs it locally before approving (PR #285, fixed in `5388e31`).
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise run the app build with **elevated/unsandboxed permissions**, no simulator, no signing identity:
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`.
- Run `scripts/check-drift.sh`.
- **The generic app build is required evidence for `YesChefApp/` changes.** `check-drift.sh` compiles only
  `YesChefPackage`; a green package build and `swiftc -parse` are not App-target evidence. The default Codex
  sandbox can SIGTERM Xcode before compilation by denying user-level service/cache access, so start with the
  elevated command. A sandbox-shaped `143` is not a green result. If the elevated build cannot reach the
  compiler, record the full-log path and **the architect runs the same build locally before approving.**
- **Run the `YesChefTests` app target when a change touches `YesChefApp/` *model* code** (a `@Observable`
  model, its extensions, or a display model — **not** view-only or copy changes). **Run it
  elevated/unsandboxed on the *first* attempt** — the default sandbox has no CoreSimulator service and a
  denied Swift/Clang module cache, so a sandboxed run *cannot* reach the tests. Do not attempt it sandboxed
  first, and do not fall back to a focused `swift test --filter` (it hits the same denied module cache). One
  invocation resolves a udid and runs the target:
  `udid=$(xcrun simctl list devices available | grep -oE '[0-9A-Fa-f-]{36}' | head -1); scripts/xcodebuild-summary.sh -scheme YesChef -destination "platform=iOS Simulator,id=$udid" -skipMacroValidation test`.
  **This is the one sanctioned simulator use** and it is a
  deliberate narrowing of guardrail #8, not a hole in it: it *runs tests*, it does not drive UI, install a
  dogfood build, or take screenshots. Jon still owns the device pass. **Why it earns the ~2 minutes:**
  nothing else executes this target — the generic build only compiles it — so it rots invisibly. Found
  2026-08-06: five tests had been red on `main` for some time (models resolve `@Dependency(\.uuid)` eagerly in
  `init`, so *constructing* one outside a scope fails), and they surfaced only because a V4c review happened
  to write app-level tests. **Gotcha:** the scheme's target is **`YesChefTests`** while the directory is
  `YesChefAppTests/` — `-only-testing:YesChefAppTests/…` fails with a misleading "isn't a member of the
  specified test plan or scheme."
- **The app target is where the model + binding *assembly* is certified.** Core tests certify the parts.
  Two shipped defects lived exactly in that gap — ADR-0030's restore (dead through three reviews and a green
  Core suite) and V4c's inserted-step section drift — so a fix to a model-level defect wants its regression
  test *here*, not only in Core ([[alert-ispresented-destructive-setter]]).
- **Corollary — keep pure logic out of the App layer.** String formatting, serialization, and parsing belong
  in `YesChefPackage` (which Codex *can* compile and test). #185's break was `HandoffIntents.swift` calling
  `date: .full` — logic that belonged in Core, where the package build would have caught it instantly.
- **`YesChefAppTests` compiles and links on every `check-drift.sh` run, but only *executes* behind
  `YESCHEF_RUN_APP_TESTS=1`** (it boots a simulator, and there is a teardown hang). **29 tests in 9 suites
  pass as of 2026-07-29** (the SQLiteData 1.8.2 bump fixed the link wall — see the DONE-LOG arc). So the old
  "a test there counts for nothing" rule is retired — but **Core is still the default home**, because
  `YesChefPackage/Tests/` runs on every dispatch with no flag and no simulator. Put a test in the app target
  only when it genuinely needs the app target, and say in the PR that you ran it with the flag. **If the
  `Ld … SQLiteData.framework` undefined-symbols wall ever returns, `xcodebuild clean` first** — SQLiteData
  links `StructuredQueriesCore` via Swift autolinking against the `PackageFrameworks` search path, not a
  declared dependency, so it is build-order sensitive and a stale eager-linking TBD looks identical
  ([[exported-import-not-link-time]]).
- **Note:** parts of the app target (`PantryViews.swift` / `GroceryViews.swift`) compile only in Jon's device
  pass, not in CI.
- **Do not install/launch on simulators by default** — hand straight to Jon's UI pass. Only boot a simulator
  when a change genuinely can't be confirmed from build + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** No alternate destinations, simulator resets, or install loops.
  An environment failure that prevents the elevated build reaching the compiler is an architect gate, not a
  successful Codex verification.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
