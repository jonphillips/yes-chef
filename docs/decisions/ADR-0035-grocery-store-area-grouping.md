# ADR-0035 — Group the grocery list by store area, categorized on-device

> **Vocabulary:** a *grocery item* (`GroceryItem`) is one line on a shopping list, already carrying a
> stored `aisle: String?` column and a `canonicalName` (from `CanonicalIngredient.canonicalName`). A
> *store area* (a.k.a. aisle / category / department) is the section of a store an item is bought in —
> Produce, Meat & Seafood, Dairy, etc. This ADR **populates** that dormant `aisle` field with a
> categorized store area and **groups the "To Buy" list by it**, so the list reads in shopping order
> instead of one flat pile.

Status: **Accepted** — 2026-07-12 (Proposed 2026-07-12). Origin: Jon's 2026-07-12 dogfood conversation ("Would be nice to
group items on the grocery list by areas of the store. Is this the one place where the onboard model can
finally help us?"). Holds the [[llm-vs-determinism-surface-boundary]] line — grocery is the deterministic
surface (ADR-0022/[ADR-0029](ADR-0029-main-thread-write-and-fetch-cost.md)), so the model's contribution
must be **stable across regenerations**, achieved by classify-once-then-cache, not by re-inferring on
every list build. Uses the on-device model tier ([[yeschef-onbard-model-tier]];
`LLMClientKit.OnDeviceModelClient` over Apple `FoundationModels`) — free, private, offline, no key.
Sync-safe by construction: `GroceryItem.aisle` is an **existing** synced column (`Schema.swift`), so
**no migration and no new prod-schema field**.

## Context

The grocery list renders as a single flat "To Buy" `Section` (`GroceryViews.swift`, a plain `ForEach`
over `displaySections.toBuyRows`). In a real shop you walk the store by department, so a flat list forces
constant back-and-forth. Three facts make this cheap to fix well:

1. **The field already exists and is dormant.** `GroceryItem.aisle` is a real, synced column; the row
   already *displays* it as a "· Dairy" suffix (`GroceryViews.detailText`) and the item editor already
   lets you hand-type it ("Aisle" field, prompt "Dairy"). What's missing is that **nothing populates it**
   — `shoppingCategory`/`aisle` is only ever carried through copy/adjust, never assigned on
   import/generation — and the list is **not grouped** by it.
2. **We have a canonical-name spine already.** Every item has a `canonicalName`, and there is an
   established "compute once, persist, never recompute" pattern in `GroceryCanonicalNameCache`. Store-area
   categorization is the same shape: a stable function of the canonical name.
3. **On-device inference is the right tool and it's already wired.** Earlier in this conversation the
   architect wrongly claimed the app had no on-device model. It does: `LLMClientKit`'s
   `TieredModelClient` treats `OnDeviceModelClient` (Apple `FoundationModels`) as the **default backend
   and the frontier degradation target**, and every YesChef AI verb already threads a `ModelTier`
   (`DepositNote`, `MakeAheadPlan`, chat, …). Because on-device inference is free/private/offline, there
   is **no per-call cost to ration** — which flips the design from "hand-maintained lookup table, model as
   fallback" to **model-first, cached**.

## Decision

**Categorize each grocery item's `canonicalName` into a store area once, on-device, persist it on
`GroceryItem.aisle`, and group the "To Buy" list by store area.** The taxonomy is an **open, growing
vocabulary** — the model returns a store-area string; we normalize it toward a canonical set but do not
hard-cap it at a fixed enum. (Jon: "there will be more than 6 buckets. That's the start.")

### The stability contract (the crux)

Grocery is the deterministic surface. A list where "chicken thighs" jumps from Meat to Other on the next
regen is worse than no grouping. Stability comes from **caching keyed on `canonicalName`, not from
avoiding the model**:

- Classify a canonical name **once**; write the result to `aisle`; **never re-classify** a name that
  already has one. Identical to `GroceryCanonicalNameCache`'s backfill discipline.
- A **seed/override table** (small, in-code) pins the store area for a starter set of common canonical
  names *before* the model is consulted — both a quality floor and the way Jon can correct a
  persistently mis-binned item without editing every row. This table is the "6 buckets to start" — a
  seed, **not** the closed taxonomy.
- Item-level user edits (the existing editor "Aisle" field) always win and are never overwritten by
  re-categorization.

### Vocabulary normalization (open, not closed)

The model emits free-form area strings; we map them onto a **canonical display set** with a normalizer
(lowercase + synonym fold: "veg"/"vegetables"/"produce" → Produce; "butcher"/"meat"/"seafood" → Meat &
Seafood; etc.), falling back to the model's own string (title-cased) when it matches nothing known. New
real areas thus appear organically; noise is folded. The canonical set also carries a **store-walk sort
order** (Jon-curated 2026-07-12): **Produce → Bakery → Deli → Canned & Dry → Condiments & Oils → Spices →
Baking → Beverages → Meat & Seafood → Household → Dairy → Frozen → Other** — cold/refrigerated departments
(Meat & Seafood, Dairy, Frozen) deliberately sit near the end so perishables are picked up last. Sections
render in this order, not alphabetically. Unknown/model-only areas sort just before "Other".

### Rendering

The "To Buy" `Section` becomes **one section per store area**, ordered by the store-walk sort, each with
its items. "Needs Review", "Assumed Pantry", and "Purchased" sections are unchanged. Empty areas do not
render. (Open question OQ2: whether Purchased also sub-groups — default **no**, keep it a flat crossed-off
tail.)

## Build slices

**S1 — deterministic seed + grouping (no model).** Ship the whole grouping experience table-only first, so
value lands without any inference risk:
- A `GroceryStoreArea` normalizer + canonical set + sort order + a seed override table over common
  canonical names, in `YesChefCore` (pure, fully unit-tested — the parsing/transform tier the house rules
  prize).
- On grocery generation/insert, populate `aisle` from the seed table when the item has no user-set aisle
  and no cached area.
- `GroceryViews`: split the flat "To Buy" `ForEach` into per-area sections in sort order. A backfill over
  existing items (mirror `GroceryCanonicalNameCache.backfill`) so current lists group immediately.
- Tests: normalizer synonym folding, sort order, seed hits, "user aisle wins", backfill idempotence.

**S2 — on-device classifier for the long tail.** For canonical names the seed table misses, a
`GroceryCategorizationClient` (a `ModelTier`-threaded client, mirroring `DepositNote`/`MakeAheadPlan`)
classifies on `.onDevice`, writing the result to `aisle` and thus caching it. Batched per generation
(classify only the *new, uncached* canonical names). Degrades cleanly: if on-device is unavailable
(`onDeviceUnavailable`), items simply stay in "Other" until later — never blocks list generation. Tests
with a stub client: uncached names get classified + cached, cached names are skipped, unavailable model
leaves items ungrouped without error.

### S2 dispatch detail (locked 2026-07-13)

Grounded against the merged S1 and the existing verb-client pattern:

1. **`GroceryCategorizationClient`** — new `YesChefCore/GroceryCategorization.swift`, mirror `MenuDepositClient`
   ([`DepositNote.swift`](../../YesChefPackage/Sources/YesChefCore/DepositNote.swift)) exactly: `Sendable`
   struct, `@Sendable classify(_ names: [String], _ tier: ModelTier) async throws -> [String: GroceryStoreArea]`,
   `DependencyKey` (live/test), `DependencyValues` accessor, tolerant static `parse`. **Batched**, one
   `ModelRequest(tier:.onDevice, reasoningEffort:.low)` per chunk (~40 names) asking for a strict JSON
   name→area map; **fold every value through `GroceryStoreArea.normalized(_:)`** so the open vocabulary stays
   canonical/round-trippable. No `promptPreferenceKey` (no new synced settings — hold the no-schema promise).
   Chunk to survive `onDeviceContextTooLarge`. `testValue = [:]`.
2. **Cache read/write** — extend `GroceryStoreAreaCache`: `uncategorizedCanonicalNames(in:)` (distinct
   `canonicalName` where `aisle == nil`) and `applyClassified(_:in:)` (write `area.title` only where still
   `aisle == nil`; never overwrite user/seed/prior — the stability contract; idempotent).
3. **Off-writer sequencing** ([[sqlitedata-fetch-writer-convoy]]): read uncached names → classify (async, **no
   transaction**) → `applyClassified` (write tx). Never run the model call inside `database.write`.
4. **App wiring** (`GroceryLibraryModel`): `.onDevice` tier; run the pass **after each generation path**
   (`addRecipeImmediately`/`addMenuImmediately`/`addMealPlan…`/multi-source `addSelected…`) **and once on
   grocery-detail appearance** guarded by `uncategorizedCanonicalNames` non-empty (LOCKED 2026-07-13: both
   triggers, so existing lists fill the long tail without a regen). Reload `itemRows` after the write.
   **Degrade silently** — `try?`/swallow; `onDeviceUnavailable` or any error leaves items under "Other", no
   alert.
5. **Tests** (stub client, `@testable`): uncached→classified+written; existing-aisle item skipped even if the
   stub returns otherwise; stub throwing `onDeviceUnavailable` leaves `aisle == nil` with no error; model
   output folded through the normalizer; `parse` tolerates malformed JSON → `[:]`.

Verify: package build + the new tests + `swift test --skip-build`; `check-drift.sh`; one iPad build
(`xcodegen generate` first — new source file). Device pass (Jon): generate a list with off-seed items
(harissa, miso, gochujang) → sensible departments, stable across regen; a device without on-device support
leaves them under "Other" with no error.

## Consequences

- **No migration, no prod-schema delta.** `aisle` already exists and syncs; categorization is a write to
  an existing column. (The standing release follow-up list is unchanged by this ADR.)
- **Deterministic-surface line held.** The model influences *placement*, cached and stable; it never
  invents or merges list *data* — quantities, item identity, and dedup stay fully deterministic
  ([[llm-vs-determinism-surface-boundary]]).
- **First real on-device verb in YesChef.** Everything to date routes frontier-preferred; this is the
  first that is `.onDevice` by design. Validates the tier for cheap/private classification and is a
  template for future on-device-first verbs.
- S1 is shippable and useful alone; S2 is purely additive quality. Natural batch = S1 as one dispatch,
  S2 as a follow-on once S1's grouping reads well on device.

## Open questions

- **OQ1 — seed taxonomy — RESOLVED (order) 2026-07-12.** The **canonical set + store-walk order is
  fixed** to Jon's 13 areas above (Produce → Bakery → Deli → Canned & Dry → Condiments & Oils → Spices →
  Baking → Beverages → Meat & Seafood → Household → Dairy → Frozen → Other). Still open, but non-blocking:
  the **seed mapping contents** (which common canonical names pre-bind to which area) — curatable
  incrementally in S1's in-code table, doesn't gate the build.
- **OQ2 — Purchased sub-grouping.** Default no; revisit if the crossed-off tail gets long.
- **OQ3 — per-list store profiles.** Different stores have different layouts; a future refinement could
  make the sort order a per-list setting. Out of scope here — one global order to start.
