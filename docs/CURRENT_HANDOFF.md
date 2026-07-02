# Current Handoff

Last updated: July 2, 2026

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

- **Dogfood fixes — batch 1, Slice 7 — Edit a grocery item (name + amount).**
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) §Slices 8–9. Two
  independent, self-contained UX wins — do both, in order, in this one dispatch/PR:
  - **Slice 8 — Scale a recipe by a multiplier.** Add a direct ×2/×3 (and/or free) multiplier that
    scales ingredient quantities and **displays the resulting servings count** after scaling. Add it
    as a parallel control — do **not** remove servings-based scaling. **Done when:** Jon can
    double/triple a recipe directly and see the resulting servings.
  - **Slice 9 — Add an image to a manually-entered recipe.** Add a photo picker to the manual recipe
    editor, reusing the existing image storage/processing path (ADR-0005; hero images already sync as
    CKAssets — no schema change). **Done when:** a manually-created recipe can have a hero image added,
    and it displays and syncs like a captured one.

  **After this:** batch 1 is complete. The Slice 7 delete-source-clobbers-amount-edit follow-up is
  parked in the effort doc for a later grocery slice — **not** part of this dispatch.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Dogfood fixes — batch 1 (bugs + near-term UX)** — closing out.
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md). Slices 1–7 done (see
  [DONE-LOG](DONE-LOG.md) / effort doc); Slices 8–9 are Next Up (last of the batch).

- **Recipe → grocery list w/ pantry checking** (Phase E) — make it slick early (canonical-key merge,
  static pantry thresholds, dialog-free); spec = [[grocery-pantry-threshold-design]]. Lower priority
  than the dogfood batch per Jon's stated intent (2026-07-01).

**Parked (not dispatched):**
- **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook from
  them (phone captures / iPad cooks, exercising the untested multi-device dedup-on-read convergence).
  Blocked on Apple shipping iOS Beta 3; Jon's simulator-pass feedback still marinating. The most
  annoying gaps found here still choose the real next milestone after the dogfood batch.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work
history and the implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

## Verification Pattern

Before checkpointing UI work:

- Run `xcodegen generate` after adding Swift source files.
- Build `YesChef` for `iPad Pro 13-inch (M5) (16GB)`.
- Run `scripts/check-drift.sh`.
- Install and launch on both active iOS 27 simulators:
  - `iPad Pro 13-inch (M5) (16GB)`
  - `iPhone 17 Pro`

Jon performs the primary UI testing pass.
