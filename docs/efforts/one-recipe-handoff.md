# Effort — One recipe hand-off

Status: Ready — one dispatch, ADR-0061 S1 (Core) and S2 (App) in one PR. Schema-free: the local `aiHandoffs`
table gains a task-type case.
Summary: One recipe **Hand off** whose prompt offers every deliverable and whose return is filed by label; each
Playbook section's `•••` becomes **Edit / Write**, and **Clear** moves to the bottom of its editor.

Related: [ADR-0061](../decisions/ADR-0061-one-recipe-handoff.md) (the decision and the slice spec) ·
[ADR-0042](../decisions/ADR-0042-workbench-handoff-and-the-return-block.md) Amd 1 ·
[ADR-0041](../decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md) Amd 1 and Amd 2 ·
[chat-access-mcp.md](chat-access-mcp.md) (its S3b builds on this dispatch)

## Spec

[ADR-0061 § Slices](../decisions/ADR-0061-one-recipe-handoff.md#slices) is the spec, read with D1–D7. S1 and S2
ship in one PR: S2 has nothing to call until S1 lands, and S1 has nothing using it until S2 does. Out of scope:
D8 (the onboard **Discuss ▾** starters), OQ1 (a focused per-section shortcut), and the menu and meal-plan
hand-offs.

Three requirements come from specifying chat-access S3b
([ADR-0060 Amd 1](../decisions/ADR-0060-chat-access-over-mcp.md#amd-1--notes-at-acceptance-2026-11-03)), which
builds on this dispatch:

1. **Core routes a new recipe, for every door and both task types.** ADR-0061 D3 moves JSON-LD detection out of
   `HandoffInAppTransport.stageReview` and into Core. That covers `.recipe`'s `YC-NEW-RECIPE:` label and legacy
   `.adjustRecipe` tokens. Today an Adjust riff that goes through `AIHandoffIntentImport.stageReview` (the
   **Import Handoff Result** intent's path) stages as a prose brief. Core's staging returns a new-recipe outcome,
   which the caller sends to Create Recipe, and marks the hand-off imported.
2. **One app entry presents a staged recipe return.** The paste transport, the **Import Handoff Result** intent,
   and later S3b's inbox all pass a staged result to one function. It shows the review items, then the brief's
   side-by-side, or sends a new recipe to Create Recipe. No door keeps its own copy of the routing.
3. **D4's repeat-return rule lives on the task type in Core,** for example `AIHandoffTaskType.acceptsRepeatReturns`,
   true only for `.recipe`. It isn't a branch inside the stager. S3b's inbox reads the same property to decide
   whether a later return supersedes an earlier one.

## Tests

ADR-0061 S1's list, plus:
- A legacy `.adjustRecipe` token whose payload is JSON-LD routes to a new recipe through Core's `stageReview`.
- `acceptsRepeatReturns` is true for `.recipe` and false for every other case.
- In `YesChefTests`: the **Import Handoff Result** intent's path sends a JSON-LD riff to Create Recipe. A
  multi-item return presents its section items first, then the brief.

## Verification

`scripts/check-drift.sh`, the generic device build, and `YesChefTests` on a simulator. This dispatch changes app
model code: the review coordinator and the transport. Guardrail #9 has the rule, and
[`verification.md`](../verification.md) has the exact commands.

## Done when

S1 and S2 are built as ADR-0061 § Slices describes, the three requirements above are met, the tests pass, and
closeout (ADR-0005 D16) runs with ADR-0061's device pass as the gate.
