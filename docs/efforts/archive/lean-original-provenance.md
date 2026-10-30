# Effort: Lean original-provenance (sync-ready "original" without the bloat)

**Type:** Data hygiene / sync prep (precedes the iCloud sync gate — see ADR-0002)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Ready Effort — should land **before** the clean re-import that precedes the sync flip,
so the synced store carries lean provenance from day one.

## Motivation

Each recipe keeps an "original" so Jon can look back and see how far an augmented recipe has
drifted from what was imported. We want to keep that capability but stop carrying redundant
weight into the (soon) iCloud-synced recipe record. Two columns on `recipes` hold provenance,
and each has a distinct problem.

## Root cause (verified)

There are **two** original-provenance columns, not one:

1. **`originalSnapshot`** (`Models.swift:30`, BLOB in `Schema.swift:63`) — a structured,
   versioned JSON `RecipeBundle` (`RecipeBundleCoding`, `RecipeCore.swift:803`), captured once at
   import and frozen (the `== nil` guards at `RecipeCore.swift:362`, `RecipeRepository+Import.swift:423`,
   `PaprikaHTMLImport.swift:205`, `ParsedRecipePage.swift:181` mean edits never overwrite it). It
   already holds the full structured recipe — ingredient sections + lines, instruction sections +
   steps, notes, tags, categories, equipment — and is therefore already field-for-field diffable.
   - **The bloat:** `snapshotData(...)` takes a `photos:` argument (`RecipeCore.swift:881`) and the
     import path passes `photos: bundle.photos` (`RecipeRepository+Import.swift:434`). `RecipePhoto`
     is `Codable` with `displayData`/`thumbnailData` as `Data?` (`Models.swift:765`), so JSONEncoder
     base64-encodes the JPEG bytes **into** the snapshot — ~1 MB+ per photo, inflated ~33%, fully
     redundant with the `recipePhotos` rows (which already sync as CKAssets; see
     `memory/sqlitedata-blob-cloudkit-asset.md`).
   - **Nobody reads those bytes.** `OriginalSnapshotView` decodes the snapshot
     (`OriginalSnapshotView.swift:14`) and renders title/source/ingredients/instructions/notes/
     tags/categories (`:42–46`) — it **never** touches `photos`. The embedded bytes are dead weight.

2. **`originalImportText`** (`Models.swift:29`, TEXT) — the **raw page HTML**, populated at import
   (`PaprikaHTMLImport.swift:203`, `ParsedRecipePage.swift:179`). Its **only** reader is a
   `#if DEBUG` DOM-export toolbar action (`OriginalSnapshotView.swift:90`). In a release build it is
   persisted — and would sync — but never read. This is the "giant blob of HTML, better for
   debugging" we don't want to carry around.

## Decision (settled with Jon)

- **Keep the original as a frozen structured blob; do _not_ model it as a suppressed `Recipe`
  row.** A second recipe row would impose a permanent `WHERE NOT isOriginal` filter on every
  recipe query (library/search/grocery/calendar/menus/counts), double the synced relational graph
  and assets, and require identity/lifecycle guards everywhere. The blob decodes into the **same**
  `Recipe`/`IngredientLine`/`InstructionStep` structs the views already use, so a read-only view
  gets full rendering reuse with zero persisted rows and zero query pollution.
- **Strip image bytes from the snapshot** — the compare is about text drift, not pixels, and the
  live images already sync as assets.
- **Stop carrying raw HTML into synced data** — keep it for debugging only.

## Design

### Part A — Lean snapshot encoder (core, sync-relevant)

Centralize the fix in `snapshotData(...)` (`RecipeCore.swift:871`) so all four call sites are
covered regardless of what each passes:

- Before building the `RecipeBundle`, map `photos` to copies with `displayData = nil` and
  `thumbnailData = nil`. **Keep the photo metadata** (id, kind, caption, sortOrder, sourceURL,
  checksum, pixel dims) — it's tiny and lets the original record "there was a hero from this URL."
- Do **not** change `RecipeBundle` itself or the transfer/export path. `RecipeBundle` is also the
  recipe-transfer format (ADR-0003; decoded at import), where embedded photo bytes are legitimate.
  Only the **snapshot** is leaned.
- `decodeSnapshot` and `OriginalSnapshotView` are unchanged (the view already ignores photos).
- Version field (`RecipeBundle.version`): bumping to mark "lean" is optional — decode is
  byte-compatible (nil `Data?` either way). Implementer's call.

### Part B — Raw HTML stays local/debug-only (core, sync-relevant)

Stop persisting `originalImportText` into the committed recipe in normal operation:

- Preferred: thread an import option (e.g. `preserveRawImportHTML`, default **false**) through the
  import paths so production/synced recipes get `nil`, and dev/debug can opt in to keep the
  DOM-export tool working. This is testable and avoids a library-vs-app `#if DEBUG` mismatch.
- Acceptable minimal fallback: gate population behind `#if DEBUG` to match the existing
  DEBUG-only reader.
- No schema change — the column stays nullable; we just stop writing it in release.

### Part C — "Compare to original" view (the payoff; separable follow-on)

Evolve `OriginalSnapshotView` (or add a sibling) from "show the original" into "show the drift":

- Load the **live** recipe's structured rows via the existing detail/repository read path and the
  decoded snapshot, then present them section-by-section (ingredients, instructions, notes,
  title/summary/times/servings) with simple change highlighting.
- **v1 matching is deliberately shallow:** align lines by `sortOrder`, flag added/removed/edited
  by text equality. Do **not** attempt fuzzy reorder-aware line matching — call that a later
  refinement if the shallow diff proves noisy.
- Purely additive, local, read-only — no schema, no identity, sync-irrelevant. Safe to split into
  its own slice if Part A/B should land first to unblock the re-import.

## Scope decisions

- **In scope:** lean snapshot encoder (strip image bytes, keep metadata); stop syncing raw HTML
  (option-gated, default off); a v1 compare-to-original view.
- **Out of scope:** modeling originals as `Recipe` rows; migrating existing fat snapshots (the
  clean re-import regenerates them lean — see Sync-safety); reorder-aware diff matching; gallery/
  multi-photo handling in the compare view.

## Sync-safety (forward note)

- **No DDL.** Both columns stay; only the *contents* we write change. Nothing here touches
  identity or the `SyncEngine` table set.
- **Ordering matters.** Land this **before** the clean re-import that precedes the sync flip, so
  every snapshot in the synced store is lean from day one and no fat-blob migration is ever needed.
  Pre-sync dev already discards data via `eraseDatabaseOnSchemaChange` + re-import.
- This closes the open "should `originalSnapshot` ride the synced recipe record?" question: yes —
  once lean it's a few KB of text, trivially fine to sync.

## Verification

- **Unit (deterministic):** import a recipe with a hero photo (existing fixtures), decode its
  `originalSnapshot`, assert every photo has nil `displayData`/`thumbnailData` but retained
  metadata, and assert the encoded byte size is in the low-KB range (regression guard against the
  bytes creeping back in). Assert a release-config import yields `originalImportText == nil` while a
  preserve-HTML import retains it.
- **Round-trip untouched:** assert the recipe-transfer `RecipeBundle` path still carries photo
  bytes (Part A must not leak into transfer/export).
- `swift test --package-path YesChefPackage` green; `scripts/check-drift.sh` clean.
- Jon UI pass: open "Original" on an augmented recipe → structured original renders; (Part C) drift
  highlighting reads correctly against the live recipe.

## Open questions for the implementer to confirm

- Exact seam to load the live recipe's structured rows for the Part C diff (reuse the detail
  model's existing fetch vs. a dedicated read).
- Whether to bump `RecipeBundle.version` for lean snapshots (optional; decode is compatible).
- Whether `preserveRawImportHTML` belongs as an import option vs. a `#if DEBUG` gate — prefer the
  option for testability unless it forces awkward plumbing.

---
*Derived from the iCloud sync planning session (2026-06-30). Companion facts in
`memory/sqlitedata-blob-cloudkit-asset.md`. Precedes the sync milestone (ADR-0002).*
