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
   Therefore sync is sequenced **after** import is trustworthy — gated on data
   quality, not a date.

## Baseline (built, un-audited)

Treat the four feature areas above as the current baseline. They are *not* re-spec'd
as forward milestones; they are the starting evidence the audit assesses.

## Phase A — Stabilize the foundation  *(next; your "(c)")*

Goal: bring current `main` into conformance with the now-codified house rules before
any new surface lands on it.

- **First:** an architect re-baselining audit of current `main` (a `docs/reviews/`
  doc), checking the built feature areas against jon-platform's
  `persistence-and-sync.md` (observed reads, identity-preserving saves, snapshot =
  interchange format), `swift-style.md` (repository core, feature models, persisted
  enums), and the Yes Chef ADRs. The audit's findings *are* the M1 build order's
  content.
- **Then:** M1 build order — pay down the confirmed debt as ordered slices.

Output: a foundation we trust enough to build import and (eventually) sync on.

## Phase B — Import hardening + landing the real library  *(your "(b)")*

Goal: make Paprika import trustworthy enough to bring Jon's real library in — the
gate that must close before sync.

- Mine Paprika feature-and-format parity systematically (its export formats, the
  `.paprikarecipes` backup, image sources, category/source semantics).
- Harden the import spike into a reviewable flow: import summary (counts, skips,
  warnings, errors), best-available image quality, date backfill, preservation of
  unmapped/raw fields, and a review step before commit.
- Round-trip and fixture tests; no silent data loss.

Output: the real library lands locally, clean enough to live with permanently.

## Phase C — CloudKit sync enablement  *(your "(a)" — deliberately last of the three)*

Goal: turn on sync only once import is trustworthy, to avoid polluting the iCloud
private zone with throwaway re-imports.

- **Verify the current SQLiteData API/version at milestone start** (house rule — the
  library moves fast).
- Audit the solo-built schema against the CloudKit laws (UUID PKs, no unique indexes
  beyond PK, dedup-on-read) *before* the first zone write.
- Enable sync; test with seeded duplicates and offline-edit races.

Output: multi-device sync with no server, no auth — the central bet, paid once the
data is worth keeping.

## Phase D+ — Parity completion, then differentiation

Sequenced after the foundation is stable, the real data is in, and sync works.
Paprika-parity-first, then the features that make Yes Chef next-gen:

- Scaling and cooking-mode hardening (old roadmap M3).
- Menu / meal-plan / grocery polish; ratify the Menus model (likely its own ADR).
- Send-a-recipe (Phase-1 transfer), then Family Cookbook (Phase-2, CloudKit
  sharing).
- Grounded AI planning (`FUTURE_INTELLIGENCE_AND_PLANNING.md`) — make-ahead/thaw/
  prep timelines, equipment-conflict flags, source-faithful cleanup.

## Status

Phases A–D are provisional and strategic; the audit (Phase A, first task) may
reshuffle the detail. Build orders are authored one milestone ahead in
[milestones/](milestones/), never as a giant dump.
