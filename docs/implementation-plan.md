# Implementation Plan

The strategic arc for Yes Chef. Concrete, Codex-ready build orders live in
[milestones/](milestones/); the phases below are the arc those slices implement.

## Why this doc re-baselines the roadmap

`REQUIREMENTS_MVP_ROADMAP.md §11` staged the build as M0 setup → M1 library → M2
import → M3 scaling/cooking → M4 grocery → M5 meal planning → M6 send → M7 family.
The repository no longer matches that numbering. Working solo (PRs #1–#5, all
self-merged, with **no `milestones/` build orders ever in place**), the executor has
already built well past and out of order from that plan:

- **Recipe library** — list, detail, editor, cooking-mode shell, taxonomy
  (categories, source/author facets, library placement), write-once original
  snapshot. (Old M1.)
- **Paprika import spike** — HTML export + `.paprikarecipes` backup parsing, image
  import, date backfill. Partial; not a hardened, trustworthy flow. (Old M2.)
- **Grocery lists** — source-provenance items, conservative consolidation, pantry
  staple assumptions. (Old M4.)
- **Meal calendar + Menus + grocery-from-plan** — month/week/day calendar, a Menus
  subsystem (dishes, calendar placements, drag/drop), grocery generation from a
  date range or menu. (Old M5, plus Menus, which was not in the roadmap at all.)

So the old numbering describes history, not forward work, and is **superseded by the
numbering below.** The roadmap's *requirements* content stays authoritative; only
its §11 milestone sequence is retired.

Two facts shape everything forward:

1. **The foundation is un-audited.** The 2026-06-16 Pass-1 review (`docs/reviews/`)
   found P0/P1 architecture problems (hand-pulled reads → `CancellationError`;
   destructive blob saves; logic-in-views; stringly-typed columns; lossy snapshot).
   Those fixes were codified into jon-platform's house docs — but the grocery, menu,
   and meal-planning code was stacked on top *without confirmation the code itself
   was brought into conformance.* The first forward act is to find out.

2. **Sync is a one-way gate.** Local re-imports while iterating are free and
   throwaway. The first time CloudKit sync is enabled, every bad or duplicate import
   propagates to all devices and is painful to purge from the private zone.
   Therefore sync is sequenced **after** import *and capture* are trustworthy — gated
   on data quality, not a date. (As of 2026-06-29 "all capture" explicitly includes
   authenticated in-app browser capture; see Phase D.)

## Baseline (built, un-audited)

Treat the four feature areas above as the current baseline. They are *not* re-spec'd
as forward milestones; they are the starting evidence the audit assesses.

## Phase A — Stabilize the foundation  *(next; your "(c)")*

Goal: bring current `main` into conformance with the now-codified house rules before
any new surface lands on it.

**Resolved (2026-06-27):** the
[re-baselining audit](reviews/AUDIT-2026-06-27-main-conformance.md) found **no
architecture debt** to pay down — every Pass-1 P0/P1 finding is resolved in code, the
solo-built grocery/menu/calendar subsystems conform, and `swift test` is green. Phase A
therefore **collapses from a milestone into a single tests-only slice** (the audit's one
"now" residual: grocery dangling-source tolerance), folded in as **Slice 0 of M1**. The
remaining audit findings (dedup-on-read; `menuItems.recipeID` second FK) are parked on
the sync and Family Cookbook milestones, where they belong.

Output: a foundation already trusted enough to build import on — confirmed, not assumed.

## Phase B — Import hardening + landing the real library  *(your "(b)")*

Goal: make Paprika import trustworthy enough to bring Jon's real library in — the
gate that must close before sync. **Build order:**
[milestones/M1-paprika-import-hardening.md](milestones/M1-paprika-import-hardening.md)
(which opens with the Phase-A fold-in as Slice 0).

- Mine Paprika feature-and-format parity systematically (its export formats, the
  `.paprikarecipes` backup, image sources, category/source semantics).
- Harden the import spike into a reviewable flow: import summary (counts, skips,
  warnings, errors), best-available image quality, date backfill, preservation of
  unmapped/raw fields, and a review step before commit.
- Round-trip and fixture tests; no silent data loss.

Output: the real library lands locally, clean enough to live with permanently.

## Phase C — Web recipe capture  *(new — the daily-driver unlock, before the sync gate)*

Goal: let Jon capture *new* recipes from web pages — paste-a-URL and a share
extension — so the app becomes his daily driver instead of Paprika. M1 lands the
*existing* library; capture is what makes the *next* recipe land here. Sequenced
**before sync** because a share extension is another write path: an un-idempotent
capture pollutes the iCloud zone exactly like a bad bulk import. **Build order:**
[milestones/M2-web-recipe-capture.md](milestones/M2-web-recipe-capture.md).

- Harvest Galavant's proven, same-stack capture engine (JSON-LD/microdata value-votes,
  headless rendered-DOM fetch) and re-target it to `schema.org/Recipe` — harvest now,
  converge on a shared package later (ADR-0007).
- Reuse M1's composed import identity (URL-present strong path) and review-before-commit,
  so capture is idempotent and reviewable.
- App-group shared store so the extension and app see one library; committed sanitized
  HTML-page fixtures.
- In-app browser capture is its own milestone (**M3 — now Phase D, elevated above sync**),
  proven in Galavant first, then harvested. Photo → LLM recipe capture is a *separate*, later
  fallback for sources with **no** structured data (printed/handwritten); it is **not** the
  answer to paywalled sites, which embed good structured data behind a login (see Phase D).

Output: the app is worth living in before sync turns on — new recipes land here, cleanly
and idempotently.

## Phase D — In-app authenticated browser capture  *(M3 — elevated above sync, 2026-06-29)*

Goal: capture recipes from sites that gate their content behind a login, by browsing to them
in an **in-app `WebView`/`WebPage`** (the iOS 26 SwiftUI WebKit API — the *same* one
`YesChefApp/RenderedDOMFetcher.swift` already uses headlessly; **not** `SFSafariViewController`/
"SafariView", which sandboxes the page and forbids the JS/DOM access capture needs) **holding
Jon's authenticated session**, capturing the rendered DOM directly. The interactive browser is
`RenderedDOMFetcher` shown rather than headless: a visible `WebView` for navigation/login, plus
the same `page.callJavaScript("…outerHTML")` capture — now against the *authenticated* DOM.

**Why this jumped ahead of sync (decision — Jon + architect, 2026-06-29).** Jon's named
must-have sites are **4-of-7 paywalled** (NYT Cooking, Cook's Illustrated, America's Test
Kitchen, Milk Street — issue #29). Those sites embed perfectly good `schema.org` structured
data; it simply sits behind a login wall, so an unauthenticated paste-a-URL GET retrieves a
teaser stub, and the share extension only helps when Safari hands over rendered content (its
URL-only fallback re-hits the wall). The in-app browser is the **robust** path — it owns the
session end-to-end and reaches the structured data that is already there. This is therefore
**not** an OCR/LLM problem; it is an authentication problem. Because a majority of the daily
sites depend on it, the app is not genuinely "worth living in before sync" without it — and the
one-way-gate logic already says *all* trustworthy capture should precede sync, so elevating it
above sync is **consistent with** the gate, not contrary to it. (M1 still lands first — agreed;
this only reorders what follows M1.)

- **Evaluate in Galavant first (Jon), then harvest (ADR-0007).** Code at
  `/Users/jon/code/galavant/galavant`. Two questions decide harvest-vs-rebuild: (1) does it
  already capture the **rendered DOM from a visible/interactive web view** (vs. only the
  headless `WebPage` fetch we already harvested), and (2) does it **persist the login session /
  cookies across launches** (WebKit's data store does by default; confirm Galavant doesn't use
  an ephemeral store)? (2) is the whole value for paywalled sites — log in once, not per capture.
- Capture flows through the **same** review-before-commit + idempotent `importBundle` path as
  M2; the browser is a new *fetch* seam, not a new write path. **Never store credentials** —
  the session lives in the web view's own store.
- Committed sanitized fixtures for the rendered-DOM shape, as in M2 Slice 5.

Output: Jon's real daily sites — paywalled included — capture cleanly into the library,
**before** the sync gate opens.

## Phase E — CloudKit sync enablement  *(deliberately last — after import AND all capture)*

Goal: turn on sync only once import **and all capture paths** are trustworthy, to avoid
polluting the iCloud private zone with throwaway re-imports or duplicate captures.

- **Verify the current SQLiteData API/version at milestone start** (house rule — the
  library moves fast).
- Audit the solo-built schema against the CloudKit laws (UUID PKs, no unique indexes
  beyond PK, dedup-on-read) *before* the first zone write.
- Enable sync; test with seeded duplicates and offline-edit races.

Output: multi-device sync with no server, no auth — the central bet, paid once the
data is worth keeping.

## Phase F+ — Parity completion, then differentiation

Sequenced after the foundation is stable, the real data is in, and sync works.
Paprika-parity-first, then the features that make Yes Chef next-gen:

- Scaling and cooking-mode hardening (old roadmap M3).
- Menu / meal-plan / grocery polish; ratify the Menus model (likely its own ADR).
  Grocery consolidation + pantry thresholds is specced ahead in
  [milestones/grocery-consolidation-and-pantry.md](milestones/grocery-consolidation-and-pantry.md)
  (one canonical key, same-dimension unit merge, static pantry thresholds — deterministic,
  no inventory).
- Send-a-recipe (Phase-1 transfer), then Family Cookbook (Phase-2, CloudKit
  sharing).
- Grounded AI planning (`FUTURE_INTELLIGENCE_AND_PLANNING.md`) — make-ahead/thaw/
  prep timelines, equipment-conflict flags, source-faithful cleanup.

## Status

Phases A–F are provisional and strategic; the audit (Phase A, first task) may
reshuffle the detail. Build orders are authored one milestone ahead in
[milestones/](milestones/), never as a giant dump.
