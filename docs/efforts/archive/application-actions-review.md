# Effort: Application Actions Review (2026-08-02)

**Status:** Reviewed, dispositioned. One new track; the rest absorbed or parked.
**Provenance:** External brief ("Preparing Application Actions for Shortcuts, App Intents, and Alternate Interfaces") drafted in a ChatGPT discussion, reviewed against `main` and the ADR log on 2026-08-02.

## Why this exists

The brief asks whether Yes Chef's capabilities are callable from surfaces other than SwiftUI views — keyboard shortcuts, Apple Shortcuts, App Intents, a hypothetical Stream Deck or remote iPad. It proposes an explicit application-action layer between the views and the domain.

The thesis is sound and the app has real evidence for it, but the brief was written without knowledge of the house stack or the decision log, so most of what it proposes is already decided, in flight, or deliberately rejected. This doc records the disposition so the brief doesn't get re-litigated.

## The thesis, restated with our own evidence

The brief argues abstractly that the UI should trigger capabilities without owning them. Two shipped defects prove it concretely:

- **ADR-0041 S2** — `matches()` cross-wires two sections' pasted results because both are `.recipe` with the same id. The routing decision lived where the view happened to put it.
- **ADR-0045** — `chatButtonTapped` is an unscoped view-level visibility toggle that seeds no prompt, so `canRun` grays every apply-verb and the cook concludes the feature was removed.

Both are capabilities owned by a view. That is the argument, and it is ours, not speculative.

## What the brief does not know

- We already have a layer below the views: pure repository functions over an explicit `Database`, plus `@Observable` feature models and swift-navigation `Destination` enums. The open question is not "add an application layer" but "what belongs between repositories and feature models."
- The brief's proposed `AppDestination` enum collides with **ADR-0046**, whose central finding is that the section taxonomy is already encoded four times in three incompatible partitions. A fifth parallel enum repeats the defect being fixed. **Do not add one.**
- The AI-handoff actions it proposes already exist: **ADR-0042/0038** give nine verbs behind one `AIHandoffTaskType`, and **ADR-0043 D1** routes every `ModelRequest` through a chokepoint recording surface, task, tier resolution, context layers, budget and effort.
- Its "which actions can't run independently" question is answered by **ADR-0029 S1** — quick mutations run synchronous `database.write` on the `@MainActor` model. That slice is the prerequisite for any headless execution.
- Its App Intent entity list needs an **ADR-0040** grain check. Serve With is not rows until **ADR-0048 S3**. Make Ahead and Chef It Up are deliberately prose (**ADR-0048 D4**) and therefore can never be App Intent entities. That is correct, not a gap.

## D1 — Commit authority becomes a typed, test-enforced property

**This is the only genuinely uncovered idea in the brief, and it is not the automation part.**

The brief classifies operations "informally" into safe-to-run-headlessly and requires-review. Informal is wrong for this app. The review gate is the most load-bearing invariant we have, and it is currently written as prose in at least three places and enforced in none:

- **ADR-0042 D2** — `adjustRecipe` stays an unwired placeholder.
- **ADR-0047 D5** — extraction is licensed only because it terminates in a human review gate; it may not invent.
- **ADR-0048** — the regeneration path must upsert by identity and preserve hand-authored rows.

Same invariant, three statements, zero enforcement. This is exactly the argument **ADR-0043 D2** made and won: a convention that is not a failing test goes stale — its own inventory drifted 19/14 → 18/15 sites in 48 hours with nothing deliberately restructured.

**Decision:** operations that write canonical recipe data declare whether they may commit without a human, and an undeclared writer fails a test. A marker plus a scan, not a framework — the ADR-0043 shape.

**Justification is fidelity, not Siri.** An App Intent that could commit a model-derived change headlessly would breach the boundary silently. Declaring makes the breach impossible to add by accident.

## D2 — Structured results on grocery, as an issue not a track

`AddToGroceryListResult { inserted, merged, skipped, warnings }` is a real improvement — "Added 18 items, merged 7, skipped 2 unrecognized" is better in-app feedback today, independent of any automation surface. **ADR-0035** just left us in that code. This is a return type, not architecture. File as an issue.

## D3 — Keyboard shortcuts are parked behind ADR-0046

Genuinely absent from the decision log and genuinely useful on iPadOS and macOS. But binding shortcuts before **ADR-0046** reshapes the shell means doing the work twice. Revisit immediately after it lands, and bind to actions rather than to view state.

## D4 — The brief becomes a lens on ADR-0046, not a parallel track

ADR-0046 rewrites the top-level container, touches every surface, and has no test coverage. Opening a second cross-cutting extraction concurrently is the real risk here — not speculative automation.

Instead: while collapsing four taxonomy encodings into one `TabView`, ask of each surface *does this capability live in a view*. Most of the brief's benefit rides free on work already scheduled.

## Note on the brief's own decision standard

It rules out changes justified by hypothetical Siri or Stream Deck workflows, then frames itself around App Intents. The justification that survives its own standard is **testability** — extractable actions are testable actions, and enforcement tests are now a house idiom. Recorded here so the framing doesn't recur.

## Not doing

Per the brief's own list, and endorsed: no generic command bus, no plugin architecture, no network RPC server, no serialized command format, no dynamic discovery, no undo middleware, no Stream Deck plugin, no iPad control console. Also, per D1 above: no `AppDestination` enum.

## Open

- **OQ1** — Where does the declaration live: on the repository write functions, on the feature-model call sites, or on a thin action type introduced only where a second caller exists? Prefer the narrowest that a scan can enforce.
- **OQ2** — Does ADR-0003's private per-person libraries mean a future Shortcut needs an explicit library parameter? Not blocking, but the brief never raises it.