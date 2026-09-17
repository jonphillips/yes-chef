# Effort — Prepared Components (the reusable intermediate layer)

**Status:** Designed (proposal) — **not dispatched, not an ADR.** Feeds a future ADR; nothing here
is ratified. Explicitly **post-cutover** work (see Timing).
**Summary:** Give cooking its missing middle layer — `ingredients → prepared components → dishes` —
by letting a recipe *be* a reusable component and letting a dish *link an ingredient line to* that
component. The abstraction is a `Recipe.kind` enum plus one component↔dish **edge table**; it is
entirely **additive** schema. The stateful "what's in my larder right now / use soon" inventory ledger
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

**The one genuinely missing abstraction** — the load-bearing thing — is that **an ingredient line cannot
point at another recipe.** `RecipeRelatedRecipe` links *recipe→recipe*; `RecipeServeWith` is loose title
strings. Neither lets "½ cup chicken stock" in a dish resolve to *your* Chicken Stock Concentrate. That
edge is what unlocks make-extra, inline-expand, and "you already have the sauce." It is the function-call
factoring a cook with a software brain keeps reaching for. Everything else is polish on top of it.

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

### 2. The component↔dish link is an **edge table**, not an ingredient FK

The obvious move — put `relatedRecipeID` on the ingredient row so "2 Tbsp Chicken Glace" points at the
component — **fails our CloudKit constraint.** An ingredient already carries one foreign key (to its
recipe); a second FK on the same record violates CloudKit's single-FK sharing rule. This is not
hypothetical: `RecipeRelatedRecipe.swift` already documents and works around exactly this ("two SQL
foreign keys would violate CloudKit's single-FK sharing rule"). So the link wants the same shape it
uses — a **loose-column edge table**:

```text
@Table ingredientComponentLink {
  id: UUID
  recipeID:      Recipe.ID      // the dish (loose column, not a SQL FK)
  ingredientRef: <stable ingredient anchor within that recipe>
  componentID:   Recipe.ID      // the .component recipe (loose column)
  dateCreated: Date
}
```

Open design question for the ADR, flagged not answered: **what is `ingredientRef`?** It must survive a
base-text edit the way variation anchors must (see [`variation-anchor-repair.md`](variation-anchor-repair.md)
for how anchoring off model output bit us — do not repeat that). Options: an anchor into the stored
ingredient grain (ADR-0040), or link at the *ingredient-section* grain instead of the line. Resolve
before building.

### 3. Reuse `Facet` for the function vocabulary

ACID / CRUNCH / UMAMI / BODY / RICH / FRESH / ALLIUM / HEAT is the §12 menu-balance vocabulary and
`Facet` is already a first-class table. Tag components (and dishes) with facets; do **not** invent a
parallel `function` field. Compositional reasoning ("this plate has richness and acid but no
freshness → your Salsa Verde") then falls out of facet coverage, which `RecipeFacetCoverage` /
`SeedCoverageReport` machinery already computes — AI narrates, determinism counts (§7.5).

## What this unlocks (all from the two additive pieces above)

- **Inline expand vs. linked component** (§16 flavor): a dish can *embed* the vinaigrette prep (stays
  self-contained) or *link* the `.component` and expand it inline for whoever doesn't have it made. Same
  duality functions have between inlining and calling.
- **Make-extra**, when the economics are strongly favorable: a dish needing 2 Tbsp brown butter whose
  component has a 3-week fridge life prompts "brown 8 oz, use 2 Tbsp, refrigerate the rest." Gated on
  §11 storage-life metadata, not on any inventory state.
- **Substitute-down** when the component isn't made: "2 Tbsp Chicken Glace" → "½ cup unsalted stock,
  reduced to ~2 Tbsp." Pure recipe knowledge, no ledger.
- **"You already have X" / "Improve this dish"**: facet-coverage narration over the dish + the set of
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

- **S1 — `Recipe.kind` + authoring.** Additive column defaulting to `.dish`; a way to mark a recipe a
  component; the promotion-rule gate lives in copy/affordance, not schema. Facet tagging already works.
  No link yet. Ships value alone (a browsable component shelf, filterable by facet).
- **S2 — the edge link + inline expand.** The `ingredientComponentLink` table; resolve the
  `ingredientRef` anchoring question first; render a linked ingredient with expand-inline vs.
  view-component. This is the abstraction; everything downstream needs it.
- **S3 — make-extra + substitute-down.** §11 storage-life/effort metadata + deterministic
  economics; AI narrates. No inventory state.
- **S4 (maybe, separate ADR) — "improve this dish" / "you already have."** Facet-coverage narration over
  dish + known components.
- **Not planned:** the on-hand/use-soon ledger. Reopen only via the §14 Inventory-Confirm door, as its
  own decision.

## Open questions for the ADR

1. `ingredientRef` grain and anchor-repair story (line vs. section; survive base edits) — the S2 blocker.
2. Does a `.component` recipe show in the main library list, a separate shelf, or both? (Browsability vs.
   noise.)
3. Import/export + backup coverage for `kind` and the link table (old JSON must still decode — the
   §Phase-1 "unknown keys ignored" property should hold).
4. Where make-extra economics live: pure core function (preferred, §7.5) with AI only phrasing it.
5. Does the pitch's `4×` concentration deserve a typed field, or is it prose until a second concrete use
   appears? (Default: prose.)
