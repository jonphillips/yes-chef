# Standing guards

Closed decisions that stay closed. **Nothing here is work.** The architect reads this before curating
`NEXT_UP.md` so a dispatch never re-queues a closed item; **the executor reads it when its dispatch touches
text→recipe extraction, hand-off returns, the Shortcuts transport, variations/edit proposals, or chat
presentation** — the ⚠️ items are review blocks. Moved from `CURRENT_HANDOFF.md` on 2026-09-29
(jon-platform ADR-0005).

Closed decisions that stay closed, here only so a dispatch does not re-queue them. **Nothing in this
section is work.**

- **⚠️ The ADR-0042 return contract is v3** (`AIHandoffReturnContract.version`) — re-copy the project
  instructions from AI Settings or every verb fails the marker gate. (Operational: it bites on any hand-off
  dogfooding session.)
- **⚠️ [ADR-0051](decisions/ADR-0051-text-to-recipe-extraction-strategy.md) — text→recipe has ONE strategy; do
  not fork a new parser.** Any new "turn this text/markup into a recipe" path (paste, photo→OCR, another
  hand-off return, …) MUST route LLM extraction through **`RecipeExtractionClient`**, reuse the existing
  deterministic extractors for structured sources (schema.org → `RecipeJSONLDExtractor`), and terminate in
  **`RecipeEditorDraft`**. **A fifth bespoke parser, a second "text→recipe" model call, a new terminal draft
  type, or a third save path is a review block** (D7, as restated by Amd1-D3). The four existing front-ends stay
  plural *by design* (web/schema.org, menu-note heading heuristic, workbench synthesis, JSON-LD return) —
  consolidate the sink and the engine, not the parsers. **The D5 lift is DONE** — `RecipeExtractionClient` now
  lives in a source-neutral home (out of `WebRecipeCapture`), lifted at paste-text, the second real consumer
  (ADR-0053 S1, PR #290); `structuredPageText` → `text`.
  - **⚠️ [Amd 1](decisions/ADR-0051-text-to-recipe-extraction-strategy.md#amendment-1--d1-was-wrong-about-capture-there-are-two-save-paths-and-the-review-surface-is-source-specific-2026-08-07)
    corrected D1 — do not read the old wording as "capture uses the sink."** It does not: `RecipeCaptureView`
    reviews on **`ParsedRecipePage`** and commits through a **second** canonical save path
    (`importCapturedRecipe` → `importBundle`), which Paprika import shares. The enforceable rule is **one sink
    type; ONE SAVE PATH PER IDENTITY CLASS** — a source with a stable external identity (URL, Paprika record)
    commits through `importBundle` and gets `RecipeImportRef` dedupe/warnings/rollback; a source authored in the
    app (paste, typed, menu-note, workbench) commits through `save(draft:)`. **Review surfaces may be
    source-specific but must edit the sink**; capture is a *named grandfathered exception*, **not a precedent**
    to cite. **Converging the two save paths is not queued work** — it needs a source that is both authored and
    externally identified, which does not exist yet.
- **⚠️ [ADR-0053 Amd 2](decisions/ADR-0053-create-recipe-destination.md#amendment-2--a-headless-transport-shortcuts--app-intent-into-create-recipe-2026-08-10)
  — the Shortcuts return path SHIPPED (PR #307, DONE-LOG); its ONE correct wiring is now load-bearing, do not re-fork
  it.** The headless `CaptureRecipeFromText` App Intent lands clipboard text in Create Recipe via a
  `CreateRecipeCoordinator` **sibling** of `ImportHandoffResult` — **never** the routed handoff importer
  (`HandoffReviewCoordinator`): clipboard text has no `handoffID` and no subject, so it is Create Recipe /
  `save(draft:)`, categorically (Amd2-D2). It reuses `CreateRecipeExtraction.extract` — **no new parser, no second
  "text→recipe" model call** (this *is* the ADR-0051 guard above) — with **no general `yeschef://` URL scheme**
  (it foregrounds via an `openAppWhenRun` opener; Amd2-D3). The **only** carve-out is ADR-0058 D2's single-purpose
  `find-referral` door for Cockpit: one host, one parameter, calling `stage(referral:)`, never a router. It seeds **non-destructively** — a non-empty
  session offers the incoming text as a new source and never clobbers unsaved work (Amd2-D4). The transport stays
  producer-agnostic and menu-unaware, preserving exact text (Amd2-D1/D5); durable staging = a new synced table = a
  non-goal (D4).
- **ADR-0021 (variations) is COMPLETE — V1–V3, Amendment 4 (V4a/V4b/V4c + Delete), and anchor-repair
  Dispatch 0/1/2 all shipped (DONE-LOG).** ADR-0023 (recipe edit proposals) has nothing queued: its
  *iterative refine loop* is **WITHDRAWN** (ADR-0042 D7 — it happens in the live external thread; **do not
  rebuild it**); per D2 the in-app adjust verb is the **only** path that writes a structured delta.
  - **⚠️ [ADR-0042 Amd 4](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-4--the-recipe-body-hand-off-finalizes-two-ways-revise-or-riff-into-a-new-recipe-2026-08-15) — the recipe-body hand-off is now DUAL-SINK; do not assume it is prose/delta-only.** The `adjustRecipe`
    hand-off finalizes two ways, chosen in the external conversation and recovered by **return SHAPE**
    (`RecipeAdjustmentFinalize.classify`, reusing S3's `fromJSONLD`): a **revision brief** (prose) → the
    `.recipeAdjustmentBrief` review (delta against live rows, D2 intact); a **new recipe** (schema.org JSON-LD)
    → **Create Recipe** as a standalone draft via `CreateRecipeCoordinator.stage` (the same door as
    capture/workbenchDraft — this *is* the ADR-0051 sink guard, **no new parser**). The "only path that writes a
    structured **delta**" line still holds — a new recipe is not a delta, it has no identity to reconcile.
    v1 is standalone (no "riffed-from" provenance) and drops learnings on the new-recipe branch. The old
    `.menuPrepPlan` deliverable-default leak on the recipe body is fixed (`AIHandoffToken.selfContainedPrompt`). **Expected,
  not a bug to patch (ADR-0014 Amd1-D4):** adding a header inside a recipe that has variations mints a new
  section, so `derivingVariation` hits `.ingredientSectionAdded` → `variationNeedsReview`. Fixing it needs a
  delta-vocabulary decision and it is **ADR-0021's** — do not extend the delta ops on this momentum. **Note:
  Amd4-D4's two step ops (`stepInsert`/`stepRemove`) were the sanctioned widening and have now shipped (V4c);
  the vocabulary is closed again, so a *section* op still needs its own ADR decision, not this momentum.**
- **ADR-0042 S3 (`workbenchDraft`) is DONE — S3a + S3b built, device-passed 2026-08-07 (PR #289),
  recorded in [`DONE-LOG.md`](DONE-LOG.md).** The return is **extraction, not synthesis** (schema.org JSON-LD
  → the deterministic `RecipeJSONLDExtractor`); **do not build a new recipe-text parser** (Amd2-D2/D5). There
  is no S5. Amd2-OQ1/OQ3/OQ4 are resolved (see the ADR). It is the first path built to ADR-0051.
- **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it.** ADR-0041 closed at S2.6, S3
  withdrawn ([Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).
  If section provenance is ever wanted it designs its own storage against its own consumer
  ([[withdraw-not-defer-orphaned-schema]]).
- **Both candidates Jon named 2026-07-21 are discharged** — variations (ADR-0021 V1–V3, shipped + device-passed;
  Amd 4 is a *later* 2026-08-01 reopening, queued separately in Next Up) and "Menu is under-served by hand-off
  verbs" (ADR-0043's load test). Parked **ADR-0013** meal-planner verbs are separate and unscoped — see Ready
  Efforts.
- **The Recipe Workbench store/curate/compare arc (ADR-0019) is complete**, S1–S4 shipped. Parked follow-ons
  live in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md), not here.
- **The workbench's experiment-outcome verb is NOT scoped** — only its *placement* is ratified (ADR-0042 D8's
  corollary: a conjecture suppresses learnings, a **cooked** experiment is findings, so learnings come back
  on). That amendment gets written when that half is scoped, **deliberately not now.**
- **Chat entry points are unified and closed** ([`efforts/chat-ask-uniformity.md`](efforts/chat-ask-uniformity.md),
  PR #244), and **ADR-0046 S2 (PR #298) closed the presentation half too** — every wide-width surface (Recipe,
  Calendar, Workbench Detail, Workbench Compare) is now the **`.inspector`** presentation; compact stays a modal
  sheet. Uniformity is **cross-surface, not cross-device**: modal sheets keep the iOS nav bar, embedded/inspector
  presentations keep the in-panel header row. **That divergence is intended — do not "unify" it.** The old
  `ChatWorkspaceSplit` detent/divider and the `.column`/`DetentIdentity` contract are **deleted; do not resurrect
  them.**
