# Device passes & held ops

Jon's checklist: device passes owed by merged work, and the held prod-schema promotion. **Not executor
work — the executor never reads this file.** `NEXT_UP.md`'s **Owed** line points here. Moved from
`CURRENT_HANDOFF.md` on 2026-09-29 (jon-platform ADR-0005). When a pass clears, delete its block and note
it in `DONE-LOG.md`.

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate is **crossed and holding**. We stay in
CloudKit **Development** by design; prod-schema promotion is the held ops step in its own section below.

## Device passes owed

Not work, a checklist.

**Cockpit Find handoff — the two-app round trip ([ADR-0058](decisions/ADR-0058-cockpit-find-referral-transport.md),
PRs [#322](https://github.com/jonphillips/yes-chef/pull/322) + [#325](https://github.com/jonphillips/yes-chef/pull/325)),
no schema.** This is Cockpit's S-join, so it is owed **after Cockpit S-c2** (verdict drain) lands; until then, Yes
Chef's half can only be seen in `AppLog.handoff`. On device:
- Send a multi-recipe email from Cockpit; Create Recipe opens with its provenance.
- Save two candidates from one multi-recipe email; the Find shows both admitted, with no id seen and no hop.
- Kill Yes Chef between the two saves; on relaunch, confirm Cockpit receives the first admission rather than a dismissal (the transient review session itself is not restored).
- Glance back at Cockpit mid-review; the referral is **not** dismissed, and a later save still admits it.
- Kill Yes Chef mid-review; the next launch dismisses it.
- The Shortcuts "Capture a Recipe from Text" action shows only its text field.

**ADR-0055 — menu Dishes drag-to-reorder (PR [#310](https://github.com/jonphillips/yes-chef/pull/310)), no
schema.** On device (Xcode 27 beta 5+), reorder dishes within a menu day by drag — a row lifts and drops in the
new position with no not-allowed badge, and the order persists. Confirm the interim Move Up/Down swipe actions
are gone. Exercise a sectioned menu (multiple days) — the sectioned `reorderContainer(for:in:)` was the one live
unknown (ADR-0055 OQ3) and S2 built against it. Cross-check `docs/KNOWN-ISSUES.md` reads correctly.

**ADR-0042 Amd 5 — tolerant LLMHandoffKit contract marker (PR
[#309](https://github.com/jonphillips/yes-chef/pull/309)), no schema.** Paste a return whose `YC-CONTRACT:`
marker is **missing** or **older** (`v2` / `v2.1`) and confirm it still **imports, with a non-blocking warning**
on the review surface — no hard rejection. Paste one with the **current** `v3` marker → silent, no warning.
Paste one claiming a **newer** marker (`v4`) → hard stop. Confirm no "Galavant"/"Settings" wording ever reaches
a user (the error must read as Yes Chef's own "instructions out of date"). Known mild false positive to eyeball,
not fix: the tokenless bare-JSON reader-feedback path always shows the missing-marker footnote.

**ADR-0052 S3 — audit learned grocery `.model` placements (PR
[#306](https://github.com/jonphillips/yes-chef/pull/306)), no schema.** In the grocery seed-coverage audit view,
confirm classifier-promoted `.model` rows are listed for audit (amended, never deleted); correct one via the
aisle picker and confirm the correction wins as a `user` row and survives relaunch (precedence user > seed >
model). ⚠️ **Architect note:** touches app-layer model code — the [[app-test-target-in-verification]] gate may be
open; run `YesChefTests` locally or let this device pass stand as the check.

**ADR-0042 Amd 4 — recipe-body hand-off finalizes two ways (PR
[#309](https://github.com/jonphillips/yes-chef/pull/309)), no schema.** On a recipe,
**Copy Prompt** and confirm the tail no longer says "prep plan" and the body clearly describes *both* finalize
outcomes (revision brief vs. new recipe). Then paste, into the recipe's **Paste** control, each of: **(a)** a prose
revision brief → the side-by-side **adjustment review** opens (revise-this-recipe); **(b)** a schema.org `Recipe`
JSON-LD block → **Create Recipe** opens with a populated **standalone** draft (riff-into-new), and the original
recipe is untouched. Both must carry the `YC-HANDOFF` token + `YC-CONTRACT: v3` marker (a real return does).
⚠️ **Ride-along build fix:** this slice also fixes a **pre-existing** red build on `main` — commit 34c579b added
`WebRecipeCaptureWarning.multipleRecipeCandidates` + `.nestedInstructionSectionsFlattened` but never updated the
**Share Extension**'s exhaustive `shareReviewTitle` switch, so `YesChefShareExtension` did not compile (the app
scheme builds the extension). Worth checking why that merged green. Core (`AIHandoffTests`, 54) + app
(`AIHandoffRecipePasteRoutingTests`, 2) suites pass locally.

**ADR-0054 — extraction preserves structure & identity (PR
[#308](https://github.com/jonphillips/yes-chef/pull/308)), no schema.** Paste JSON-LD and confirm: **(a)** named
`HowToSection` instruction groups survive as named instruction sections (not one flat block); **(b)** a *nested*
`HowToSection` flattens with the child name preserved and a visible warning; **(c)** two materially-complete Recipe
nodes → one deterministic primary imports and a `.multipleRecipeCandidates` warning appears (no blended recipe);
**(d)** duplicate ingredient lines across two sections are kept (dedup is section-scoped). Each warning's
capture-review title should render in Create Recipe, and an ordinary schema.org paste should still import unchanged.

**ADR-0053 Amd 2 / S3 — Shortcuts return path + two ride-alongs (PR
[#307](https://github.com/jonphillips/yes-chef/pull/307)), no schema.** Run the `Get Clipboard` Shortcut both from a
**cold launch** and while the app is **already running** — clipboard text lands in the resident Create Recipe session
for review. Empty clipboard fails cleanly. **Fire the Shortcut while a different draft is in progress and confirm it
does NOT wipe it** — a non-empty session offers the incoming text as a new source via a confirmation dialog (the
`isPresented` destructive-setter trap, [[alert-ispresented-destructive-setter]]). Ride-alongs: **an archived recipe
opens from a menu link** (archive severs only the meal-plan link and keeps `menuItems`; permanent delete severs them),
and **iPhone Settings / Groceries / Workbenches navigation** pushes correctly through the More tab. ⚠️ **Architect
note:** the new app-target `CreateRecipeModelTests` are app-layer *model* code and could not run in Codex's env, so
the [[app-test-target-in-verification]] gate is open — run `YesChefTests` locally to close it, or let this device pass
stand as the check.

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

*`Recipe.lastCookedAt` and `Recipe.timesCooked` are **not** on this list and must not be promoted — both are
superseded by calendar-derived values (this slice) and are to be **dropped in the pre-prod baseline squash**:
omit them from the squashed `CREATE TABLE "recipes"` and remove the fields + CodingKeys from the `Recipe`
model. Old backup JSON carrying these keys still decodes (unknown keys are ignored), so no backup-compat
migration is needed.*

**The check is the registration list, in both directions.** A column on a synced table is on this list; a
column on a table that is *not* registered in `CloudSync` is local and belongs nowhere near it. Both
mistakes have been made — verify against `CloudSync.swift`, not against intuition.
