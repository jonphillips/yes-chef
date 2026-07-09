# Effort: NYT "Reader Feedback" — comment ingestion + LLM curation

**Type:** New feature (post-M4, parsing-quality track — sibling to Milk Street parser hardening)
**Owner:** Codex (implement, per slice) · Jon (architect/review)
**Status:** ⚠️ **STALE — partially built and since redirected. Do not dispatch from this doc.** Governed by
[ADR-0025](../decisions/ADR-0025-reader-comment-ingestion.md); the **authoritative build is the ADR's
[Amendment 2026-07-09](../decisions/ADR-0025-reader-comment-ingestion.md#amendment--2026-07-09-dogfood-revision-of-d3d5-post-129)**,
and the live dispatch is `docs/CURRENT_HANDOFF.md` § Next Up. The scaffolding (Load-Comments bridge,
`readerFeedback` enum, extractor, review-sheet reuse, Reader Feedback display, per-tip note storage) is
**already merged** ([#129](https://github.com/jonphillips/yes-chef/pull/129)). Known-stale details below:
Slice 4 (build a Claude client + key storage) is **done** — reuse `LLMClientKit` + Keychain `apiKeyStore`;
Slice 5's `AppStorage` prompt is a **DB-backed `AIPromptPreferenceKind.readerFeedback`** (ADR-0018); Slice 1
(review-sheet dismiss hardening) is **shared with ADR-0024**. **And note:** the "curation, not synthesis"
principle immediately below is **refined by Amendment A1** — the model now *may* consensus-distill *within*
a single atomic point (never *across* points). Read the ADR + handoff, not this doc, for the current shape.

## Motivation

NYT Cooking already parses cleanly via JSON-LD — no parsing gap to fix. The opportunity is
enrichment: NYT recipes carry deep reader comment threads, sortable to "Most Helpful," full of
genuinely useful technique/result tips buried in noise ("I didn't have crème fraîche so I used
whipped cream," location complaints, etc.). Jon always captures NYT authenticated, which is
exactly the condition needed to load and scrape the full ranked thread.

Goal: surface a handful of genuine, specific reader tips as a new **Reader Feedback** note
section on the recipe, with an LLM doing the noise-filtering — reviewed and approved by Jon
before anything is saved, same as every other capture path in this app.

## Design principle: curation, not synthesis

The central risk with an LLM "summarizing comments" is **flattening distinct, specific tips
into a mushy consensus** — e.g. collapsing "I used cardamom instead and it was great" and "I
swapped in cinnamon, worked well" into "some readers suggest warm spices," which destroys
exactly the information that made either tip useful (a specific person did a specific thing and
it worked). This effort explicitly designs against that failure mode:

- The LLM's job is to **select and lightly trim** individual comments, not paraphrase or merge
  them into new prose.
- Output is a **structured list of snippets**, one per selected comment — never a single
  free-text summary paragraph. The output *shape* enforces this, not just prompt wording (a
  model can ignore an instruction; it can't easily ignore "return a JSON array of `{text}`
  items, one per accepted tip").
- Each selected snippet becomes its **own** draft `RecipeNote` row, reviewable/editable
  individually — so Jon can accept three tips and reject a fourth without editing a blob of
  merged text, and the recipe detail view shows several distinct quoted tips rather than one
  vague paragraph.
- The prompt template (user-editable, see below) explicitly instructs: *preserve specific,
  distinct quotes; do not merge different readers' distinct suggestions into a single
  generalized statement.*

## Constraints carried over from `docs/open-questions.md`

- **Only the in-app authenticated `WebPage` browser can do this.** The share extension is
  passive/one-shot (`SharePreprocessor.js` runs once in host Safari, no WebKit in the
  extension) and cannot drive an interactive sort+load. This is exclusively an in-app-browser
  feature.
- **PII/ToS:** comments are third-party content. Commenter display name/avatar are **stripped
  at DOM-extraction time** — never built into the in-memory struct, never sent to the LLM,
  never stored. Only comment text + helpful-count survive.
- **Review-sheet fragility must be hardened first.** Neither `RecipeCaptureView` nor
  `ShareViewController` sets `interactiveDismissDisabled`/`isModalInPresentation` today,
  flagged in `docs/open-questions.md` as a blocker to growing the review surface — do this as
  Slice 1, standalone.

## Build order

### Slice 1 — Review-sheet dismiss-fragility hardening
Add `interactiveDismissDisabled(true)`/`isModalInPresentation` while there are unsaved edits,
plus an explicit Cancel-with-confirm, to `RecipeCaptureView` and `ShareViewController`.
Sync-agnostic, no dependency on anything below; can land any time.

### Slice 2 — Harvest a real "Most Helpful, fully loaded" NYT comment DOM fixture
Same grounding step the Milk Street effort used a real capture for
(`docs/efforts/parser-hardening-truncated-structured-data.md`). Use the Claude-in-Chrome MCP
against an authenticated NYT Cooking recipe: sort to Most Helpful, click Load More a few times,
save a sanitized fixture HTML. Required before Slice 3's selectors can be designed — the
selectors, sort-control markup, and Load-More button are unknown until a real page is in hand.

### Slice 3 — NYT comment capture playbook (in-app `WebPage` browser)
- A named, host-keyed "Load Comments" action in `BrowserWorkspaceView`
  (`YesChefApp/BrowserViews.swift`), separate from the existing "Capture" recipe action.
  Injects JS to click the Most Helpful sort control, then Load More, bounded to a fixed cap
  (start ~20-30 comments / 3-5 Load-More clicks; tune once Slice 2's fixture shows real
  volume).
- This is the first *interactive* per-site capture playbook — Milk Street's DOM fallback
  (playbook #1) is parser-only, no JS injection. Keep it the same small/named/fixture-tested
  shape `docs/open-questions.md` calls for ("a registry of declarative, named, fixture-tested
  playbooks that degrade gracefully," not imperative per-site hacks), so a third site's
  playbook slots in without a rewrite.
- A new pure, host-keyed comment extractor (same shape as `RecipeEditorialProseExtractor` —
  SwiftSoup over the loaded `Document`, fixture-tested, no WebKit dependency in the extractor
  itself) producing `[RawComment { text, helpfulCount }]`. Strip commenter name/avatar here —
  the struct never carries identifying info downstream.
- Separate pipeline from `RecipeJSONLDExtractor`/`RecipeParseBuilder`: comments are not part of
  `schema.org/Recipe` and don't touch the existing parse contract.

### Slice 4 — Claude API client + key storage
First LLM integration in the app. Per `docs/FUTURE_INTELLIGENCE_AND_PLANNING.md` §7.4, the app
has no server (ADR-0002), so this is a direct client-side call with a personal API key:
- Minimal Claude API client (plain HTTP call; check whether a package dependency is already
  vendored before adding one).
- Personal API key stored in Keychain, entered via a new field in the existing `SettingsView`
  (`YesChefApp/RecipeLibraryView.swift:593`).
- Build the client generically — this is reusable infrastructure for other §7.2 "good AI uses"
  (make-ahead extraction, substitutions), not comment-triage-specific.

### Slice 5 — Reader Feedback prompt setting + LLM curation wired into review
- Global, user-editable prompt template in `SettingsView`, `AppStorage`-backed like the
  existing pantry-list field (`GroceryPantryStorage`, `YesChefApp/YesChefApp.swift:8`). Ship a
  sensible default reflecting Jon's examples (filter substitution/location-complaint noise;
  keep genuine technique/result feedback; preserve specific distinct quotes, don't merge them).
- LLM call happens inside the **review-before-commit** flow (`RecipeCaptureView`), never
  silently — matches §9's AI-proposes/user-approves model and the accept/edit/delete pattern
  already built for editorial-prose notes (`docs/efforts/share-review-notes-and-image.md`).
  Input: anonymized `RawComment` list + prompt template. Output: structured list of selected
  snippets (see design principle above).
- New `RecipeNoteType.readerFeedback` case (`YesChefPackage/Sources/YesChefCore/Models.swift:744-758`)
  — additive enum case, no table/schema change, same sync-safe pattern as the existing 13
  cases (`[[sqlitedata-blob-cloudkit-asset]]`). Each selected snippet becomes its own draft
  `RecipeNote` row with this type.
- Detail view: `RecipeDetailView.swift:256` renders `note.noteType.rawValue.capitalized` as
  the section label; confirm/adjust so `readerFeedback` displays as "Reader Feedback" (raw
  `.capitalized` doesn't split camelCase — likely needs an explicit display-string map).

### Slice 6 — Jon device-tests end to end
Real NYT recipe with real comments: Load Comments → review sheet shows proposed Reader
Feedback notes as distinct quotes → edit/accept/reject individually → recipe detail shows the
Reader Feedback section with multiple distinct tips intact (not one blended paragraph).

## Scope decisions

- **In scope:** NYT-shaped interactive comment scrape; anonymization at extraction; LLM
  curation (select + trim, not summarize) via a generic client-side Claude call; global
  editable prompt; new `readerFeedback` note type; review-before-commit integration.
- **Out of scope:** per-source prompt overrides (documented future extension — only NYT has a
  comments feature today, revisit once the global prompt's real-world performance is known);
  a general "any site's comments" engine (same site-specific-DOM brittleness class as Milk
  Street/editorial-prose — keep it named and per-shape); on-device LLM path (comment triage is
  judgment-heavy per §7.4's test, not structural extraction, so cloud Claude is the right tool
  here, not Foundation Models).
- **Sync-safety:** new note type is an additive enum case; writes go through the existing
  `RecipeNote` table at import/review time. No schema change, no identity impact, nothing new
  for the `SyncEngine` path.

## Open questions for the implementer to confirm

- Exact NYT selectors for the sort control / Load More button / comment nodes — unknowable
  until Slice 2's real fixture is in hand.
- Final comment-count cap and how aggressively to bound Load-More clicks (runaway scraping vs.
  missing good tips) — start conservative, tune from real volume.
- Whether the Claude client belongs in `YesChefCore` (host-testable, no network in tests) or
  app-layer only, given it's the first network-calling, key-bearing component in the codebase.

---
*Derived from `docs/open-questions.md` ("Comment ingestion — top-ranked tips as recipe
enrichment", "In-app capture — per-site behavior playbooks & review-UX sturdiness") and
`docs/FUTURE_INTELLIGENCE_AND_PLANNING.md` §7.2/§7.4/§9. Companion to
`docs/efforts/parser-hardening-truncated-structured-data.md` (Milk Street — playbook #1,
parser-only) and `docs/efforts/editorial-prose.md` (the DOM-scrape-behind-schema-first
precedent this reuses).*
