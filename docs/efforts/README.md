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
