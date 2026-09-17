# ADR-0057 — Prepared Components are **recipes with a `kind`**, linked to the dishes that use them by a **directional recipe-grain edge**; the flavor vocabulary is **one new facet surfaced as "Dimension"**; the on-hand inventory ledger stays **out**

> **Vocabulary.** A *component* (a.k.a. prepared component / larder item) is a recipe made to be **reused** —
> chicken glace, seed crunch, Dijon-shallot vinaigrette, brown butter, salsa verde. A *dish* is a recipe cooked
> to be eaten. A *dimension* is a flavor/texture function a recipe **provides** or **has** — ACID, CRUNCH, UMAMI,
> BODY, RICH, FRESH, ALLIUM, HEAT (the [`FUTURE_INTELLIGENCE_AND_PLANNING.md`](../FUTURE_INTELLIGENCE_AND_PLANNING.md)
> §12 menu-balance vocabulary). "Larder" is the browsable view of your components; it is **capability** ("what I
> can deploy"), never **inventory** ("how much of it I have right now").

Status: **Proposed** — 2026-09-17. **Not yet ratified, and deliberately not scheduled: this is post-cutover work**
(D7). Origin: Jon, pressure-testing a ChatGPT "home-larder / prepared-components" pitch and asking for it to be
right-sized rather than cheerled. The measured result is that most of the pitch is already our roadmap
([`../PRODUCT_BRIEF.md`](../PRODUCT_BRIEF.md), [`../FUTURE_INTELLIGENCE_AND_PLANNING.md`](../FUTURE_INTELLIGENCE_AND_PLANNING.md)
§4.4/§11/§12/§14) and the one load-bearing new abstraction is small. Worked design + slice detail live in the
companion effort [`../efforts/prepared-components.md`](../efforts/prepared-components.md). Governed by
[ADR-0056](ADR-0056-move-to-production-and-data-carry.md) + [`../PROD-CUTOVER.md`](../PROD-CUTOVER.md) (the one-way
Dev→Prod schema deploy that makes *breaking* schema expensive after cutover, and why this is all additive),
[ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (editable at the grain stored), and the house style rule
that impossible states stay unrepresentable (enums over flag-soup — jon-platform swift-style §3). Prior art in
code: [`Facet.swift`](../../YesChefPackage/Sources/YesChefCore/Facet.swift) (the taxonomy-axis table),
[`RecipeRelatedRecipe.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeRelatedRecipe.swift) (loose-column
synced edge + the CloudKit single-FK note), [`RecipeServeWith.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeServeWith.swift),
[`PantryPolicy.swift`](../../YesChefPackage/Sources/YesChefCore/PantryPolicy.swift). Concept links:
[[recipe-as-reusable-function]], [[larder-is-capability-not-inventory]], [[additive-schema-is-post-cutover-safe]].

## Context

Cooking has an intermediate layer that most recipe software elides: `ingredients → prepared components → dishes`.
A serious home cook builds a stock of reusable preparations (stock concentrate, glace, vinaigrette, pickles, sauces)
and finishes dishes from them. Yes Chef's model today is `ingredients → recipe`, with no first-class notion that a
recipe can *be* a reusable building block another recipe consumes.

The provoking input was a ChatGPT pitch to add a full "Larder / PreparedComponent" subsystem: a new entity, per-item
metadata, function tags, and a stateful "what's on hand / use soon" screen with made-dates and remaining portions.
Evaluated against what already exists, most of it is already ours and one piece is genuinely missing:

- **Already shipped or roadmapped, do not rebuild:** component *planning* (§4.4), the flavor/menu-balance vocabulary
  (§12) and the first-class [`Facet`](../../YesChefPackage/Sources/YesChefCore/Facet.swift) table, "goes-with"
  suggestion (`RecipeServeWith`, `MenuComplement`/`MealPlanComplement`), substitutions (§8.4), and the recipe
  intelligence metadata track (§11: `suitability`, `makeAheadScore`, `activeWorkload`).
- **Genuinely missing — the load-bearing abstraction:** a recipe cannot declare *"I use your Chicken Glace"* as a
  first-class, directional fact the app can reason over. `RecipeRelatedRecipe` is symmetric and untyped;
  `RecipeServeWith` is loose title strings.
- **Explicitly out — a boundary already settled:** a per-instance stock ledger. `PRODUCT_BRIEF.md` lists *"Automatic
  pantry deduction"* and *"Restaurant-style inventory management"* as non-goals; §14 records that *"pantry quantity
  is not a feature goal … modeled as memory, assumptions, and shopping policy, not a stock ledger the user has to
  maintain."* The pitch itself named this trap ("the road to SAP for pickled shallots") and then walked into it.

The whole app is local-first SQLite + CloudKit sync, no server ([ADR-0056](ADR-0056-move-to-production-and-data-carry.md)),
so every new table is a synced surface and a migration, and — critically — the imminent Dev→Prod cutover makes
*breaking* schema changes one-way after the fact. Any component design must therefore be **additive** and small.

## Decision

### D1 — A component **is** a `Recipe` with a new `kind`; no `PreparedComponent` entity

Add one field to [`Recipe`](../../YesChefPackage/Sources/YesChefCore/Models.swift):

```swift
public enum RecipeKind: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable {
  case dish        // default — a recipe cooked to be eaten
  case component   // a recipe made to be reused
}
// on Recipe:  public var kind: RecipeKind   // additive, migrates in defaulted to .dish
```

An enum, matching the house pattern already on `Recipe` (`RecipeDifficulty`, `RecipeLibraryPlacement` at
[`Models.swift:183`](../../YesChefPackage/Sources/YesChefCore/Models.swift)) — **not** a `Bool isComponent`, so the
type stays honest if a third kind ever appears. A `.component` reuses the *entire* recipe model — editor, scaling,
`originalSnapshot`, sync, backup, import/export — for free, which is the whole reason not to invent a parallel
entity. The pitch's per-component metadata (`concentration 4×`, `yield`, `portionSize`, storage life, make/buy,
effort, uses) is **not new storage**: it rides the §11 intelligence-metadata track, shared with dishes, most of it
optional prose. The `4×` concentration stays prose until a second concrete consumer proves it deserves a typed field.

**Promotion rule (authoring gate, not a schema constraint):** a recipe becomes `.component` only when it is
*deliberately reused* — reusable across ≥3 plausible dishes, or intentionally produced/stored for future cooking. A
dish's private subassembly (the squash purée for one langoustine course) stays a plain recipe or an ingredient
section; it earns `.component` only when reuse actually shows up. This keeps the library from filling with one-off
intermediates.

### D2 — The dish→component link is a **new, directional, recipe-grain** synced edge table

```swift
@Table("recipeComponentLinks")
public struct RecipeComponentLink: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID      // the dish        (loose column, not a SQL FK)
  public var componentID: Recipe.ID   // the .component   (loose column, not a SQL FK)
  public var sortOrder: Int
  public var dateCreated: Date
}
```

Both IDs are **loose columns**, for the same reason [`RecipeRelatedRecipe`](../../YesChefPackage/Sources/YesChefCore/RecipeRelatedRecipe.swift)
uses them: a second SQL foreign key on one record is incompatible with SQLiteData's CloudKit sharing model (see the
comment on the `recipeRelatedRecipes` migration, [`Schema.swift:1247`](../../YesChefPackage/Sources/YesChefCore/Schema.swift)).
Registered as a synced table with a data-free creating migration and an **index on `componentID`** for the reverse
lookup, mirroring the `recipeServeWith` pattern ([`Schema.swift:1030`](../../YesChefPackage/Sources/YesChefCore/Schema.swift)).

This is **not** a reuse of `RecipeRelatedRecipe`, which is deliberately *symmetric*. Component-usage has a direction:
a dish uses a component, not the reverse. Encoding that direction is what makes the reverse view *correct* rather
than mushy.

**Directional ≠ one-way queryable.** The edge is read from both ends:
- on a dish, `WHERE recipeID = …` → the **"Components used"** section;
- on a component, `WHERE componentID = …` → the **"Used in these dishes"** section (the reverse lookup the
  `componentID` index serves).

Scope line, to prevent feature creep at the query layer: this edge answers **"what dishes use this component?"**
exactly. The looser **"what should I make *with* this component?"** is a different, superset question served by
dimension-coverage reasoning (D4) plus `RecipeRelatedRecipe`/`ServeWith` — not by this table.

### D3 — Linking is at **recipe grain**; ingredient-line linking is **declined** (with the cost stated)

A dish links to the components it uses at the **recipe** level, surfaced in its own section. We deliberately do
**not** link an individual ingredient line ("½ cup chicken stock") to a component.

The reason is cost, not ideology. An ingredient-line link needs a stable `ingredientRef` that survives a base-text
edit — the exact anchor-repair failure mode that bit recipe variations when anchors were taken from model output
(see [`../efforts/variation-anchor-repair.md`](../efforts/variation-anchor-repair.md)). That is a real rabbit hole,
and recipe-grain linking sidesteps it entirely while keeping most of the payoff.

The cost, stated plainly so a future reader doesn't think it was missed: we **lose the inline behaviors** — a dish
cannot auto-rewrite "½ cup stock" into "use 2 Tbsp of your 4× concentrate" *at that line*, and make-extra cannot
anchor to a specific ingredient. What survives at recipe grain: "this dish uses your Salsa Verde / Chicken Glace,"
substitute-down, "you already have the sauce," and the whole capability-awareness payoff — i.e. most of the value,
none of the anchor risk. If inline linking ever earns its keep, it is a **separate future ADR** that must bring its
own anchoring story; this ADR does not open it.

### D4 — The flavor vocabulary is **one new facet**, surfaced to the user as **"Dimension"**; the `Facet` type keeps its name

[`Facet`](../../YesChefPackage/Sources/YesChefCore/Facet.swift) is Yes Chef's **taxonomy axis**, not a generic tag
bag — "Cuisine" and "Course" *are* facets (it was migrated in as "Promote category namespaces to facets"), and
Italian / Appetizer are values under them. So the flavor/texture vocabulary is modeled as **one new facet whose
values are the dimensions** (ACID, CRUNCH, UMAMI, …), reusing the entire facet mechanism — tagging, coverage
(`RecipeFacetCoverage` / `SeedCoverageReport`), browse/filter — with **zero schema change**. We do **not** invent a
parallel `function` field.

Naming: **leave the table and type named `Facet`.** It is shipped into the Production-bound schema, and "facet" is
genuinely correct for a taxonomy axis (a recipe's cuisine *is* a facet of it); a rename is a breaking change bought
purely for taste. `Facet` is an internal name the user never sees — the user sees the facet's `name`. So the new
flavor axis gets the **user-facing label "Dimension"** (Profile/Flavor are alternatives — see OQ1). Splitting the
concern is strictly better than a rename: "Dimension" fits the flavor axis; "Facet" still fits Cuisine/Course.

**Reasoning nuance for the coverage layer, not a storage one:** for a `.component`, a dimension value means "what
this *provides*" (glace provides UMAMI/BODY); for a `.dish`, it means "what's *present*." Same storage (a facet
value tagged on a recipe); the make-extra / gap-analysis logic reads it in both senses. Compositional reasoning
("this plate has richness and acid but no freshness → your Salsa Verde") then falls out of coverage the machinery
already computes — deterministic core computes, AI only narrates (§7.5).

### D5 — `kind` is **orthogonal** to `libraryPlacement`; it is a new axis, not an overload

[`RecipeLibraryPlacement`](../../YesChefPackage/Sources/YesChefCore/Models.swift) (`main` / `reference`) is a
*where-it-sits* axis. A component is not a `reference` recipe: it is a normal, cookable, favoritable `main`-library
recipe that happens to be built for reuse. Overloading `reference` (or adding a `component` placement case) would
conflate "what it is" with "where it lives" and break both queries. `kind` is its own orthogonal axis. A component
is `kind: .component` and typically `libraryPlacement: .main`.

### D6 — The on-hand / "use soon" inventory ledger is **out of scope, and stays out**

The pitch's Larder screen with *Available / Low / Gone*, "made Tuesday", "8 portions in freezer", "use soon" is
**not** built. It requires per-instance mutable state (a made-date and a remaining quantity on every jar) that the
cook maintains by hand — the exact non-goal in `PRODUCT_BRIEF.md` and the exact boundary §14 settled. Our existing
[`PantryPolicy`](../../YesChefPackage/Sources/YesChefCore/PantryPolicy.swift) (`unlimited / threshold /
alwaysConfirm`) is assumptions, not stock, and correctly so. The larder in this ADR is **capability** — the set of
components you know how to make and have linked — reachable without tracking a single made-date or portion.

If perishability ever earns its place, the sanctioned door is §14's bounded **"Inventory Confirm"** (a threshold on
a pantry item routes a grocery line to a review bucket instead of silently skipping it), which reuses `PantryPolicy`
and would need a real measurement-normalization layer — not a new stock table, and not this ADR.

### D7 — This is **post-cutover** work; all schema here is additive, so waiting costs nothing

`Recipe.kind` is a defaulted additive column; `RecipeComponentLink` is a new table; the Dimension facet is data, not
schema. Under the one-way Dev→Prod schema deploy ([ADR-0056](ADR-0056-move-to-production-and-data-carry.md),
[`../PROD-CUTOVER.md`](../PROD-CUTOVER.md)) the expensive, can't-take-back changes are *breaking* ones (rename,
retype, remove); additive columns and record types are safe to add **after** Production is live as a normal reviewed
migration. So there is **no forcing function** to build before ship, and the cutover runbook is going the other way
(Phase 1 *drops* dead columns to reach a clean baseline). The only "if already certain" option is folding the single
additive `Recipe.kind` column into the Phase 1 squash to skip one later migration — a one-migration saving, **not** a
reason to manufacture certainty or widen the frozen baseline. Ship cutover clean; build components after.

## What this costs — stated plainly

- **Two new synced surfaces** (`Recipe.kind` column + `RecipeComponentLink` table) — a migration, a registration,
  sync traffic, backup/import-export coverage, permanent once promoted to prod ([[synced-table-cost-calibration]]).
  Small, but non-zero.
- **No inline ingredient behaviors** (D3). Make-extra and substitute-down operate at recipe grain, not per line.
  Accepted, and reversible later via a dedicated ADR — but it is a real capability we are choosing not to have now.
- **The "provides vs. present" asymmetry lives in the reasoning layer** (D4), not the schema. If coverage logic
  forgets which sense it's in, a component could be scored as if it "needs" the dimension it supplies. The gap
  analysis must read `kind` alongside the dimension tags.
- **A component pollutes the main library list** unless the UI accounts for it (OQ2). Ten vinaigrettes and a glace
  interleaved with dinners is noise if unhandled.

## Alternatives considered and rejected

- **A first-class `PreparedComponent` entity.** Rejected: it duplicates the recipe model (editor, scaling, snapshot,
  sync, import/export) for no semantic gain. A component *is* a recipe; `kind` says so cheaply (D1).
- **An ingredient-line → component link (`ingredientRef`).** Rejected for now (D3): the anchor-repair cost is real
  and the recipe-grain link captures most of the value. Left as a future ADR, not a never.
- **Reusing `RecipeRelatedRecipe` for the link.** Rejected: it is symmetric; component-usage is directional (D2).
- **Renaming `Facet` to `Dimension`.** Rejected: breaking change to shipped schema for a word the user never sees;
  "Dimension" is the *user-facing label* of a new facet instead (D4).
- **A parallel `function`/`dimension` tag field on Recipe.** Rejected: it is exactly what the `Facet` mechanism
  already is (D4).
- **Building the on-hand inventory ledger.** Rejected: reopens a settled boundary (D6).

## Open questions

- **OQ1 — the user-facing label.** "Dimension" vs. "Profile" vs. "Flavor" for the new facet. Leaning "Dimension";
  not load-bearing, decide at build.
- **OQ2 — where components appear.** Main library list, a separate "Larder" shelf, or both, and how they filter
  (by dimension). Browsability vs. noise; likely a filtered view over `kind == .component`, not a separate store.
- **OQ3 — import/export + backup coverage.** `kind` and `RecipeComponentLink` must round-trip, and old backup JSON
  lacking `kind` must still decode (unknown-keys-ignored, as the cutover squash already relies on). Confirm in S1.
- **OQ4 — make-extra economics home.** The "brown 8 oz, use 2 Tbsp, keep the rest" decision is a deterministic core
  function (storage-life + portion math), with AI only phrasing it (§7.5). Confirm it does not leak into a model call.
- **OQ5 — convergence with `ServeWith`.** `RecipeServeWith` (loose "goes with" strings) and the component link
  overlap conceptually. Do they stay separate, or does a serve-with entry that resolves to a saved recipe become a
  component link? Defer until both have real data; do not pre-merge.

## Slices (post-cutover)

- **S1 — `Recipe.kind` + the Dimension facet + authoring.** Additive `kind` column defaulted to `.dish`
  ([`Models.swift:5`](../../YesChefPackage/Sources/YesChefCore/Models.swift)); an affordance to mark a recipe a
  component (promotion rule in copy, not schema); seed the flavor-function facet (label "Dimension"). Import/export +
  backup coverage and the old-JSON decode check (OQ3). No link yet. Ships value alone: a browsable component shelf,
  filterable by dimension. Fully unit-tested in `YesChefCore`.
- **S2 — the directional link + "Components used" / "Used in".** `RecipeComponentLink` `@Table` + `Schema.swift`
  registration + data-free creating migration + `componentID` index (D2); forward section on the dish, reverse
  section on the component. Test both reads, sort order, and that deleting a component leaves no dangling render
  (dangling-edge tolerance, as `RecipeRelatedRecipe` handles).
- **S3 — make-extra + substitute-down.** §11 storage-life/effort metadata + deterministic economics; AI narrates.
  No inventory state (D6). OQ4 resolved here.
- **S4 (maybe, its own ADR) — "improve this dish" / "you already have."** Dimension-coverage narration over a dish +
  the set of known components.
- **Not planned:** the on-hand/use-soon ledger (D6); ingredient-line linking (D3). Each reopens only as its own
  decision.

## Verify

Package build + new `YesChefCore` tests + `swift test --skip-build`; `check-drift.sh`; one iPad build (`xcodegen
generate` first — new source files + schema). Unit coverage in core: `kind` defaults to `.dish` on migrate and on
decode of `kind`-less JSON; a component and a dish are queryable by `kind`; the link reads correctly from both ends;
a deleted component does not crash either render; the Dimension facet tags and its coverage compute. Device pass
(Jon): mark a recipe a component, link it into a dish, confirm "Components used" on the dish and "Used in" on the
component, and confirm both held on a second device after sync.
