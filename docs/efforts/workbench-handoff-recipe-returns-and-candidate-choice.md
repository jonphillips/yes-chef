# Effort — Workbench hand-offs: recipe returns become the working recipe, and the cook picks the candidates

Status: Ready
Summary: A recipe that comes back on any workbench hand-off stages as the working recipe (replacing an existing one only on confirm), Compare stops asking for a "prep plan", and the cook chooses which candidates a hand-off carries instead of a hidden five-candidate cap.

Jon reported on 2026-11-08 that a recipe staged from a workbench discussion landed in the workbench log as a JSON
Observation, and questioned the hand-off candidate cap. He decided: a returned recipe **replaces** an existing working
recipe **behind a confirm**, and **he chooses** which candidates go on a workbench hand-off.

Decisions: [ADR-0042 Amendment 6](../decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-6--every-workbench-hand-off-can-finalize-as-a-recipe-and-the-cook-picks-what-it-carries-2026-11-08).
Related: [ADR-0042 Amd 4](../decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-4--the-recipe-body-hand-off-finalizes-two-ways-revise-or-riff-into-a-new-recipe-2026-08-15)
(the same route-by-shape on the recipe body), [ADR-0019 D2/D3](../decisions/ADR-0019-recipe-design-studies.md)
(the original soft cap), [ADR-0060](../decisions/ADR-0060-chat-access-over-mcp.md) (`stage_handoff_return`),
[standing guards](../standing-guards.md) (no new recipe-text parser; Amd2-D2/D5).

## Diagnosis (architect, 2026-11-08)

- **The return was routed by the verb you picked, not by what came back.** A `.workbenchCompare` return is treated as
  plain text, never parsed, and saved as a `.observation` log entry (`AIHandoffIntentImport.workbenchReview`, the
  `.workbenchCompare` case → `HandoffReviewCoordinator.commitWorkbenchObservation`). Only `.workbenchDraft` parses
  JSON-LD. A `.workbenchExperiments` return that carries a recipe fails outright with `unparsedExperimentBlocks`.
- **The model was told to send recipes back.** The chat-access server instructions say to finalize through
  `stage_handoff_return` "including a riff into a new recipe" and carry the Recipe JSON-LD contract
  (`ChatAccessServerInstructions.swift`). On a Compare conversation that settled on a recipe, the model did exactly that.
- **Compare's finalize clause is wrong.** `HandoffAppOperations` builds the Compare prompt with
  `deliverableFormat = .menuPrepPlan`, so `.discuss` mode ends with *"When the user asks you to finalize, return the
  paste-ready prep plan."* This is the same leak Amd4-D3 fixed on the recipe body.
- **The cap is fixed at five for every model and hidden from you.** `WorkbenchChatContext.softCandidateCap = 5` applies at
  every tier, including hand-offs, which get a 160k-character budget. For external models the cap, not the budget,
  decides what's dropped. The omission note goes into the prompt, so only the model sees it. The chat header always
  reports the on-device budget (`seededContextDescription` hard-codes `onDeviceSerializedCharacterBudget`).

## S1 — Route a workbench return by shape: a recipe becomes the working-recipe review

**Build.**
- In `AIHandoffIntentImport.workbenchReview`, the `.workbenchCompare` and `.workbenchExperiments` cases first check
  whether the deliverable holds a Recipe JSON-LD object. Use the existing detection: `splittingJSONLDAndRationale` +
  `WorkbenchDraftRecipe.fromJSONLD`, as `RecipeAdjustmentFinalize.classify` does. Lift one shared helper rather than
  copying it a third time. If a recipe is found, stage `.workbenchDraft(AIHandoffWorkbenchDraftReview(...))` with the
  return's learnings: the existing "Review working recipe" item plus "Review learnings". Prose around the JSON becomes
  the draft's rationale through the existing splitter, not an Observation. Otherwise behaviour is unchanged.
  **No new parser** (standing guard).
- This is one seam, so paste, the chat-access inbox, and `stage_handoff_return` all get it. Check whether anything
  after staging assumes the review kind matches `handoff.taskType` (import status, `acceptsRepeatReturns`, the
  pending-handoff bookkeeping). Make a Compare handoff that returns a draft complete cleanly.
- Fix the ask, following Amd2-D4: the shape comes from the verb's own ask, not a one-clause `DeliverableFormat`.
  - Give Compare its own `DeliverableFormat` case, with a clause that names differences, not a prep plan.
  - `compareHandoffPrompt()` and `experimentsHandoffPrompt()` each gain the second finalize outcome, as in Amd4-D1. If
    the cook has settled on a recipe, return it as one schema.org `Recipe` JSON-LD object per
    `RecipeJSONLDContract.outputInstructions`, then a separate rationale block, never mixed with the usual deliverable.
    Infer which the cook means, and ask one short question only if it's genuinely ambiguous.
- No change to `ChatAccessServerInstructions` wording ("including a riff into a new recipe" is now true here too).

**Acceptance / tests (Core).**
- Compare return that is JSON-LD only → `.workbenchDraft` review.
- JSON-LD fenced, with rationale before or after → draft with rationale.
- JSON-LD plus a learnings section → draft and learnings.
- Experiments return carrying JSON-LD → draft, not `unparsedExperimentBlocks`.
- Prose compare that contains a stray `{`, or JSON that isn't a Recipe → still a comparison Observation.
- The exported Compare prompt (both modes) no longer contains "prep plan". Assert on the assembled prompt from
  `HandoffAppOperations`, not just the Core ask.

**Not in scope.** Don't migrate the existing JSON Observation in Jon's log. Confirm and write in the PR how he
recovers it: copy its JSON into the Compare paste door, or into Create Recipe. Build nothing for it.

## S2 — Replace an existing working recipe, behind a confirm

**Build.**
- The draft review item applies to Draft returns and S1's rerouted returns alike. If the workbench already has a
  working recipe:
  - The commit title becomes **"Replace Working Recipe…"**.
  - Committing presents a confirmation first.
  - On confirm, one write transaction runs `WorkbenchRepository.removeDraftRecipe` then `createDraftRecipe`.
- **Check at commit time, not just at staging.** A working recipe can appear or disappear while the review is open.
  Never surface `draftRecipeAlreadyExists` to the cook from this path.
- Confirmation copy reuses the existing Remove Working Recipe semantics, which are the honest consequences:
  - Unpromoted draft: "Replaces the draft working recipe, including any edits you made to it. This can't be undone."
  - Promoted recipe: "Detaches it from this workbench and stays in your library."
- Add the confirm as a small optional field on `ChatApplyReviewItem`, or in the review sheet. Pick whichever keeps the
  generic review surface simplest. Explain the choice in the PR.
- **Show the Draft door when a working recipe exists.** Today it's gated on `draftRecipeID == nil`
  (`WorkbenchViews.swift`, Working Recipe footer). With replace-on-confirm the gate is unnecessary. The draft ask
  already carries "Current working recipe:", so a Draft hand-off from an existing recipe is a revision round. Footer
  copy says the result replaces the working recipe after review.

**Acceptance / tests (App model, `YesChefTests`).** Drive the real review-item builder and its commit into an isolated
database:
- No working recipe → created, no confirm.
- Unpromoted draft → confirm → old recipe row deleted, new one linked.
- Promoted recipe → confirm → old recipe still in the library (`.main`) and unlinked, new one linked.
- Cancel → nothing changed.
- Working recipe appears between staging and commit → confirm still shown.

## S3 — The cook picks which candidates a workbench hand-off carries

**Build.**
- `HandoffExportSource.workbench` gains an optional candidate selection: an ordered set of `WorkbenchCandidate.ID`, where
  `nil` means all. `HandoffAppOperations` filters `WorkbenchChatContext` to it before building the Compare,
  Experiments or Draft ask. The App Intent / Shortcuts path passes `nil`.
- **The count cap applies only at the on-device tier.** Frontier chat and hand-offs are bounded by the character
  budget alone, which already trims references first and then whole candidates from the bottom (ADR-0019 D2's
  depth-over-breadth rule still holds).
- Serialization reports which candidates and references were **included and left out**, by ID, so the UI can say so
  without re-deriving it.
- **Picker.**
  - Every workbench "Hand off · Compare / Experiments / Draft" copy action opens a picker before copying. This covers
    Workbench Detail, Workbench Compare, and the Draft footer.
  - The picker lists candidates in workbench order with toggles, all on by default, and shows a live fit line from
    the real serializer at the frontier budget, e.g. "All 7 fit", or "Too much to send: *Title A*, *Title B* would be
    left out".
  - It shows a one-line reference count (included / left out).
  - **Copy Prompt** is disabled with nothing selected. Paste buttons are unchanged.
  - Skip the picker when the workbench has exactly one candidate.
  - Don't persist the selection in v1. It's ephemeral per hand-off; no schema, no UserDefaults.
- **Honest chat header.** `seededContextDescription` takes the active tier and reports that tier's actual omissions,
  so a frontier chat stops showing on-device numbers.

**Acceptance / tests.**
- Core:
  - The selection filters candidates and keeps workbench order.
  - No count cap at frontier tiers: a 7-candidate workbench under budget sends all 7.
  - The on-device tier keeps the cap.
  - Over-budget trimming reports the right left-out IDs.
  - Header text differs by tier when an omission exists.
- App model: the picker's fit line and the disabled state, and the exported prompt contains exactly the chosen
  candidates.

## Verification and completion

No schema, migration, sync, contract-version or new-parser change is authorized: `AIHandoff` is device-local,
`HandoffExportSource` isn't persisted, and the selection is ephemeral.

- Run focused tests, then `scripts/check-drift.sh`, the generic device build, and the `YesChefTests` app target per
  [verification.md](../verification.md). All slices touch `YesChefApp/` model code.
- Closeout: DONE-LOG entry and archive this brief with the final dispatch.
- Owed device gate (Jon, iPad + iPhone):
  - Run a Compare hand-off through chat access that ends in a recipe. It stages "Review working recipe" and creates
    it.
  - Repeat with a working recipe present: the confirm appears and replaces it.
  - The Draft door shows with a working recipe present.
  - The candidate picker sends exactly the chosen candidates, and its fit line is right.
  - No agent screenshot work.

## Dispatch ledger

- [x] Dispatch 1 — S1 + S2 (return routing, Compare ask fix, replace-on-confirm, Draft door), one PR.
- [ ] Dispatch 2 — S3 (candidate picker, tier-scoped cap, honest header), one PR.
