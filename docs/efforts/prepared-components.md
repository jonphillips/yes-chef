# Effort — Prepared Components (the reusable intermediate layer)

**Status:** Designed (proposal) — **not dispatched, not an ADR.** Feeds a future ADR; nothing here
is ratified. Explicitly **post-cutover** work (see Timing).
**Summary:** Give cooking its missing middle layer — `ingredients → prepared components → dishes` —
by letting a recipe *be* a reusable component and letting a dish *link to* that component at
**recipe grain** (a "components used" section, not an inline ingredient-line link — see §2). The
abstraction is a `Recipe.kind` enum plus one **directional** dish→component edge table; it is entirely
**additive** schema. The stateful "what's in my larder right now / use soon" inventory ledger
is **parked**, on purpose — it reopens a boundary [`FUTURE_INTELLIGENCE_AND_PLANNING.md`](../FUTURE_INTELLIGENCE_AND_PLANNING.md)
§14 already settled.
**Related:** [`../PRODUCT_BRIEF.md`](../PRODUCT_BRIEF.md) (non-goals: *automatic pantry deduction*,
*restaurant-style inventory management*) · [`../FUTURE_INTELLIGENCE_AND_PLANNING.md`](../FUTURE_INTELLIGENCE_AND_PLANNING.md)
§4.4 (Component Planning), §11 (Recipe Intelligence Metadata), §12 (Menu Balance), §14 (Pantry
Intelligence — the *settled boundary* and the bounded "Inventory Confirm" idea) ·
[ADR-0056](../decisions/ADR-0056-move-to-production-and-data-carry.md) + [`../PROD-CUTOVER.md`](../PROD-CUTOVER.md)
(the one-way Dev→Prod schema deploy that makes *breaking* schema expensive after cutover, and why this
work is additive) · [ADR-0021](../decisions/ADR-0021-recipe-variations.md) (recipe-to-recipe modeling
prior art) · [ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) (editable at the
grain stored). Code prior art: `RecipeRelatedRecipe` (symmetric synced edge + the CloudKit single-FK
note), `RecipeServeWith`, `Facet`, `MenuComplement`/`MealPlanComplement`, `PantryPolicy`. Concept links:
[[recipe-as-reusable-function]], [[larder-is-capability-not-inventory]].

## Why this exists (and why most of the pitch is already ours)

The provoking prompt: "does a home-larder / prepared-components system belong in Yes Chef?" The measured
answer is **yes for one narrow abstraction, no for the inventory app it wants to become** — and most of
the surrounding pitch is our own roadmap handed back to us. Logged here so we don't "re-discover" it:

| The idea, as pitched | Where it already lives |
|---|---|
| Components as reusable recipes | §4.4 **Component Planning** — stock, aioli, marinade, beans, verbatim |
| Function tags (ACID / CRUNCH / UMAMI / BODY) | §12 **Menu Balance** dimensions **and** the first-class `Facet` table already in schema |
| "You already have Tahini-Lemon Sauce; finish with it" | `RecipeServeWith` + `MenuComplement`/`MealPlanComplement` |
| "Improve this dish" from what's on hand | §12 menu-balance narration |
| Substitutions when a component is missing | §8.4 |
| make/buy, storage life, effort, "suited-for" | §11 **Recipe Intelligence Metadata** (`suitability` OptionSet, `makeAheadScore`, `activeWorkload`) |

**The one genuinely missing abstraction** — the load-bearing thing — is that **a dish cannot say it uses
one of your components.** `RecipeRelatedRecipe` links *recipe→recipe* but symmetrically and untyped;
`RecipeServeWith` is loose title strings. Neither lets a dish declare "this uses your Chicken Stock
Concentrate" as a first-class, directional fact the app can reason over. That link is what unlocks
"you already have the sauce," substitute-down, and capability-awareness. It is the function-call factoring
a cook with a software brain keeps reaching for. Everything else is polish on top of it.

We deliberately draw the link at **recipe grain, not ingredient-line grain** — see §2 for why, and what
it costs.

## The shape

### 1. A component *is* a recipe (`Recipe.kind`)

Do **not** add a `PreparedComponent` table. A component is a `Recipe` that declares intent to be reused.
Model it the house way — an enum, not a `Bool`, so impossible states stay unrepresentable
(§11; jon-platform swift-style §3):

```text
Recipe.kind: enum { dish, component }   // new, defaults to .dish; additive nullable/defaulted column
```

`.component` recipes carry the same body (ingredients + instructions), so Chicken Glace, Seed Crunch,
Dijon-Shallot Vinaigrette, Brown Butter reuse the whole recipe model — editor, scaling, snapshot,
sync, backup, import/export — for free. The extra "component metadata" the pitch wants
(`concentration 4×`, `yield`, `portionSize`, `storage`, `make/buy`, `effort`, `uses`) is **not** new
storage: it lands on the §11 intelligence-metadata track, shared with dishes, most of it optional prose.

**Promotion rule** (keeps the library from filling with one-off subassemblies — a real risk): a recipe
is a `.component` only when it is **deliberately reused** — reusable across ≥3 plausible dishes *or*
intentionally produced/stored for future cooking. A dish's private subassembly (the squash purée for one
langoustine course) stays an ingredient section or a plain recipe; it earns `.component` only when reuse
actually shows up. This is a UI/authoring gate, not a constraint the schema enforces.

### 2. The link is a directional dish→component edge table, at recipe grain

Draw the link at **recipe grain, displayed in its own "Components used" section** (the way ServeWith and
Related recipes already surface), **not** as an inline pointer on an ingredient line. Decided: we are
**not** linking at ingredient-line grain.

```text
@Table recipeComponentLink {
  id: UUID
  recipeID:    Recipe.ID   // the dish   (loose column, not a SQL FK)
  componentID: Recipe.ID   // the .component recipe (loose column)
  sortOrder: Int
  dateCreated: Date
}
```

Loose columns, not SQL FKs — same reason `RecipeRelatedRecipe` uses them: two FKs on one record violate
CloudKit's single-FK sharing rule (documented in `RecipeRelatedRecipe.swift`). But this is a **new,
directional** table, not a reuse of `RecipeRelatedRecipe` — component-usage has a direction (a dish uses
a component, not the reverse), and `RecipeRelatedRecipe` is deliberately symmetric.

**Directional ≠ one-way queryable.** The edge is read from both ends: on a dish, `WHERE recipeID = …`
renders "Components used"; on a component, `WHERE componentID = …` renders "Used in these dishes" (index
`componentID` for that reverse lookup). Direction only fixes *meaning* — it stops the app implying "Salsa
Verde uses Grilled Salmon" — it does not cost you the "what uses this?" view; it is what makes that view
correct. Note the scope line: this edge answers **"what dishes use this component?"** exactly. The looser
**"what should I make *with* Salsa Verde?"** is a different, superset feature served by dimension-coverage
reasoning (§3) plus `RecipeRelatedRecipe`/`ServeWith`, not by this table.

**Why not ingredient grain, and what it costs.** An ingredient-line link ("½ cup chicken stock" →
*your* 4× concentrate) would need a stable `ingredientRef` that survives a base-text edit — the exact
anchor-repair rabbit hole that bit variations when anchors came off model output
([`variation-anchor-repair.md`](variation-anchor-repair.md)). We decline it. The cost is real and worth
stating: we lose the **inline** behaviors — a dish can't auto-rewrite "½ cup stock" to "use 2 Tbsp of
your 4× concentrate" *at that line*, and make-extra can't anchor to a specific ingredient. What survives
at recipe grain: "this dish uses your Salsa Verde / Chicken Glace," substitute-down, "you already have
the sauce," and the capability-awareness payoff — i.e. most of the value, none of the anchor risk. If
inline ever earns its keep, it's a separate future decision with its own anchoring ADR.

### 3. The flavor vocabulary is a new **facet**, surfaced as "Dimension"

Correction to an earlier glib note: `Facet` is **not** a generic tag bag — it is Yes Chef's *taxonomy
axis* (`@Table("facets")`, migrated in as "Promote category namespaces to facets"). "Cuisine" and
"Course" *are* facets; Italian / Appetizer are values under them. So ACID / CRUNCH / UMAMI / BODY / RICH /
FRESH / ALLIUM / HEAT (the §12 menu-balance vocabulary) is **one new facet whose values are the
flavor-functions** — reusing the entire facet mechanism with **zero schema change**, not a parallel
`function` field.

Naming: leave the **table and type `Facet`** — it's shipped into the Production-bound schema, and "facet"
is genuinely correct for a taxonomy axis (a recipe's cuisine *is* a facet of it); renaming it is a
breaking change bought for taste. But `Facet` is an internal name the user never sees — the user sees the
facet's `name`. So give the new flavor axis the user-facing name **"Dimension"** (or Profile/Flavor). You
get the word you prefer exactly where it's a free seed-row + UI-label choice, while "facet" stays in code
where it's apt. Splitting them is strictly better than a rename: "Dimension" fits the flavor axis, "Facet"
still fits Cuisine/Course.

One reasoning-layer nuance for the ADR, not a storage one: for a **component** a dimension value means
"what this *provides*" (glace provides UMAMI/BODY); for a **dish** it means "what's *present*." Same
storage (a facet value tagged on a recipe); the make-extra / gap-analysis logic reads it in both senses.
Compositional reasoning ("this plate has richness and acid but no freshness → your Salsa Verde") then
falls out of the coverage `RecipeFacetCoverage` / `SeedCoverageReport` already compute — AI narrates,
determinism counts (§7.5).

## What this unlocks (all from the two additive pieces above)

- **Make-extra**, when the economics are strongly favorable: a dish needing 2 Tbsp brown butter whose
  component has a 3-week fridge life prompts "brown 8 oz, use 2 Tbsp, refrigerate the rest." Gated on
  §11 storage-life metadata, not on any inventory state.
- **Substitute-down** when the component isn't made: "2 Tbsp Chicken Glace" → "½ cup unsalted stock,
  reduced to ~2 Tbsp." Pure recipe knowledge, no ledger.
- **"You already have X" / "Improve this dish"**: dimension-coverage narration over the dish + the set of
  components you *know how to make* — capability, not stock.

Note the load-bearing word: **capability**, not inventory. A freezer of glace/roasted-garlic/brown-butter
and a fridge of vinaigrette/pickled-shallots is a set of *things you can deploy*, and the whole payoff
above is reachable **without tracking a single made-date or remaining portion.**

## Parked, on purpose: the "on hand / use soon" ledger

The pitch's shiniest surface — a Larder screen with *Available / Low / Gone*, "made Tuesday", "8 portions
in freezer", "use soon" — is **out of scope, and it should stay out.** It requires **per-instance mutable
state** (a made-date and a remaining quantity on every jar) that the cook maintains by hand. That is:

- The `PRODUCT_BRIEF.md` **non-goals** verbatim: *"Automatic pantry deduction"* and *"Restaurant-style
  inventory management."*
- Against §14's **settled boundary**: *"pantry quantity is not a feature goal … modeled as memory,
  assumptions, and shopping policy, not a stock ledger the user has to maintain."* Our existing
  `PantryPolicy` (`unlimited / threshold / alwaysConfirm`) is assumptions, not stock — correctly.
- The very thing the pitch itself named and then walked into anyway ("the road to SAP for pickled
  shallots").

Baking a contested stateful ledger into the schema we're about to make append-only at cutover would be
the worst-timed version of the mistake. If perishability ever earns its place, the bounded form already
exists: §14's **"Inventory Confirm"** — a threshold on a pantry item routes a grocery line to a review
bucket instead of silently skipping it — which reuses `PantryPolicy` and needs a real measurement layer,
not a new stock table. That is the door; this effort does not walk through it.

## Timing — why this is post-cutover, and why waiting costs nothing

Pre-ship *feels* like the moment to bake this in. It isn't, because the design is **entirely additive**:

- `Recipe.kind` is a new defaulted column; the link is a new table; facets already exist. Under the
  one-way Dev→Prod schema deploy ([ADR-0056](../decisions/ADR-0056-move-to-production-and-data-carry.md),
  [`../PROD-CUTOVER.md`](../PROD-CUTOVER.md)) the expensive, can't-take-back changes are *breaking* ones
  — rename, retype, remove. Additive columns and record types are safe to add **after** Production is
  live, as a normal reviewed migration.
- So there is **no forcing function** to build before ship, and the cutover runbook is actively going the
  other way — Phase 1 *drops* dead columns to reach a clean baseline. Widening that baseline with
  speculative, unused component schema is the anti-pattern, not the save.
- The only "if you're already certain" optimization is folding a single additive `Recipe.kind` column
  into the Phase 1 squash to skip one later migration. That is a one-migration saving and **not** a
  reason to manufacture certainty. Ship cutover clean; add components after; lose nothing.

## Slice plan (post-cutover; sketch for the future ADR)

- **S1 — `Recipe.kind` + the "Dimension" facet + authoring.** Additive column defaulting to `.dish`; a
  way to mark a recipe a component; seed the flavor-function facet (user-facing name "Dimension"). The
  promotion-rule gate lives in copy/affordance, not schema. No link yet. Ships value alone (a browsable
  component shelf, filterable by dimension).
- **S2 — the directional link + "Components used" section.** The `recipeComponentLink` table; render the
  linked components in their own section on the dish (recipe grain, no ingredient anchoring). This is the
  abstraction; everything downstream needs it.
- **S3 — make-extra + substitute-down.** §11 storage-life/effort metadata + deterministic
  economics; AI narrates. No inventory state.
- **S4 (maybe, separate ADR) — "improve this dish" / "you already have."** Dimension-coverage narration
  over dish + known components.
- **Not planned:** the on-hand/use-soon ledger. Reopen only via the §14 Inventory-Confirm door, as its
  own decision.

## Open questions for the ADR

1. Ingredient-line linking is **declined** (see §2), so no anchor-repair work. Revisit only as a separate
   future decision with its own anchoring ADR if inline behaviors ever earn their keep.
2. Does a `.component` recipe show in the main library list, a separate shelf, or both? (Browsability vs.
   noise.) And is "Dimension" the right user-facing label, or Profile/Flavor?
3. Import/export + backup coverage for `kind` and the link table (old JSON must still decode — the
   §Phase-1 "unknown keys ignored" property should hold).
4. Where make-extra economics live: pure core function (preferred, §7.5) with AI only phrasing it.
5. Does the pitch's `4×` concentration deserve a typed field, or is it prose until a second concrete use
   appears? (Default: prose.)
