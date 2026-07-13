# ADR-0037 — Seed-coverage diagnostic: a review queue for grocery store-area misses

> **Vocabulary:** the *seed table* is `GroceryStoreArea.seedAreas` — a small, in-code
> `[canonicalName: GroceryStoreArea]` dict that pins a store area for common canonical names *before*
> the on-device model is consulted ([ADR-0035](ADR-0035-grocery-store-area-grouping.md), the deterministic
> quality floor). A *seed miss* is a canonical name for which `GroceryStoreArea.seed(for:)` returns `nil`.
> This ADR builds **visibility** into which canonical names miss the seed table, so Jon has a de-duped,
> prioritized **review queue** to curate `seedAreas` in code.

Status: **Accepted** — 2026-07-13 (Proposed 2026-07-13). Origin: post-ADR-0035 session note ("build the visibility for items that
did not match deterministically — a diagnostic that surfaces which canonical names miss `seed(for:)` — so
Jon has a review queue to review and add to code"). This is ADR-0035 **OQ1's** open half — the seed mapping
*contents* are curated incrementally, and this is the instrument that tells Jon what to curate. Read-only,
dev-facing, **no schema change, no sync surface** — a pure `YesChefCore` computation plus a thin Settings view.

## Context

ADR-0035 gives grocery items a store area two ways: the deterministic **seed table** (stable, free, offline,
works when on-device inference is unavailable) and the **on-device classifier** (S2, fills the long tail). The
seed table is the only *stable* floor: it is the sole cross-generation memory for placement. There is
deliberately **no persistent `canonicalName → area` cache** ([[grocery-area-no-learned-cache]]) — the model's
result is cached only on the ephemeral `GroceryItem.aisle` column, so a name that leaves the list re-infers
next time and can drift. **The way to make a placement permanently stable is to add it to `seedAreas` in code.**

Today Jon has no view of what is falling through. The misses are invisible: an item with a model- or
user-assigned `aisle` looks identical to a seed hit. Curating `seedAreas` is therefore guesswork. Two facts
make a good diagnostic cheap:

1. **A seed miss is a pure function of the canonical name**, recomputable at will — `seed(for:) == nil`.
   It must be recomputed fresh; **`aisle == nil` is not the signal** (the model/user may have filled it).
2. **The canonical-name corpus already persists durably** in the DB — every `IngredientLine` and every
   `GroceryItem` carries a backfilled `canonicalName` (`GroceryCanonicalNameCache`). No ledger, no new table,
   no sync concern: the review queue is *derived*, and it auto-shrinks the moment Jon adds a seed and rebuilds.

## Decision

**Add a pure `SeedCoverageReport` computation in `YesChefCore` that scans the durable canonical-name corpus,
keeps the names that miss the seed table, de-dupes and frequency-counts them, splits them into *uncovered* vs
*covered-elsewhere*, and carries each name's current stored `aisle` as a suggested area. Render it in a new
`Settings → Developer` section, with a "copy as Swift literal" export that emits paste-ready `seedAreas` lines.**

### Corpus (locked 2026-07-13)

Distinct `canonicalName` across the **union of `IngredientLine` and `GroceryItem`** rows. `IngredientLine`s are
permanent, so the queue front-loads the whole recipe library and keeps growing as recipes are added; grocery
items add manual one-offs that never came from a recipe. (Pantry items deliberately excluded — keep the corpus
to things that reach, or feed, a shopping list.) Names with a `nil`/empty canonical name are skipped.

### What counts as a miss, and how it's split (locked 2026-07-13)

For each distinct canonical name where `GroceryStoreArea.seed(for: name) == nil`:

- **Uncovered** — no non-empty `aisle` exists on *any* row for this canonical name. These land in "Other" on the
  list (pre-S2) or lean entirely on the model (post-S2). **Highest priority** — seeding these is the biggest
  stability win.
- **Covered elsewhere** — a seed miss, but at least one row already has a non-empty `aisle` (model- or
  user-assigned). The placement works today but is not *stable*; promoting the guess into `seedAreas` pins it.
  The most-common stored `aisle` for the name becomes the **suggested area**, prefilling the export.

Within each group, sort by **occurrence count desc, then canonical name asc** — most-impactful first, stable ties.

### Shape (pure core)

```swift
// YesChefCore, pure + fully unit-tested (no DB, no I/O in the compute step).
public struct SeedCoverageReport: Equatable, Sendable {
  public struct Gap: Equatable, Sendable, Identifiable {
    public var canonicalName: String
    public var occurrences: Int
    public var suggestedArea: GroceryStoreArea?   // most-common stored aisle, if any
    public var id: String { canonicalName }
  }
  public var uncovered: [Gap]          // no stored aisle anywhere — sort: count desc, name asc
  public var coveredElsewhere: [Gap]   // has a stored aisle — suggestedArea non-nil
}

extension SeedCoverageReport {
  // Pure: takes already-fetched (canonicalName, aisle?) pairs so the compute is trivially testable.
  public static func make(from observations: [(canonicalName: String?, aisle: String?)]) -> Self
}
```

A thin DB adapter (mirroring `GroceryStoreAreaCache`) gathers the observations off the durable corpus and hands
them to `make`. Keep the SQL read out of the pure function.

### Export

A **"Copy seed entries"** action per group (and per row) that emits paste-ready Swift dict literal lines, sorted
the same way, area-guess prefilled where known:

```
"harissa": .condimentsAndOils,   // covered-elsewhere → suggestedArea filled
"sumac": .other,                 // uncovered → .other placeholder for Jon to correct
```

`.other` is the honest placeholder for uncovered names — Jon edits the area, not the key. This closes the loop:
review queue → clipboard → paste into `seedAreas` → rebuild → entry drops off the queue.

### Placement (locked 2026-07-13)

New **`Developer`** `Section` in `SettingsView` (`SettingsViews.swift`), a `NavigationLink`/pane row →
`SeedCoverageView`. **Always visible** (single-user app; no `#if DEBUG` / launch-arg gate). De-emphasize
visually — it sits below Import & Export. The view shows the two groups as `List` sections with counts in
headers, each row `canonicalName · ×N · suggested-area`, tap-to-copy that name's literal, and a
copy-all-in-group toolbar/button.

## Build slices

**S1 — pure report + core adapter (no UI).**
- `SeedCoverageReport` + `make(from:)` in `YesChefCore`. Fully unit-tested: seed hits excluded; miss with no
  aisle → uncovered; miss with an aisle → coveredElsewhere with the *most-common* aisle as `suggestedArea`;
  case/whitespace fold via the same canonical pipeline; count + sort order; a name that appears both covered and
  uncovered across rows resolves to **coveredElsewhere** (any stored aisle wins).
- DB adapter on `GroceryStoreAreaCache` (or a sibling): `seedCoverage(in:) -> SeedCoverageReport` gathering
  distinct `(canonicalName, aisle)` observations across `IngredientLine ∪ GroceryItem`.
- Swift-literal export helper (pure, tested): given a `[Gap]`, emit the sorted dict-literal string.

**S2 — Settings Developer view.**
- `SeedCoverageView` reading the adapter; `Developer` section + row in `SettingsView`.
- Two grouped `List` sections, counts in headers, copy-per-row + copy-per-group (`UIPasteboard`).
- Reload on appear (and on `DatabaseChangeBeacon.didChange`, mirroring the sync-health refresh hook) so it
  reflects the current library without a manual refresh.

Natural batch: S1+S2 as one dispatch (small, cohesive). S1 alone is the testable spine if it needs splitting.

## Verify

Package build + the new `YesChefCore` tests + `swift test --skip-build`; `check-drift.sh`; one iPad build
(`xcodegen generate` first — new source files). No simulator installs ([[lean-verification-default]]) — Jon does
the device pass: open `Settings → Developer → Seed Coverage`, confirm off-seed names (harissa, miso, gochujang)
appear with sensible groups/counts, copy a group, paste, confirm it drops off after adding to `seedAreas`.

## Consequences

- **No migration, no prod-schema delta, no sync surface.** Purely derived from existing durable columns; nothing
  new is written or synced. Consistent with ADR-0035's no-schema promise.
- **Closes ADR-0035 OQ1's curation loop.** Turns "guess what to seed" into a prioritized, paste-ready worklist,
  and directly strengthens the deterministic floor that the [[llm-vs-determinism-surface-boundary]] line depends
  on — every promoted seed is one fewer name relying on drift-prone model placement.
- **Dev-facing, low-stakes.** Read-only; the only side effect is clipboard. Safe to ship always-on.

## Open questions

- **OQ1 — occurrence weighting.** Count is raw row occurrences (a recipe used 5× still counts its lines once per
  line). Fine as a priority signal; revisit if it over-weights prolific recipes.
- **OQ2 — synonym pre-fold.** The report shows *canonical* names; if two surface spellings canonicalize the same,
  they already merge. No action unless the canonicalizer itself is under-folding (separate concern).
