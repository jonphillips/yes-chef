# ADR-0050 — The Power Browser is a **contextual faceted query**, and its gate is **coverage**, not code

Status: **Proposed** — 2026-08-01, from the browsing arc that follows ADR-0049. **Depends on
[ADR-0049 Amendment 2](ADR-0049-unified-labels-and-assisted-tagging.md#amendment-2--the-namespace-is-a-facet-and-a-facet-is-a-row-not-a-tree-position-2026-08-01)**
— it is that amendment's first consumer and the reason it exists. Governed by
[ADR-0022](ADR-0022-llm-aligned-compare-matrix.md) (advisory LLM vs deterministic write boundary) and
[ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (a saved browser is a typed query, never an encoded
blob). Extends [ADR-0006](ADR-0006-taxonomy-source-and-library-placement.md) (source/author/placement stay typed
concepts). Reuses [ADR-0046](ADR-0046-sidebar-adaptable-app-shell.md)'s shell.

**This ADR decides the query model and the gate. It deliberately does not design the UI.**

## Context

**A cook does not arrive with a finished query.** The real shape is *beef … maybe grilled … not a steak dinner …
Korean or Southeast Asian … make-ahead would be nice*, where each choice is only thinkable once the previous one
has narrowed the field. Every mechanism the app could reach for — a flat label list, a folder drill-down, a
filter sheet — asks for the whole question up front, or forces one predetermined path through information that is
genuinely multidimensional. There is **no correct ordering** of Cuisine, Protein, Dish Type and Technique, which
is exactly why `Korean > Beef > Grilled > Taco` cannot be a storage path and cannot be a navigation path either.

**The library is large enough for this to matter now.** ~2000 recipes is past the size where scrolling and
free-text search are sufficient, and it is the reason ADR-0049 exists at all — labels are only useful if
something browses them.

**The metadata is heterogeneous and must stay that way.** Facet values, scalar attributes (total time, servings,
rating), booleans (freezer suitable), source metadata (author, cookbook, publication), loose personal labels,
usage history, and full text are all browsable and **none of them share a storage model**. The tempting
simplification — make everything a category so one control renders everything — is the mirror of the mistake
ADR-0049 Amd 2 just corrected, one layer up.

## Decision

### D1 — One typed query value, and it is also the saved-browser storage

```swift
struct RecipeBrowserQuery: Codable, Hashable {
  var text: String?
  var facetSelections: [FacetSelection]        // facetID -> selected value ids
  var attributeFilters: [RecipeAttributeFilter]
  var sourceFilters: [RecipeSourceFilter]
  var looseLabelIDs: Set<Category.ID>
  var sort: RecipeSort
}
```

Shapes are illustrative; **the distinctions are binding**. A facet selection is not an attribute filter is not a
loose label is not text — collapsing them into a `[String: [String]]` bag is how the query layer loses the ability
to apply the right semantics to each, and it is a one-way door.

**One boundary owns the semantics.** A domain service or repository executes the query; no view re-derives
filtering. The predictable failure otherwise is the library list and the browser disagreeing about what
"Protein = Beef" means.

**The saved browser stores this value and nothing else** — no recipe-id membership. It re-evaluates as recipes
and classifications change; that dynamism *is* the feature. A static hand-picked collection is a different
concept and stays separate (ADR-0008 territory). Per ADR-0040 this is a typed, `Codable` value in real columns
or a versioned encoding with a **loud** decode — the `Menu.prepPlan` BLOB is the failure mode to avoid, and a
saved browser is regenerable, so a corrupt one must say so rather than present as "no filters."

### D2 — OR within a facet, AND across everything else. No boolean builder.

`Cuisine = Korean OR Mexican` **AND** `Dish Type = Taco` **AND** `Protein = Beef` → beef tacos filed as either
cuisine. Text, attributes, sources all AND in.

**Loose labels AND with each other**, deliberately asymmetric with facets: two values in one dimension are
alternatives, two personal labels are both true of the recipe. Revisit on real usage, not on symmetry.

**An arbitrary boolean expression builder is rejected, not deferred.** It is the feature that makes a browser
look powerful and get used once. Explicit `NOT` is the one plausible addition ("not a steak dinner" is in the
motivating example) and is **parked** until the default model demonstrably fails a real want.

### D3 — Hierarchical matching is derived, and the recipe stores one join

Selecting `Protein = Beef` matches recipes joined to `Beef` **and every descendant**. Selecting
`Beef > Tenderloin` matches that value and its own descendants. The recipe stores its **most specific**
assignment only (ADR-0049 Amd 2 D10); `CategoryHierarchy.descendantIDs(of:in:)` already exists and ancestor
mappings are cached, not recomputed per row.

### D4 — Facet availability and value counts are **computed from the result set**, and the counts are self-excluding

This is the whole product, and it is the only genuinely hard part of the implementation.

**Availability.** A facet is shown when it can still meaningfully divide the surviving recipes. The initial rules
are deterministic and dull on purpose: at least one surviving recipe carries a value; **at least one viable value
still partitions the result** (a lone value that narrows the set — one Beef recipe among sixty-seven Korean ones —
is a valid drilldown, so requiring two would hide useful narrowing on a sparsely classified library); selecting
something would change the result; the facet is not already fully constrained (a single value covering the whole
result divides nothing and is dropped); coverage is high enough not to mislead (D6). Ordering is **configured priority,
then narrowing potential.** Information-gain or entropy scoring is a later refinement and needs data to be worth
having; **the ranking must stay deterministic and testable** either way.

**Counts are self-excluding within their own facet.** With `Cuisine = Korean` and `Protein = Beef` selected, the
count shown next to `Mexican` answers *"how many beef recipes are Korean **or** Mexican"* — not "Korean **and**
Mexican," which is zero-ish, which would make multi-select look broken and train the user out of it. So: apply
every constraint **except the facet's own**, then evaluate under the proposed selection. This is the single most
likely thing to be implemented wrong, and it is the first test written.

**Counts are the affordance, not decoration.** A value with no count is a guess.

### D5 — Deterministic and local. **AI is never in the query path.**

Filtering, counting, availability, ranking, and saved-browser loading involve **no model call and no network**,
ever. Selecting a chip is a keystroke-latency interaction; a model in that loop makes it slow, costly,
unexplainable, and offline-fragile.

AI's role here is entirely **upstream** — assigning the classifications the browser reads (ADR-0049 D2/D3) — plus
two later, optional, clearly-labeled surfaces: suggesting taxonomy cleanup, and explaining why a recipe matched.
This is [[llm-vs-determinism-surface-boundary]] in its easiest form: the browser reads canonical shared state and
displays counts, so a plausible-but-wrong answer is indistinguishable from a right one.

### D6 — **Coverage is a gate, and it is the real schedule risk**

**A faceted browser over an unclassified library is an empty room.** Today essentially no recipe carries a
Protein, Dish Type or Technique value; if the browser shipped tomorrow, D4's own rules would correctly hide
nearly every facet, and the honest reading of that screen is "this feature does not work."

So the sequencing is not negotiable and not parallel:

> **explicit facets → proposer re-pointed at facets → a real backfill run over the library → the browser.**

ADR-0049's S5 (detail mini-labeler) and S6 ("needs labels" batch queue) are **prerequisites of this ADR**, not
siblings of it. They were scoped as consumers that justify the proposer; they are now also the mechanism that
makes this ADR's deliverable non-empty. On-device tier, no network, no per-recipe cost — the batch queue is
precisely the tool for this, and prefetch is what makes a few hundred reviews tolerable from the couch.

**The gate, concretely:** the browser surface is not dispatchable until the facets ADR-0050 promotes as primary
carry classification on a majority of the library. Below that, the work item is labeling, not browsing.
Diagnostics (D8) are what measure it, which is why they come early rather than as polish.

**Corollary — do not build ranking sophistication before there is data to rank.** Configured priority over a
half-classified library beats an entropy score over the same library, and costs nothing.

### D7 — Non-taxonomic filters keep their own semantics and their own controls

Attributes (time, servings, rating, freezer suitability, make-ahead), source (author, cookbook, publication),
usage (recently added, never cooked, cooked > 5×) and text are **first-class query members, not categories**.
Ranges get range controls, booleans get toggles, large vocabularies get searchable pickers, dates get presets.

**Rejected: encode everything as a facet value so one chip renders it all.** "Under 60 minutes" as a category
value means a write path that must maintain it, a taxonomy that lies when a recipe's time changes, and a
vocabulary polluted with things nobody would ever hand-file. ADR-0006 already put source and placement in typed
homes; this holds that line.

**Missing ≠ Other.** An unclassified recipe has *no* Cuisine, which is different from `Cuisine = Other`.
`Cuisine = Unclassified` is a **derived query predicate**, never a persisted value — it is the cleanup entry
point, and inventing a real "Other" row would poison the vocabulary permanently.

### D8 — Diagnostics ship early, because they are the labeling work list

Result count before and after each constraint, facet coverage, value distribution, facets hidden for low
discrimination, query and count timings, saved queries referencing deleted values, redundant
ancestor+descendant joins. Dev-only, in the ADR-0043 spirit: **the record is derived, never authored.** Coverage
diagnostics are how D6's gate is measured, so they are early scaffolding, not late polish.

### D9 — Saved-query durability is designed, not discovered

Saved queries reference facet, value and label **ids**. A referenced value that has been deleted, merged, or
whose facet was hidden must surface as an **unresolved selection the user can repair** — never silently dropped,
never silently ignored. A saved browser that quietly returns the wrong recipes is worse than one that says it is
broken ([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) lossless-or-loud, applied to query state
instead of parsed text). Merges migrate by re-pointing; deletions report.

### D10 — Performance is an ID-and-index problem

The query layer works over ids and indexed summary fields; full recipes hydrate only for what is on screen.
Index the recipe↔category join, facet membership and parent links, and the commonly filtered scalars; batch the
count calculations rather than looping values; cache ancestor mappings; cancel superseded queries when the user
is clicking fast. A local SQLite database over a personal library can do this directly — **no search
infrastructure, no denormalized index service.** The realistic failure is N+1 hydration inside a count loop, and
D8's timings are what catch it.

Text search may start on the existing local search and combine with structured filters afterward; the
architecture allows a dedicated index later but **must not fold structured filtering into the text index.**

### D11 — The Power Browser is not the category manager

Category management answers *"what vocabulary exists and how do I edit it?"* The Power Browser answers *"which
recipes match my intent, and what should I narrow next?"* They may share value-rendering components; they stay
separate surfaces with separate entry points. Merging them produces a screen that edits your taxonomy while you
are trying to pick dinner.

### D12 — Platform: the engine is device-independent; the surface starts where there is room

Query engine, semantics and saved state are shared. The first surface is iPad/macOS, where selections and results
are simultaneously visible — the interaction ADR-0046's shell is being reshaped for. iPhone uses progressive
sheets over **the same query value**. The one binding UI constraint: **active selections are always visible and
individually removable**, and hierarchy is disambiguated in the chip (`Protein: Beef > Tenderloin`, since
`Tenderloin` alone is genuinely ambiguous once Pork exists). Everything else is design.

## Consequences

**Positive.** Browsing supports how the intent actually forms. No single taxonomy path is imposed. Irrelevant
filters disappear rather than being scrolled past. Results stay visible. Taxonomy and typed attributes coexist
without either being deformed. Saved browsers stay live. All of it is deterministic, offline, private and
testable. The browser improves for free as classification improves.

**Negative, honestly.** Self-excluding counts and descendant roll-ups are meaningfully harder than a filter
sheet, and D4 is where the bugs will be. **The dependency on classification coverage is a real schedule risk
that no amount of query engineering removes** (D6). Saved queries need migration behavior for taxonomy churn.
Query semantics must be centralized or surfaces will drift apart. And the UI has genuine room to become a
cockpit — which is why D2 rejects the boolean builder and this ADR refuses to design the screen.

## Rejected alternatives

- **One global category tree / folder drill-down.** Choosing a branch hides every other dimension; there is no
  stable universal path.
- **A static filter sheet listing everything.** The scan cost is the problem being solved; a bigger sheet is a
  bigger problem.
- **AI-driven browsing as the primary engine** (D5). Latency, cost, offline, explainability — and it puts a
  model on canonical shared state where a plausible wrong answer looks identical to a right one.
- **Store every browsable property as a category** (D7).
- **Save recipe-id snapshots** (D1). That is a static collection, and conflating the two loses the only reason
  to save a query.
- **Arbitrary boolean query builder** (D2).
- **Build the browser first and backfill classification alongside it** (D6). The demo would work on the twelve
  recipes used to build it and fail on the library.

## Slices

Nothing here is dispatchable until ADR-0049 Amd 2 is ratified and its data pass device-confirms.

- **S0 — the labeling gate (ADR-0049 S5+S6, re-pointed at facets).** Not this ADR's code; this ADR's
  precondition. Ends when coverage on the primary facets is real.
- **S1 — the query engine, headless.** `RecipeBrowserQuery`, descendant matching, OR/AND semantics, matching-id
  retrieval, self-excluding counts, availability + deterministic ranking. Pure Core, no UI, and the count
  semantics are the first tests written.
- **S2 — the iPad/macOS surface.** Search field, selection chips, ranked facets, expandable values, results,
  sort, clear. *Batchable with S3 if S1 lands clean.*
- **S3 — attribute, source and usage filters** with type-appropriate controls. Source reads the ADR-0006 typed
  fields (D7 / OQ4).
- **S3.5 — re-point `RecipeActiveFilterBar` onto the engine** (OQ2). A deletion, not an addition; the filter
  bar's UI is unchanged. Do this *after* the engine is proven, and treat "the phone list and the browser now
  agree on what a selection means" as its acceptance test.
- **S4 — saved browsers**, including D9's unresolved-selection repair. **Replaced by Amendment 1** (Lenses):
  a saved browser is a zero-shelf Lens, built in slices L1–L2.
- **S5 — iPhone presentation** over the same engine.
- **S6 — classification diagnostics and cleanup entry points**, promoted out of D8's dev-only scaffolding.
  **Partial: the existing facet work list is a Release labeling surface** (`Settings → Label Recipes`) that routes
  directly to the per-recipe tag editor. The queue is usable now; suggestion prefetch across it is the fast
  follow-on, with no change to the labeling engine or proposer in this slice.
- **Parked, explicitly:** personalized ranking, information-gain scoring, AI match explanations, `NOT`,
  primary/secondary values. Each needs a real want, not this ADR's momentum
  ([[withdraw-not-defer-orphaned-schema]]).

## Resolved

- **OQ1 — the Power Browser lives as its own app-shell tab (closed 2026-08-09).** It is
  neither a Library mode nor a sheet over the Library: browsing is a distinct task with a
  simultaneous facets-and-results layout on iPad/macOS. The existing `Browser` tab remains the
  web-capture workspace, so the Power Browser has its own clearly named entry point rather than
  overloading capture navigation.

- **OQ2 — the library filter bar stays, and becomes a preset over `RecipeBrowserQuery` (closed 2026-08-01).**
  The existing filter bar is good on the phone and is **not** being replaced as a surface. What it stops doing
  is computing filtering *itself*. Today `RecipeListRequest` fetches every recipe and
  `RecipeLibraryListState` filters in memory over **display-name strings** — `selectedCategoryNames` is a
  `Set<String>` matched with `isSubset(of:)`, and `CategoryHierarchy.filterDisplayNames` pre-expands ancestor
  names into each row. That is a second, stringly implementation of D3, and it will **disagree** with this ADR
  in three specific ways:

  1. **`isSubset` is AND within a dimension.** Selecting Korean and Mexican today returns recipes that are
     *both* — near zero. D2 says it returns either. Two screens of one app teaching contradictory rules.
  2. **Names are not identities.** After ADR-0049 Amd 2, `Protein > Beef > Tenderloin` and
     `Protein > Pork > Tenderloin` are distinct values that share a display name. String matching hits both.
  3. **Pre-expanded ancestor names are hand-maintained descendant matching**, which has to be kept in step with
     the real one forever.

  So: the filter bar constructs a `RecipeBrowserQuery` (a few facet selections plus a sort), the shared engine
  evaluates it, the bar renders the result. **No visual change and no lost affordance on the phone**, and it
  lands as a *deletion* — the in-memory filter loop goes away rather than a layer being added. The phone also
  gets saved browsers for free: a saved browser is just a query value, so **iPad/macOS composes them and the
  phone opens them**, which is a better split than "the phone gets the lesser filter." Scheduled as S3.5,
  after the engine exists — not part of S1.

- **OQ4 — source filters read the typed recipe fields, not facets (closed 2026-08-01).** Follows ADR-0049 Amd 2
  OQ5. Author, cookbook, publication and website are ADR-0006 typed metadata; D7's source filters query those
  fields directly. There is no Cookbook facet to fall back to and there should not be one.

## Open

- **OQ3 — what is the coverage threshold in D6's gate, numerically?** Cannot be answered until D8's diagnostics
  measure the library. Deliberately left open rather than guessed.
- **OQ5 — the typed `Recipe.cuisine` / `Recipe.course` fields are redundant with the Cuisine/Course facets, and
  their fate is unscoped.** Observed on device 2026-08-03: the library filter's **Fields → Cuisine** control
  reads the typed `Recipe.cuisine` free-text column (`RecipeLibraryListState.cuisineFilterOptions` →
  `distinctOptions(…\.recipe.cuisine)`), while **Categories → Cuisine** reads the ADR-0049 Amd 2 facet. They
  disagree — a recipe filed under the `Cuisine: Thai` facet value does not appear under Fields → Cuisine unless
  it *also* carries the string "Thai" in the typed column, which is sparsely populated (schema.org
  `recipeCuisine` at import, or hand-entry in the editor's Fields section). This is a fourth stringly parallel to
  the three OQ2 lists.

  **This is NOT the same as OQ4.** OQ4 keeps source/author/cookbook/publication typed *on purpose* — there is no
  source facet and should not be one. Cuisine and Course are the opposite: ADR-0049 **D6 routes `recipeCuisine`
  into the Cuisine facet**, so these two typed fields are on a *retirement* path, not a keep path. The open
  question is the retirement itself — (a) migrate existing typed `cuisine`/`course` values into facet assignments
  (a synced data pass, deterministic-UUID/post-engine, [[migration-writes-bypass-sync-triggers]]); (b) drop the
  editor's Fields cuisine/course inputs; (c) delete the Fields → Cuisine/Course filters, which S3.5's re-point
  makes redundant rather than re-points. Sequenced with S3.5 (the filter-bar re-point) and gated behind the same
  Dispatch 4 coverage backfill; do not fold it into the D5 editing slice. Whether the typed columns are then
  physically dropped is a separate schema call, deferred like every other column retirement.

  **Design constraint the retirement must honor (Jon, 2026-08-04): preserve the per-facet picker affordance —
  rebind it, don't delete it.** What is worth keeping about the typed fields is not the free-text column but the
  *interaction*: a fast single-select **dropdown per facet** (pick one `Cuisine`, pick one `Course`) is
  meaningfully quicker than drilling the sectioned Categories tree (F1) for a flat, single-ish facet. So step (b)
  is **replace the free-text input with a facet-value picker**, not "delete the field and send the user to the
  tree." You lose only the free-text divergence (a typo can't happen when choosing an existing value); you keep
  the speed. Likely end state is **per-facet single-select pickers for the common single-ish facets +
  tree/mini-labeler for multi-value and nested facets** — the two are complementary, F1's tree is not wasted.
  Crucially this needs **no schema**: "one Cuisine per recipe" is already a *soft picker convention, not a
  constraint* (D8 / ADR-0049 OQ2), so a dropdown that presents single-select while the model still permits multi
  is pure UI. It touches the deferred `selectionMode` column (ADR-0049 D8) **only** if the schema must actively
  *prevent* a second value — which the soft convention says it must not. Ship the picker as an affordance, not a
  data-model change.

## Amendment 1 — saved browsers become **Lenses**: a base query plus ordered shelves (2026-10-31)

**The want (Jon, 2026-10-31).** Browsing by one cuisine for a dinner returns a flat result, and the cook
wants it laid out by what is appropriate to that cuisine: a Mexican view with a shelf of antojitos, a shelf of
tacos, a shelf of salsas; an Indian view with curries, dals, breads. The layout is chosen by the cook, saved, and
reopened any time. It is mostly an iPad surface. **S4's "saved browser" is one flat query, which cannot express
this.** It also turns out to be the degenerate case of it.

### A1-D1 — A Lens is a base query and an ordered list of shelves, and nothing else

```swift
struct RecipeLens {
  var name: String
  var baseQuery: RecipeBrowserQuery          // "Cuisine: Mexican"
  var shelves: [Shelf]                        // ordered
  var showsRemainder: Bool                    // A1-D3

  struct Shelf {
    var title: String                         // "Tacos"; defaults to the selected value's name
    var query: RecipeBrowserQuery             // "Dish Type: Taco"
  }
}
```

Shapes are illustrative; the distinctions are binding. A shelf's predicate is **a full `RecipeBrowserQuery`, not a
category id.** Tags are the expected common case and the editor leads with them, but a "Weeknight" shelf
(`total time ≤ 45`) or a "Never cooked" shelf costs nothing extra and a category-only shelf would have to be
widened later through a schema change. D7 still holds inside a shelf: an attribute is not a category there either.

**A Lens with zero shelves is a saved browser.** S4 is therefore *replaced*, not built alongside: there is one
saved thing, not two. Opening a zero-shelf Lens opens the Power Browser on its base query, which is exactly what
S4 described. Opening a Lens with shelves opens the shelf view.

**Still a typed query, still no recipe-id membership** (D1). A Lens re-evaluates as the library and its
classification change. Hand-picked membership remains ADR-0008's curated collections; a Lens never pins a recipe.

### A1-D2 — A shelf is `matches(base) ∩ matches(shelf)`, set intersection, never a merged query

The shelf's recipes are the intersection of two independently evaluated results. **The two queries are not
merged into one**, because D2's OR-within-a-facet would make a merge wrong exactly when both name the same
facet: base `Cuisine: Mexican`, shelf `Cuisine: Oaxacan` merges to `Mexican OR Oaxacan` (all of Mexican, since
Oaxacan descends from it), while the intersection is the Oaxacan recipes, which is what the cook meant.
Intersection needs no new semantics in the engine: it evaluates two ordinary queries and the Lens intersects
their id sets. D3's descendant matching applies inside each query as usual.

**Shelves may overlap.** A recipe that is both a taco and make-ahead appears on both shelves; shelves are views,
not filing. Each shelf sorts by its own query's `sort`.

**"See all" on a shelf stays inside the Lens** (a full grid of that one shelf), because there is no single
`RecipeBrowserQuery` that equals an intersection in general. The Lens's hand-off to the Power Browser is its
**base query only** ("browse all Mexican"), which is always exact.

### A1-D3 — The remainder shelf is derived, and it doubles as the labeling work list

When `showsRemainder` is on, a final **Everything else** shelf shows `matches(base) − ⋃ matches(shelf)`. It is
computed, never stored, and has no editable predicate. It is useful when browsing ("what else is Mexican?"), and
it is D6's coverage gap made visible inside the cook's own frame: a large remainder on the Mexican Lens usually
means Mexican recipes with no Dish Type. Each remainder recipe reaches the per-recipe tag editor the same way
the S6 `Label Recipes` queue does. Default on.

### A1-D4 — Empty is quiet; broken is loud

Two different states, never rendered the same way:

- **Empty** — the shelf's query is valid and today's intersection has no recipes. Hidden in the shelf view, shown
  with a count of 0 in the Lens editor. This is normal; a "Moles" shelf can be empty until the first mole is
  captured.
- **Unresolved** — the base or a shelf references a facet, value or label that has been deleted, merged away or
  hidden. **D9 applies unchanged**, to the base and to every shelf: the selection surfaces as unresolved and
  repairable, merges re-point, deletions report. An unresolved shelf is **shown, never hidden**, with its repair
  affordance. Hiding it with the empty ones would make a broken Lens look like a sparse one.

An unresolved base query makes the whole Lens unresolved: shelves cannot be evaluated against a base that no
longer means what it was saved to mean.

### A1-D5 — Suggested shelves come from the engine's counts, not from a model

The Lens editor offers candidate shelves for the current base: the engine's existing availability and
self-excluding counts (D4) over the base result, ranked by D6's configured facet priority. Pick Mexican and the
editor offers "Dish Type: Taco (14), Salsa (11), Soup (7); Course: Appetizer (9) …" to check off. Deterministic,
offline, no model call (D5). Suggestions are only offers; a shelf exists when the cook adds it.

### A1-D6 — Storage: a Lens row and ordered shelf rows; each query is a versioned value with a loud decode

Two **synced** tables, so a Lens built on the iPad opens on the phone:

- `recipeLenses` — `id`, `name`, `baseQuery` (TEXT), `showsRemainder`, `sortOrder`, timestamps.
- `recipeLensShelves` — `id`, `lensID` (FK, cascade), `title`, `query` (TEXT), `sortOrder`.

Shelves are rows because they are the grain the cook edits: added, removed, renamed and reordered one at a time
([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)). A whole Lens encoded as one blob would turn a
reorder into a rewrite and a conflict between devices into a lost shelf. **The query inside a row is a value, not
a grain**: the cook edits it whole through the browser's controls. It is stored as D1 already allows, a
versioned `Codable` encoding with a **loud** decode. A query that fails to decode is a broken shelf under A1-D4,
reported in place; it never decodes to an empty query, which would match the whole base and look like a working
shelf. Decoding happens at read time in the feature, never in a migrator ([[loud-decode-not-in-migrator]]).

Both tables have a consumer that ships with them ([[synced-table-cost-calibration]]). Both join `makeSyncEngine`'s
synced tables and reach Production through an additive Development→Production schema deploy checked against
[PROD-CUTOVER](../PROD-CUTOVER.md) Reference A's diff. Every column, `showsRemainder` included, must have uploaded a
non-nil value in Development before that deploy, or the field is missing in Production and uploads fail.

### A1-D7 — Platform: shelves where there is width, sections where there is not

D12 holds: the engine and the Lens evaluation are shared Core; the surface starts on iPad/macOS. The binding UI
constraints are few:

- **On regular width, each shelf is a horizontally scrolling row** with a count and "See all"; shelves stack
  vertically in Lens order.
- **The base query is always visible** on the Lens screen, as D12's chips (`Cuisine: Mexican`).
- **"Save as Lens"** from the Power Browser seeds a zero-shelf Lens from the current query.

On compact width (S5), the same Lens renders as vertical sections, each showing its first few recipes and
"See all". The phone opens and uses Lenses; editing them there is not required. Where Lenses appear in the
ADR-0046 sidebar is design, not decision.

### Rejected

- **A shelf as a single category id.** Narrower than the query value already built, and widening it later is a
  schema change (A1-D1).
- **Merging base and shelf into one query** (A1-D2).
- **Keeping S4 saved browsers as a separate concept.** Two saved things with overlapping meaning, one of which
  is a special case of the other.
- **Nested shelves or per-shelf sub-sections.** A Lens is one level. A cook who wants Tacos → Fish / Pork wants a
  Tacos Lens.
- **Manual recipe pinning on a shelf.** That is ADR-0008's static collection (D1).
- **Model-generated Lenses or shelf suggestions** (D5). A1-D5's counts answer the same want deterministically.

### Slices (replace S4)

- **L1 — Lens core and schema.** The two tables and their migration; the `RecipeLens` value, versioned query
  encoding with loud decode; evaluation (per-shelf intersection, remainder, empty vs unresolved, A1-D4); D9
  unresolved detection over base and shelves; shelf suggestions (A1-D5). Core tests lead with the intersection
  semantics (including the same-facet base/shelf case from A1-D2), remainder correctness with overlapping
  shelves, and a corrupt-encoding shelf reporting as broken rather than empty.
- **L2 — iPad/macOS Lens surface.** The shelf view, "See all", the Lens editor (add from suggestions or from a
  Power Browser query, rename, reorder, remove, remainder toggle), "Save as Lens" from the Power Browser, and the
  unresolved-shelf repair affordance. *Batchable with L1.*
- **S5 (unchanged slot) — iPhone presentation** now also opens Lenses as vertical sections.
