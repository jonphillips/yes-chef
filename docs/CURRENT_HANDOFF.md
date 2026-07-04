# Current Handoff

Last updated: July 4, 2026 (**ADR-0012 Slice 1 shipped** — `.menu` context + grounded chat, PR #81 →
merged to main, approved. **Next Up = ADR-0012 Slice 2** — the menu prep-plan verb → `Menu.prepPlan`
(additive `Data?` BLOB, first schema touch of this effort). Lean verification is the default.)

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

**ADR-0012 Slice 2 — the menu prep-plan verb → `Menu.prepPlan`.** Read
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md) first —
Accepted, five decisions resolved, do not re-open them. S1 (`.menu` context + grounded chat) shipped in
PR #81; this dispatch is **S2 only** (S3 complement is a **separate later dispatch** — do not build it here).

S2 concretely (ADR-0012 Decisions #1 + #4):
- Add the additive column **`Menu.prepPlan: Data?`** — a Codable BLOB of
  `PrepPlanStep { when: String; task: String; sourceDish: MenuItem.ID? }`. `when` stays a **String**
  (relative-day label, e.g. "morning of day 2"); `sourceDish` is a **nullable** `MenuItem.ID` back-pointer.
  Additive-nullable, sync-safe — this is the **`serveWith` storage pattern**, not new infra
  ([[sqlitedata-blob-cloudkit-asset]]). No reserved columns, no unique index.
- Add the **prep-plan apply-action + review card** to the menu apply-action catalog (which S1 left empty),
  routed through the existing staging card so **the tap writes** — no chat turn mutates the menu on its own.
- The verb **composes and sequences the existing per-recipe `makeAhead` notes** already fed into the S1
  serialization; it must **not** re-generate per-dish make-ahead prose (Decision #4, vocabulary hygiene:
  "prep plan" ≠ "make-ahead").
- Add the menu **prep-plan section**: timeline/checklist render of the stored steps, plus **regenerate** and
  **clear** affordances. The plan is a **passive snapshot** — do not auto-recompute on menu edits; the
  `sourceDish` back-pointer only makes staleness detectable (ADR-0010 provenance posture).

Classify commit shape before extending later verbs: [[chat-verb-commit-shapes]] (prep-plan is a structured
staged-list commit, not one-field-per-verb). **Schema note:** this is the first schema touch of the effort —
fold it into the standing "promote CloudKit fields to prod schema before any TestFlight cut" follow-up below.

**Standing release follow-up carried from Phase E (not a dispatch on its own):** before any prod/TestFlight
cut, promote the Slice 3 pantry-policy + `canonicalName` CloudKit fields to the **production** schema, and
note the app target (`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

Phase E is **fully complete** — Slice 4 (`PantrySuppression` + review UI, PR #80 → DONE-LOG), Slice 3
(pantry policy + `canonicalName` migration, PR #79 → DONE-LOG), Slices 1 + 2 (canonical key + `Measure`,
PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG). The cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its named
follow-ons — **Menu + Meal-Planner chat verbs** and **reader photo affordances** — live in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate later efforts.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Recipe → grocery list w/ pantry checking** (Phase E) — **complete.** All four slices shipped: canonical
  key + `Measure` (PR #77), pantry policy + `canonicalName` migration (PR #79), `PantrySuppression` + review
  UI (PR #80) — all → DONE-LOG. Design rationale = [[grocery-pantry-threshold-design]]. Standing release
  follow-up (promote CloudKit fields to prod schema) noted under Next Up.

- **Actionable chat / LLMClientKit** (ADR-0011) — **complete.** The lift (Slice 1, 3 repos) + make-ahead
  (Slice 2) + Chef It Up / Serve With / per-line substitution shipped 2026-07-02/03 (PRs #73–#75 →
  DONE-LOG); `LLMClientKit` is a live path-dep. Remaining named-later verbs (**Menu + Meal-Planner chat
  verbs**) live in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md); classify each new
  verb's commit shape first ([[chat-verb-commit-shapes]]).

- **Dogfood fixes — batch 3** — complete (PR #75 → DONE-LOG; ingredient structure · Chef It Up +
  Serve With · substitution · keep-awake). Non-blocking device-pass notes recorded in the DONE-LOG entry.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Menu actionable chat** (ADR-0012, **Accepted** 2026-07-03) — the Menu-scope instance of actionable
  chat. **S1 shipped** (`.menu` context + composite grounding + grounded chat, PR #81 → DONE-LOG, no schema).
  **S2 is now in Next Up** (prep-plan verb → `Menu.prepPlan`). S3 complement verb → inserts a `MenuItem` is
  the remaining slice. The Planner-day (`MealPlanItem`, absolute-date) version is a **separate follow-on
  ADR**, not this effort. Design + all five resolved decisions in
  [`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Cooking workspace** — **complete** (Slices A + B, PRs #73 / #74 → DONE-LOG). Its Menu chat-verbs
  follow-on is now its own effort above (ADR-0012). The reader **photo affordances** (manual set-as-cover,
  pinch-zoom in the viewer) remain a named later effort in
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) (host built context-general to
  receive them).

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
