# Current Handoff

Last updated: July 3, 2026 (Phase E Slice 1 + 2 approved, PR #77 → DONE-LOG. Next Up = Phase E Slice 3 —
pantry policy model + the deferred `canonicalName` cache migration (one synced-schema change; **must-flag
the sync-zone implications in the PR**). Ready to dispatch to Codex. Lean verification is the default.)

The **short entry point** for a fresh Yes Chef conversation. This file is deliberately lean: it holds
**Next Up** (the dispatch target), the **Ready Efforts** queue, and the **Verification Pattern** —
nothing else. Completed-slice history, the implemented-behavior checkpoint, and strategic background
live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**Single dispatch target.** Dispatch to the coding agent with:
*"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."* If this section is empty, missing, or
ambiguous, the agent must **STOP and ask Jon — never infer the next task.** See
`docs/AGENTS.md` § Work Intake & Dispatch. A dispatch may bundle **several cohesive slices** (one
PR); do all listed, in order.

**Phase E — grocery/pantry, Slice 3: pantry policy model + the deferred `canonicalName` migration.**
Full spec + build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md)
(read the **Slice 3** section and the **architect amendment 2026-07-03** near "The slices"; boundaries in
FUTURE_INTELLIGENCE §7.5/§13/§14). One PR — this is the milestone's **single synced-schema change**, so
it carries both the pantry policy columns and the `canonicalName` cache deferred out of Slice 1:
- **Pantry policy on `PantryItem`.** Add `isUnlimited: Bool` (default **true** — new items never show),
  `thresholdQuantity: Double?`, `thresholdUnit: String?` (both nil when unlimited or when threshold 0 =
  "always confirm"). **Migration-aware backfill:** existing pantry items → `isUnlimited = true` so current
  suppression is unchanged. Threshold is a **static rule — no depletion / on-hand / inventory anywhere**
  (§14 boundary, the one most likely to erode — guard it in code and tests).
- **The deferred `canonicalName` cache.** Add `canonicalName: String?` to `IngredientLine` / `GroceryItem`,
  backfilled from existing rows via the Slice-1 `CanonicalIngredient.canonicalName(_:)` so nothing already
  hidden becomes visible. Re-point the Slice-1 compute-on-read call sites at the cached column. **One
  migration carries both** the policy and the cache.
- **Editor UI:** a per-item control — *Always have it (never show)* / *Remind me if a recipe needs more
  than [qty][unit]* / *Always confirm*. **Threshold control is offered only for measure-unit items**
  (volume/weight); count-y items (garlic cloves) show only unlimited-or-shop (Decision #6 — a "½ clove"
  threshold is nonsense).
- **Tests:** migration preserves current behavior; the three policy states round-trip; threshold 0 =
  always confirm; a count-y item exposes no threshold field; the `canonicalName` backfill hides nothing new.
- **MUST-FLAG in the PR:** the schema change vs. the sync milestone's CloudKit zone — confirm the
  zone implications, don't assume ([[sqlitedata-blob-cloudkit-asset]]: additive-nullable columns, UUID PKs,
  no unique index → sync-safe, but state it explicitly).
- **Do NOT build** Slice 4 (`PantrySuppression` pure function + grocery-list review UI) — that is the
  next and final dispatch for this milestone.

Phase E Slice 1 + 2 (canonical key + `Measure`) is **complete** (PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG). The cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its named
follow-ons — **Menu + Meal-Planner chat verbs** and **reader photo affordances** — live in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate later efforts.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Recipe → grocery list w/ pantry checking** (Phase E) — in progress. Slice 1 + 2 (canonical key +
  `Measure`) **complete** (PR #77 → DONE-LOG). **Now Next Up = Slice 3** (pantry policy model + the
  deferred `canonicalName` migration — the milestone's single synced-schema change). Build order +
  architect amendment (2026-07-03) in
  [`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md);
  design rationale = [[grocery-pantry-threshold-design]]. Slice 4 (`PantrySuppression` + review UI) follows.

- **Dogfood fixes — batch 3** — complete (PR #75 → DONE-LOG; ingredient structure · Chef It Up +
  Serve With · substitution · keep-awake). Non-blocking device-pass notes recorded in the DONE-LOG entry.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Cooking workspace** — **complete** (Slices A + B, PRs #73 / #74 → DONE-LOG). Menu + Meal-Planner chat
  verbs and the reader **photo affordances** (manual set-as-cover, pinch-zoom in the viewer) are named in
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as later efforts (host built
  context-general to receive them).

**Parked (not dispatched):**
- **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook from
  them (phone captures / iPad cooks, exercising the untested multi-device dedup-on-read convergence).
  Blocked on Apple shipping iOS Beta 3; Jon's simulator-pass feedback still marinating. The most
  annoying gaps found here still choose the real next milestone after the dogfood batch.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work
history and the implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

## Verification Pattern

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the
device pass regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files.
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise build `YesChef` **once** for `iPad Pro 13-inch (M5) (16GB)` (`-skipMacroValidation`).
- Run `scripts/check-drift.sh`.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
