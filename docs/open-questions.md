# Open Questions

Live ambiguities and recently-resolved decisions. Resolved items stay here briefly
(dated) so the reasoning is durable, then graduate into the relevant doc or ADR.

## Resolved — 2026-06-28

- **Web recipe capture is its own milestone (M2), before sync.** A share extension is
  another write path; it must be idempotent before the iCloud one-way gate. See
  [milestones/M2-web-recipe-capture.md](milestones/M2-web-recipe-capture.md).
- **Harvest Galavant's capture engine, don't reinvent.** Same-stack, proven (JSON-LD/
  microdata votes, headless rendered-DOM). Re-target to schema.org/Recipe in YesChefCore.
- **In-app browser capture → M3.** Perfect it in Galavant first, then harvest.
- **App-group shared store now** (M2 Slice 3), coordinated with the sync CloudKit container.
- **Fallback is OpenGraph/meta + preserve-raw for M2;** photo → LLM recipe capture is the
  intended successor (its own later milestone) and the fallback for sites that resist
  structured extraction.

## Live — web-capture engine convergence

- **Converge YesChef + Galavant onto a shared capture-engine package (ADR-0007).** YesChef
  is already the second consumer; harvest-first only defers the abstraction until two working
  implementations exist. **Trigger: M2 close** (or Galavant's next capture-engine change).
  Tracked so it isn't forgotten — do not let the two engines drift permanently.

## Resolved — 2026-06-27

- **Rebaseline cleanly, don't retro-fit.** The roadmap §11 numbering is retired;
  forward work is renumbered from current reality. See
  [implementation-plan.md](implementation-plan.md).
- **Audit before forward.** The first architect act is a re-baselining review of
  current `main` for conformance to the now-codified house rules, before any new
  build order. It gates the M1 build order.
- **Order of the big three: stabilize → import → sync.** Architecture-debt paydown
  first, then import hardening, then CloudKit sync. Sync is last by design: it is a
  one-way gate, and enabling it before import is trustworthy would propagate
  throwaway re-imports across all devices and the private iCloud zone.
- **Menus are ratified product, not speculation.** Yes Chef is a next-gen Paprika:
  reach recipe-app parity, then differentiate. Paprika is the source for many
  baseline features (user files / formats: https://www.paprikaapp.com/help/ios/).
  The Menus subsystem stays; it likely earns its own ADR for the
  menu / meal-plan / grocery provenance model.
- **jon-platform did not drift.** The Pass-1 alignment items (repository core,
  persisted enums, observed-reads anti-pattern, identity-preserving saves,
  snapshot-as-interchange-format) all landed in jon-platform's `docs/ios/`. The open
  risk is whether Yes Chef's *code* conforms — which the audit settles.

## Foundation / audit

- Did the Pass-1 P0/P1 fixes actually land in the code before grocery/menu/
  meal-planning were built on top, or is that debt still present under the newer
  features? (The audit answers this.)
- Are the grocery, menu, and meal-plan reads observed (`@Fetch`/`@FetchAll`) or
  hand-pulled into `@State`? Are their saves identity-preserving?
- How much feature logic lives in views vs. `@Observable` models in the newer
  subsystems?

## Import / Paprika parity

- What is the concrete Paprika feature-parity gap list, derived from the live app
  rather than memory? (To be built when authoring Phase B.)
- Which Paprika export path is canonical for the real library import — HTML export,
  `.paprikarecipes` backup, or both reconciled? Which preserves the most fidelity
  (dates, categories, image resolution)?
- Does any high-value source need authenticated capture (ATK, Milk Street), and if
  so, when does that enter scope vs. the manual-HTML fallback?

## Comment ingestion — top-ranked tips as recipe enrichment

Feature interest noted 2026-06-30 (Jon), surfaced while sanitizing the ATK capture-DOM
fixture. The want: pull a source's comments, sort by **Most Liked (ATK) / Most Helpful
(NYT)**, and surface the top few for their *valuable advice* (e.g. "they spread too much —
cut the sugar", "came out flat") — not the whole thread.

- **The capture-DOM does not give us this — confirmed from the real artifact.** ATK
  server-renders only the **first ~4 comments** into the page, in default **Newest** order;
  the other ~1488 lazy-load via a JS/API call. So a static page capture yields neither the
  volume nor the *ranking* the feature needs. "Most liked" is a different query than what
  the DOM hands us.
- **Two separable axes — don't conflate them:**
  1. *How to obtain ranked comments.* Either **(a) user-driven in the in-app browser** —
     tap "Most Liked," let it load, then a capture scrapes the rendered comment DOM (manual
     sort + automated extract; brittle against hashed CSS-module classes like
     `comments_commentText__3vCsW`), or **(b) per-site comments API** with a sort param
     (reliable ranking, but per-site integration, possible auth/ToS gating, and *not*
     generalizable the way `schema.org` JSON-LD is). Extraction itself is automatable —
     same shape as the editorial-prose scrape.
  2. *How to judge "valuable."* **Jon-reviews** (a review/share-sheet pass over the top N)
     vs **LLM triage** that distills the top comments into a recipe note. Connects to the
     already-noted photo→LLM fallback and the existing review-before-commit flow.
- **Constraints:** comments are third-party user content — PII (display names/initials),
  plus copyright/ToS questions for *storing and re-displaying* them, and a sanitization
  step on ingest (the ATK capture already pulled in 4 commenters' names and Jon's own `JP`
  avatar). Post-M3 enrichment idea; not in the current milestone arc.

## Menus / planning model

- Does the Menus subsystem need its own ADR, and what is the canonical provenance
  model linking recipe → menu → menu placement → calendar item → grocery source?
- Is "menu" vs "meal plan" vs "cooking plan" a clean three-concept split, or do two
  of them collapse?

## Sync

- What is the trigger that says "import is trustworthy enough to enable sync"? A
  concrete data-quality checklist, or Jon's judgment call on a real library?
- Can the private CloudKit zone be reset cheaply if a bad import does sync, or must
  we treat first-sync as effectively irreversible?

## Recipe relationships — suppression vs. variation vs. collection

Design discussion 2026-06-30. The thesis: these are **three distinct primitives that
differ on *who does the managing***, and the tempting unification is the classic
premature-abstraction trap. This **challenges §22A `RecipeFamily`** in
[DATA_MODEL.md](DATA_MODEL.md), which currently bundles the first two into one entity
(an optional `preferredRecipeID` + a role-discriminated `RecipeFamilyMember` join).

1. **Suppression / preferred-canonical** — *rivals* (substitutes): the "one true
   chocolate-chip cookie" with the also-rans hidden but kept. **Asymmetric**: one real
   winner that lives in the main library, losers suppressed yet available for
   comparison. Parent **is a real recipe**. Managed: *you, once* (crown the winner).
2. **Variation cluster** — *siblings* (complements) on a shared base: Cook's Illustrated
   "Sugar Snap Peas with {almond+orange / pine-nut+lemon / sesame+ginger}". **Symmetric**:
   all members stay visible, **no winner**. Membership asserted **manually** (multi-select
   → "group as variations") — precise, never auto-derived, so no false clusters across
   2,115 recipes. Parent is a **synthetic display header, NOT a real recipe and NOT a
   `preferredRecipeID`** (don't mint a phantom recipe / pollute the count). Label is
   **LLM-proposed** (the *shared theme* — ingredient **or** technique **or** form, kept
   general), human-overridable, cached once, never re-derived on render. Grouping is
   rendered **at display time** (tall parent row + smaller child links). Managed:
   *nobody ongoing* — the list draws it.
3. **Curated collection** — hand-authored, ordered, sectioned editorial index
   ([ADR-0008](decisions/ADR-0008-curated-collections.md)). Managed: *you, ongoing*.

- **Position: don't unify suppression and variation by default.** They differ in
  cardinality (asymmetric vs. symmetric), parent semantics (real winner vs. synthetic
  header), and lifecycle (crown a winner vs. curate a peer family). §22A's role-enum +
  `preferredRecipeID` shape fits suppression but mis-fits variation. Let whichever ships
  first stand alone; only unify if the second *proves* shared structure. The tell that
  they're secretly one concept: wanting the variation parent to be "the best of the
  three" — that's primacy, i.e. suppression leaking back in.
- **Open — concrete model decision:** split §22A into two entities, or keep one entity
  with two display policies (collapse-to-preferred vs. expand-as-cluster)? Defer until
  the first of the two ships.
- **Shared prerequisite — multi-select in the recipe list.** The list is **single-select
  today** ([RecipeLibraryView.swift:728](../YesChefApp/RecipeLibraryView.swift)
  `List(selection: $model.selectedRecipeID)`). Both suppression (select the losers) and
  variation (select the siblings) need batch selection, as do batch tag/categorize/trash.
  **Build it early and separately**, ahead of and independent from either relationship
  feature. Not in the current milestone arc; sequencing TBD.
- **Sync-safe — these impose zero constraint on doing iCloud first (2026-06-30).** Every
  primitive here is *purely additive*: new tables (family / cluster header / membership
  joins) + at most a nullable column, all keyed on the existing `recipes.id` UUID. None
  touch an existing synced column, recipe identity, or primary key — and CloudKit's
  append-only schema only punishes *destructive* changes (delete/rename/retype/re-key),
  not new record types or nullable fields. So sync can ship first deploying today's
  schema, and RecipeFamily/clusters arrive later as a clean additive migration. The
  synthetic-header decision helps here: the variation parent isn't a recipe, so it can't
  perturb synced recipe records at all. **This is independent of the import-before-sync
  gate** — that gate is about import *trustworthiness*, not relationship modeling.

## Sequencing — after the browser milestone (the "fun features vs. the gate" tension)

Named 2026-06-30, as M3 (authenticated browser capture) approaches close and attention
turns to "what next."

- **The pull:** iCloud sync is a *risk* (a solvable one — see the sync-safety note above
  and [ADR-0002](decisions/ADR-0002-cloudkit-sync-no-server.md)), and risk is less fun
  than building. More features and more data-model build-out (variation grouping,
  families, collections) are the tempting next move precisely *because* they're lower-
  stakes and more gratifying.
- **Why that's a trap:** sync is also **backup**, and in Jon's "new world" durability
  matters *now*, not just multi-device convergence. Every feature built *before* sync is
  more un-backed-up data riding on a single device, and more surface that first-sync has
  to carry into an effectively-irreversible private zone. Deferring the gate to chase
  features increases the cost and risk of the eventually-unavoidable crossing.
- **The counter-discipline:** the modeling work is provably sync-safe and bolts on
  cleanly *after* sync (above), so there's no technical reason to front-load it. The only
  thing that should gate sync is **import trustworthiness** — and if backup is now a
  first-order goal, the honest question is "is import good enough to back up?", not "what
  else can we build first?" Treat post-M3 as a deliberate re-decision of the
  stabilize → import → **sync** order, with eyes open about the fun-vs-gate pull, rather
  than drifting into feature work by default. "Soon-ish done with browser" is the moment
  to make that call on purpose.

## House layer

- Any of these resolutions that generalize beyond Yes Chef (e.g. the
  "import-before-sync gate") — do they belong as a jon-platform note rather than an
  app-only one?
