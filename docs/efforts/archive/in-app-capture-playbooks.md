# In-app capture: per-site playbooks and review-UX sturdiness — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** Two linked threads anchored to the in-app `WebPage` browser (ADR-0009). Post-sync.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## In-app capture — per-site behavior playbooks & review-UX sturdiness

Two linked threads Jon raised 2026-06-30, both anchored to the **in-app `WebPage` browser**
(the only ship-able interactive surface — see the comment-ingestion question above and
ADR-0009). Post-sync; **do not front-load over the iCloud gate** (see
`[[post-browser-sync-vs-features-tension]]`).

- **Per-site "capture playbooks" as a superpower (Jon's framing).** Turbocharge the in-app
  browser with small, named, per-host behaviors: Milk Street → DOM print-template fallback
  (`docs/efforts/archive/parser-hardening-truncated-structured-data.md`); NYT → sort comments to Most
  Helpful + Load-More + scrape; ATK → editorial-prose scrape (`docs/efforts/archive/editorial-prose.md`).
  These are the **same site-specific-DOM brittleness class** as the editorial-prose and
  comment-ingestion ideas — hashed CSS-module classes the publisher can rotate, lazy-load
  timing, layout shift. So the design constraint is: keep them a **registry of declarative,
  named, fixture-tested playbooks that degrade gracefully to schema-first**, not a pile of
  imperative per-site hacks. The Milk Street DOM fallback is effectively playbook #1 — build
  the seam so #2 (NYT) slots in without a rewrite. JS injection runs as the authenticated user;
  note the ToS/automation questions alongside the existing comment PII/storage ones.
- **Is the review surface sturdy/large enough? (verified concern, 2026-06-30).** Both
  review-before-commit surfaces are **dismiss-fragile today**: `interactiveDismissDisabled`
  appears **nowhere** in the app or extension, and `ShareViewController` never sets
  `isModalInPresentation`. So an in-progress capture/review can be lost to a swipe-down or an
  errant backdrop tap — and the share payload is one-shot (recovering means re-navigating in
  Safari). As scrape+review grows (comments, per-site playbooks, multi-section edits, image
  pick), a swipe-away half-sheet is the wrong container.
  - *Cheap near-term hardening (sync-agnostic, could land anytime):* guard the review sheet
    with `interactiveDismissDisabled(true)` / `isModalInPresentation` while there are unsaved
    edits, plus an explicit Cancel-with-confirm.
  - *Richer future:* graduate the in-app review from `.sheet` to a full-screen
    `NavigationStack` presentation (precedent exists — `RecipeLibraryView.swift:40`
    `.fullScreenCover` for `presentedRecipeID`).
  - *Division of labor:* the share extension is inherently space/lifetime/memory-constrained
    (system card, one-shot payload, no long-running work per
    `[[extension-sync-construct-not-run]]`), so keep it **lean — capture + quick confirm +
    hand off** — and put the **rich interactive review and the per-site playbooks in the
    in-app path**. Don't fight the platform by building the complex review inside the extension.
