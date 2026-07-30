# Effort — Unified Categories (ADR-0049 S1: fold tags into the category tree)

**Thin pointer, not a re-spec.** The authority is
[`ADR-0049 § Slices § S1`](../decisions/ADR-0049-unified-labels-and-assisted-tagging.md#slices) and its
Decision D1 + Resolved OQ3. Build S1 as written there. This brief only carries the deltas Codex needs and the
guardrails a dispatch must not undo.

## What S1 is

Subsume `tags` into `categories` so there is **one** labeling store. After S1: a former tag is a **loose
(parentless) category**; nothing in the app reads or writes the tag tables anymore; the tag tables survive
**dormant** for sync safety. This is foundational — S2 (harvest) and S3 (proposer) both target the unified
store, so nothing downstream is dispatchable until S1 lands and device-confirms.

**This is a larger-than-usual slice by design — do not split the fold from the read-migration.** If the Core
fold ships but the App still reads `tags`, tags vanish from the UI in the gap. Core fold + App read-migration
land **together**, one PR. (Architect reviews at sub-slice resolution; the dispatch is one unit.)

## The two passes — keep them separate (this is the OQ3 triage)

1. **Schema DDL — pre-engine, in `registerMigration`.** Add `color TEXT` to `categories`. Structure only, **no
   data movement** inside the migration block ([[migration-writes-bypass-sync-triggers]]).
2. **Data fold — post-engine, deterministic, idempotent.** Runs *after* `makeSyncEngine` so writes carry sync
   metadata and converge:
   - Each `tag` → a root `category` **reusing the tag's UUID** (`category.id = tag.id`). Carry `name`, `color`,
     `sortOrder`, `dateCreated`. The id reuse is what makes two devices running the fold independently land the
     **identical** category id — that convergence is load-bearing, do not generate fresh UUIDs.
   - Each `recipeTag` → a `recipeCategory` (reuse `recipeTag.id`; `categoryID = recipeTag.tagID`).
   - **Merge-on-name:** if a native same-name category already exists (case-insensitive), re-point the recipe
     links to it instead of minting a duplicate.
   - **Dedupe the pair:** `recipeCategories` has **no** unique index on `(recipeID, categoryID)` — guard in
     code so a recipe that carried both tag "Veg" and category "Veg" ends with one link, not two.
   - **Idempotent:** gate every row on "does the target already exist," so re-running on every boot is a no-op.

## Guardrails a dispatch must not undo

- **Dormant, not dropped.** Stop all writes to `tags`/`recipeTags`, migrate reads to categories, but **do not
  drop the tables and do not unregister `Tag`/`RecipeTag` from `CloudSync`** — both are sync events for no
  benefit. Unreferenced dormant rows are harmless. Physical removal is a later optional slice, or never.
- **No `kind` column, no second axis.** The parent is the dimension (ADR-0049 D1). Loose = parentless. Do not
  reintroduce a flat/typed category concept next to the tree.
- **Reconcile stays the sole writer / creator of nodes.** Nothing here changes the case-insensitive
  `reconcileCategories` contract; the fold feeds it, it does not replace it.
- **This is not the proposer.** S1 is pure determinism — no model call, no `LabelProposer`, no capture change.
  Those are S2/S3/S4.

## Blast radius (so it's sized honestly)

- **Core writes/reconcile:** `RecipeCore.swift` (`reconcileTags`), `RecipeRepository+Import.swift`
  (`reconcileTags` on import), `RecipeAdjustment.swift`, `RecipeListRequest.swift`, `Models.swift`,
  `CloudSync.swift` (leave registrations; touch only if a read moves).
- **App reads:** `RecipeActiveFilterBar.swift`, `RecipeEditorView.swift`, `RecipeDetailView.swift`,
  `RecipeLibraryListState.swift`, `MenuViews.swift`, `MealCalendarViews.swift`, `OriginalSnapshotView.swift`
  (plus `RecipeImageLoader.swift` if it only matched incidentally — verify). Each moves tag reads → category
  reads. The library filter and the editor are the substantive two; the rest are incidental references.

## Verification

- `xcodegen generate` (new Swift files), `swift build` the package, **the generic app build is required
  evidence** (App read-migration — see the handoff Verification Pattern), `scripts/check-drift.sh`.
- **Core tests carry the fold's correctness:** idempotent re-run is a no-op; merge-on-name collapses a
  tag+category same-name pair to one link; a simulated two-device fold produces no duplicate category rows
  (id-reuse convergence).
- **This IS a synced-table data pass → Jon owes a two-device sync pass.** Confirm on device: (a) existing tags
  now appear as loose categories, (b) both devices converge with **no duplicate** category rows, (c) a recipe
  that had a tag shows it as a category and the library filter still finds it. **Back up first.** (Risk is
  lower than the ATK delete effort — the fold only *inserts* categories, it never deletes tags — but it writes
  synced tables, so two devices.)
- **Prod-schema promotion:** the new `categories.color` column is additive on an already-synced table → **add
  `categories.color` to the prod-schema promotion list in this slice's own PR** (not a separate doc edit). The
  fold itself adds no new record type.

## After S1

S2 (Tier-0 harvest + seed namespaces) is the natural next dispatch — also pure determinism, no model. S3 (the
`LabelProposer`) is the first model surface; S3+S4 and S5+S6 batch. See ADR-0049 § Slices.
