# Efforts index

Design/discussion + build-order docs for Yes Chef features. **The `decisions/` ADRs
record *what we decided*; these efforts hold the *worked design and slice plan*** that
implements a decision (or explores toward one).

**Authoring discipline** (jon-platform `docs/agent-workflow.md` § "Working docs stay
discoverable"):
- **Index at creation.** A new effort adds its one-line entry here in the same change —
  the index is kept fresh by ceremony, not vigilance.
- **Self-describing header.** Each effort carries a `Status:` stamp, a one-line
  `Summary:`, and `Related:`/`Superseded-by:` links. The entry below is a copy of the
  Summary; the Status lets you triage without opening the file.
- **Search before authoring.** Before writing a new effort or an ADR, `grep -ri
  <topic> docs/` and read adjacent efforts — cross-link them.

**Status legend:** Designed (spec'd, not dispatched) · Dispatched (with Codex) ·
In progress · Done (write-up in [`../DONE-LOG.md`](../DONE-LOG.md)) · Superseded.

**Coverage note:** this index is **backfilled on touch** — entries appear as efforts
are opened/edited, not via a retroactive sweep. Docs below are the ones touched since
the index was created (2026-07-08); the rest of `efforts/` gains an entry the next time
it's touched.

## Active / recent

- [adr-0021-v4c-and-variation-delete.md](adr-0021-v4c-and-variation-delete.md) — **Done** (write-up in
  [`../DONE-LOG.md`](../DONE-LOG.md)) · [ADR-0021](../decisions/ADR-0021-recipe-variations.md) Amd4-D4 ·
  Widens the variation delta vocabulary by **exactly two** anchored ops — `stepInsert` / `stepRemove` — so a
  variation can add and drop instruction steps instead of being forced out to a separate recipe, and adds the
  **Delete** affordance Amd2-D4 sanctioned but nobody ever built. Both halves schema-free. Moves and every
  section op stay unrepresentable and still route to split-off; the vocabulary is closed again.
- [variation-anchor-repair.md](variation-anchor-repair.md) — **Designed, Dispatch 0 ships immediately** ·
  Defects in [ADR-0021](../decisions/ADR-0021-recipe-variations.md)'s anchor handling · A variation's
  anchors are taken from **model output** and never normalized to base IDs, so a base text edit orphans the
  variation permanently; `resolved(applying:)` **throws**, so one dead anchor takes out the editor, the
  reader fold and the grocery list; and two silent-failure paths in the adjust surface show nothing at all.
  Four dispatches, no schema.
- [dogfood-ferry-2026-07-25.md](dogfood-ferry-2026-07-25.md) — **Designed** (not dispatched) · Jon's
  2026-07-25 ferry pass · **Three dispatches, three PRs.** D1: one shared full-screen expand control replaces
  four drifted copies + the Menu gains the Recipe's pinned-Ask onboard treatment (view layer only). D2:
  prep-plan/complement hand-offs regroup into per-day and per-plan overflow menus, per-day prep becomes a
  *scoped ask* over woven storage (no `dayOffset` on the step record — ADR-0034 holds), Clear gains a confirm,
  and "Prep Plan" stops leaking onto the recipe surface. D3: workbench Active/Completed + edit-in-place +
  honest delete copy, and menu learnings become hand-authorable through the orphaned `.inApp` provenance.
  One nullable synced column (`workbenches.dateCompleted`); everything else schema-free. The tab-bar shell is
  split out as [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md), gated behind D1.
- [adr-0026-review-collection-sheet.md](adr-0026-review-collection-sheet.md) —
  **Ready to dispatch** (Next Up) · Governed by
  [ADR-0026](../decisions/ADR-0026-review-collection-sheet.md) (Accepted) · Hoist the multi-item
  LLM-review collection into the slide-up sheet (the universal LLM-evaluation surface); remove the inline
  `ChatApplyReviewList` band; adjust verb becomes a launch-only row; S2 = reader-feedback curation adopts
  the same host-agnostic sheet. No schema.
- [dogfood-fixes-batch-5-mechanical-polish.md](dogfood-fixes-batch-5-mechanical-polish.md)
  — **Dispatched** (2026-07-08) · Mechanical dogfood polish in one PR: recipe detail
  toolbar/layout, editor (auto-growing text + editable Make-Ahead/Chef-It-Up + async
  save), tokenized search, capture-review edits.
- [recipe-edit-proposals.md](recipe-edit-proposals.md) — **In progress** (S3 = current
  Next Up) · Governed by [ADR-0023](../decisions/ADR-0023-recipe-edit-proposals.md) ·
  The "Adjust this recipe" verb: LLM writes only to a transient preview, reviewed
  side-by-side, committed to overwrite or a variation.
- [reader-feedback-comment-ingestion.md](reader-feedback-comment-ingestion.md) —
  **Designed** · Governed by [ADR-0025](../decisions/ADR-0025-reader-comment-ingestion.md)
  · Interactive NYT comment harvest → LLM curation into *distinct* Reader Feedback notes
  (select+trim, never merge); Slices 4/5 partly superseded by shipped LLM infra.
- [browser-passwords-autofill-spike.md](browser-passwords-autofill-spike.md) —
  **Spike** (not an ADR) · Investigate why system Passwords autofill fails in the
  `WKWebView` capture browser; *defends*
  [ADR-0009](../decisions/ADR-0009-in-app-authenticated-browser-capture.md)'s
  "never store credentials," does not reverse it.
