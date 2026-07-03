# Current Handoff

Last updated: July 3, 2026 (Dogfood batch 3 approved, PR #75 → DONE-LOG. Next Up = Phase E, first
dispatch shaped with Jon: Slice 1 + 2 batched (canonical key + `Measure`, pure-core, no migration;
`canonicalName` cache deferred to Slice 3). Ready to dispatch to Codex. Lean verification is the default.)

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

**Phase E — grocery/pantry, first dispatch: Slice 1 + Slice 2 batched.** Full spec + build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md)
(read it and the **architect amendment 2026-07-03** near "The slices"; boundaries in
FUTURE_INTELLIGENCE §7.5/§13/§14). One PR, both slices, pure-core `YesChefCore`, **no UI, no schema
migration**:
- **Slice 1 — one canonical key + alias table.** Introduce `CanonicalIngredient.canonicalName(_:)` as
  the single normalizer + a **data** alias/override table (replacing the `anchovy → anchovies` `switch`
  at `GroceryCore.swift:1015` and absorbing the `defaultStaples` list). Re-point `canConsolidate` and
  `isPantryStaple` at this one key; delete/collapse `groceryConsolidationKey` and `normalizedPantryText`.
  **Compute the key on read — do NOT add a `canonicalName` column** (that cache is deferred to Slice 3
  per the amendment). No behavior change: nothing hidden today becomes visible.
- **Slice 2 — bounded `Measure` compare/merge.** Known units → dimension (volume/weight/count) with
  conversion factors; `merge` combines only same-dimension known units (`8 oz + 1 lb → 24 oz`),
  else rows stay separate; `compare(total, threshold) → .over/.underOrEqual/.incomparable`. No
  cross-dimension guessing, no invented factors.
- **Tests, no UI/model:** anchovy pair + scallion/green-onion + a plural pair merge via the alias table
  with no code branch; both old normalizers' behaviors preserved; within-dimension merges; cross-dim /
  unknown-unit pairs report incomparable. Guard the **no-inventory** boundary (§14) — static rules only.
- **Do NOT build** Slice 3 (pantry policy + the deferred `canonicalName` migration) or Slice 4
  (`PantrySuppression` + review UI) — those are the next dispatches.

Dogfood batch 3 is **complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG). The cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its named
follow-ons — **Menu + Meal-Planner chat verbs** and **reader photo affordances** — live in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate later efforts.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Recipe → grocery list w/ pantry checking** (Phase E) — **now Next Up**, first dispatch = Slice 1 + 2
  batched (canonical key + `Measure`, pure-core, no migration; `canonicalName` cache deferred to Slice 3).
  Build order + architect amendment (2026-07-03) in
  [`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md);
  design rationale = [[grocery-pantry-threshold-design]]. Slices 3–4 follow as later dispatches.

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
